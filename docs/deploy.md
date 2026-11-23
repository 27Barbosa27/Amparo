# Deploy do Amparo (VPS na UE)

Podman rootless + Caddy com TLS automático + PostgreSQL. Tudo definido em `deploy/compose.prod.yaml`.

## 1. Antes de começar

- **VPS Linux na UE** (por causa do RGPD). Um utilizador normal, sem root, para correr os contentores.
- **Um domínio** para a API (por exemplo `api.amparo.pt`) com o registo DNS A/AAAA a apontar para a VPS.
- **Firewall**: só 22 (SSH, de preferência só por chave), 80 e 443 (TCP e UDP).
- No Podman rootless, abrir as portas 80 e 443: `sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80` (e pôr a linha em `/etc/sysctl.d/`).
- `podman`, `podman-compose` (ou o plugin `docker-compose`), `gpg` e `git`.

## 2. Segredos

```bash
cp deploy/prod.env.example deploy/.env.prod
chmod 600 deploy/.env.prod
```

Preencher `deploy/.env.prod` (gerar cada valor com os comandos que estão no ficheiro). **O ficheiro nunca vai para o Git.**

**As duas chaves mais importantes são `EMAIL_ENC_KEY` e `PROFILE_MASTER_KEY`.** Sem elas, os emails e todos os dados de saúde cifrados ficam ilegíveis para sempre.
- Guardá-las num cofre (gestor de palavras-passe), **fora da VPS e fora dos backups da base de dados**.
- Se estivessem juntas com o backup, o backup deixava de proteger alguma coisa.
- Rodar a `PROFILE_MASTER_KEY` ou a `EMAIL_ENC_KEY` exige recifrar os dados (o formato guardado tem um byte de versão para o permitir). Ainda não há script para isso.

**Firebase (só Cloud Messaging):** criar o projeto, aceitar o DPA da Google na consola, criar uma conta de serviço só com a permissão de enviar mensagens e guardar o JSON em `deploy/secrets/fcm-service-account.json` (a pasta está no `.gitignore`). Sem este ficheiro, o push fica desligado e a API avisa no arranque.

## 3. Arrancar

```bash
podman compose -f deploy/compose.prod.yaml --env-file deploy/.env.prod up -d --build
podman compose -f deploy/compose.prod.yaml ps
curl https://api.exemplo.pt/health/db      # {"estado":"ok"}
```

A ordem é: base de dados → `migrar` (corre as migrações e termina) → API → Caddy. Se uma migração falhar, a API não arranca.

Para a API e o Caddy arrancarem sozinhos depois de um reinício da VPS: `loginctl enable-linger <utilizador>` e gerar as unidades systemd (`podman generate systemd` ou Quadlet).

## 4. Atualizar

```bash
git pull
podman compose -f deploy/compose.prod.yaml --env-file deploy/.env.prod up -d --build
```

Antes de uma atualização com migrações, fazer um backup (secção 5).

## 5. Backups cifrados e teste de restauro

O backup é cifrado com uma **chave pública gpg**. A VPS só tem a pública, por isso quem roubasse os backups ou a VPS não os abria.

1. No teu computador: `gpg --full-generate-key` e exportar a pública: `gpg --export --armor backups@amparo.example > backup-publica.asc`. Guardar a **privada** num cofre.
2. Na VPS: `gpg --import backup-publica.asc` e `gpg --edit-key backups@amparo.example trust` (confiança total) ou deixar o script usar `--trust-model always`, que é o que já faz.
3. Correr de hora a hora, ou pelo menos uma vez por dia (timer systemd ou cron):

```bash
set -a; . deploy/.env.prod; set +a
deploy/backup.sh          # escreve em /var/backups/amparo e apaga os com mais de 14 dias
```

4. **Copiar os backups para fora da VPS** (outra máquina ou armazenamento na UE), por exemplo com `rsync` ou `rclone`. Um backup só na mesma máquina não protege contra perder a máquina.
5. **Testar o restauro todos os meses**, numa máquina com a chave privada:

```bash
deploy/restore-test.sh amparo-20261122T030000Z.dump.gpg
```

O script cria um PostgreSQL descartável, restaura lá o backup e verifica as tabelas, as migrações e que a auditoria continua imutável. Termina com `RESTAURO OK`. (Foi testado de ponta a ponta no desenvolvimento.)

**Restaurar a sério:** parar a API, restaurar o `.dump` com `pg_restore --clean --if-exists` para a base de dados, voltar a arrancar. As chaves vêm do cofre, não do backup.

## 6. Monitorização

- **Disponibilidade:** um serviço externo (com servidores na UE) a verificar `https://api.exemplo.pt/health/db` de minuto a minuto e a avisar por email ou telemóvel se falhar duas vezes seguidas.
- **Logs:** a API escreve uma linha JSON por pedido (`podman logs amparo-api`): método, rota sem ids, estado e duração. **Nunca** há corpos, queries, cabeçalhos nem IPs. Os erros inesperados aparecem como `Erro não tratado: ...` sem dados de saúde.
- **Trabalhos agendados:** falhas aparecem como `Trabalho "minuto" falhou:` nos logs. Vale a pena um alerta sobre essa linha.
- **Auditoria:** a tabela `audit_logs` é só de acrescentar (trigger). Guardar o prazo de retenção que a política de privacidade indicar e apagar o que passar dele com uma operação deliberada (não está automático de propósito).

## 7. O que o deploy já faz por segurança

- A API corre como utilizador `node`, com sistema de ficheiros só de leitura, sem capacidades Linux e sem novos privilégios.
- A base de dados não tem portas publicadas: só a API a alcança, na rede interna.
- A API liga-se com `amparo_runtime` (papel `amparo_app`), **não** com o dono da base de dados: não tem permissão para alterar, apagar nem esvaziar o `audit_logs` (`REVOKE`, além do trigger), nem para tocar no histórico de migrações. O utilizador é criado pela migração `…05_papel-app-login` a partir de `APP_DB_PASSWORD`. Testado: a suite completa passa ligada com este papel (as 2 exceções são os testes que sondam o trigger a partir do dono).
- O código de ligação tem limite por IP e um limite global de falhas contra ataques com muitos IPs.
- O Caddy limita o tamanho dos corpos (200 KB), escreve o IP real em `X-Forwarded-For` (a API confia só nesse proxy) e põe HSTS.
- Limite global de pedidos por IP em produção, além dos limites apertados do login e da ligação por código.
- O CI corre migrações, tipos, testes, build, `npm audit` (só falha com vulnerabilidades altas ou críticas) e constrói a imagem.

## 8. Ainda por fazer (fora do código)

- **DPIA** e **política de privacidade**: há rascunhos baseados no que o sistema faz em `docs/dpia-rascunho.md` e `docs/politica-privacidade-rascunho.md`. Falta preencher os campos `[a preencher]` e a revisão jurídica.
- **Aceitar o DPA da Google** na consola do Firebase.
- **Conta Apple Developer** (paga) para push em iPhone real e para publicar.
- **Escolher o fornecedor de email** (servidores na UE, DPA assinado) e pôr o `SMTP_URL`, `EMAIL_FROM` e `APP_LINK_BASE` no `.env.prod`. O código já está pronto e foi testado contra um servidor SMTP real; qualquer fornecedor com SMTP serve.
- Aviso: o `npm audit` mostra 3 avisos moderados no `glob` usado pelo `node-pg-migrate`. Só corre as nossas migrações no deploy, sem dados de utilizadores, e o CI só falha a partir de severidade alta.
