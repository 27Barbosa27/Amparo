# Avaliação de Impacto sobre a Proteção de Dados (DPIA): rascunho

> **Rascunho técnico.** Descreve o que o sistema faz hoje, para ser revisto e assinado por quem for o responsável pelo tratamento, de preferência com apoio jurídico e do encarregado de proteção de dados (EPD), se aplicável. Os campos `[a preencher]` dependem de decisões ou de dados que não estão no código. Não é aconselhamento jurídico.

## 1. Descrição do tratamento

| | |
|---|---|
| **Responsável** | `[a preencher: nome, NIF, morada, contacto]` |
| **Produto** | Amparo, app de lembretes e registo de medicação para cuidadores e para as pessoas que acompanham |
| **Finalidade** | Lembrar a toma de medicamentos, registar se foi tomada, avisar o cuidador quando não é confirmada |
| **Âmbito regulatório** | Lembrete e registo. Não sugere doses, não avisa de interações, não dá aconselhamento clínico (fora de dispositivo médico) |
| **Titulares** | (a) cuidadores, com conta; (b) pessoas acompanhadas, **sem conta**, muitas vezes idosas |
| **Fundamento (art. 6.º)** | Consentimento (cuidador); execução do serviço pedido |
| **Condição do art. 9.º** | Consentimento explícito para dados de saúde. A pessoa acompanhada não tem conta: o cuidador **declara que tem a sua autorização ou a do representante legal** (data e versão do texto guardadas em `profile_access`) |

### Dados tratados
| Categoria | Dados | Como são guardados |
|---|---|---|
| Conta do cuidador | nome de exibição, email, telefone (opcional), versão e data do consentimento | email: HMAC (para encontrar a conta) **e** cópia cifrada AES-256-GCM; telefone cifrado; palavra-passe só como hash Argon2id |
| Pessoa acompanhada | pseudónimo (não se pede o nome real), fuso horário, tamanho de texto | em claro (não sensíveis); chave de cifra própria por perfil |
| **Saúde** | nome do medicamento, notas, dose | **cifrados na aplicação** com a chave do perfil (AES-256-GCM) |
| Horários e registos | horas das tomas, estado (tomada, saltada, falhada), quem registou, hora real | em claro, ligados a um UUID de perfil, sem nomes; só fazem sentido com a chave do perfil para saber qual é o medicamento |
| Técnicos | tokens (só hash), tokens de push (cifrados), IP e ação na auditoria | ver secção 3 |

## 2. Necessidade e proporcionalidade
- **Minimização:** o perfil usa um pseudónimo ("Avó Rosa"); a criação não pede dados sensíveis; o telefone e o email são os únicos dados pessoais diretos.
- **Sem Firebase como backend:** só se usa o envio de notificações. Sem Firestore, Authentication, Analytics nem Crashlytics.
- **Notificações:** só levam um tipo de evento e um identificador opaco. **Nunca** dados de saúde, nomes de medicamentos nem nomes de pessoas (verificado por teste automático). O texto visível é genérico ("Tem um aviso novo").
- **Alarmes locais:** as horas dos alarmes ficam no telemóvel, não dependem de servidores externos.
- **Retenção:** `[a preencher: prazos]`. Sugestão: dados de saúde enquanto o perfil existir e até ao pedido de apagamento; auditoria `[a preencher: p. ex. 12 meses]`; backups 14 dias.
- **Direitos:** acesso e portabilidade (`GET /auth/me/exportacao`, `GET /profiles/:id/exportacao`); retificação (editar); apagamento (apagar perfil e apagar conta, com apagamento da chave cifrada, ver crypto-shredding); limitação e oposição `[a preencher: procedimento]`. A pessoa acompanhada exerce os direitos **através do cuidador** ou do responsável.

## 3. Riscos e medidas

| # | Risco | Prob. | Impacto | Medidas já implementadas | Risco residual |
|---|---|---|---|---|---|
| 1 | Acesso de um cuidador a perfis de outra pessoa (IDOR) | média | alto | uma única verificação de acesso à frente de todas as rotas; perfil alheio responde como inexistente; testes de IDOR em todas as rotas | baixo |
| 2 | Fuga da base de dados | baixa | alto | dados de saúde cifrados com chave por perfil; chaves fora da base de dados e fora dos backups; hash Argon2id; emails com HMAC | baixo |
| 3 | Roubo de um telemóvel de pessoa ligado por código | média | médio | token de dispositivo de âmbito de **um só perfil**; só lê/regista tomas e contacto; revogação imediata pelo cuidador; ver e revogar dispositivos | baixo |
| 4 | Adivinhar o código de ligação (6 dígitos) | baixa | médio | 15 min, uso único, só o hash guardado; limite por IP e global; mesma resposta para inválido/expirado/usado | baixo |
| 5 | Roubo de credenciais / força bruta | média | alto | Argon2id; bloqueio progressivo; limite por IP; refresh com rotação e deteção de reutilização; Apple/Google validados no servidor | baixo |
| 6 | Alteração ou apagamento de registos de auditoria | baixa | médio | `audit_logs` só de acrescentar: trigger **e** `REVOKE` ao papel de execução; escritas e leituras de dados de saúde registadas | baixo |
| 7 | Dados de saúde a sair para terceiros (push, logs) | baixa | alto | mensagens só com ids opacos; registos de pedidos sem corpo, query, cabeçalhos nem IP; erros internos sem detalhes | baixo |
| 8 | Perda de dados | baixa | alto | backups cifrados (gpg, chave pública na VPS), cópia fora da VPS, **teste de restauro mensal** | baixo |
| 9 | Perda das chaves de cifra | baixa | muito alto | guardadas num cofre fora da VPS; procedimento documentado | médio até haver cofre e ensaio `[a preencher]` |
| 10 | Falha de um alarme (dano real: dose falhada) | média | alto | alarmes **locais**; o push nunca é a garantia; ecrã "Alarmes fiáveis"; alerta ao cuidador de toma não confirmada. Risco clínico fora do âmbito de software de lembrete, mas deve ser comunicado ao utilizador | médio `[a avaliar com o spike de alarmes]` |
| 11 | Subprocessadores fora da UE (Google, Apple) | certa | médio | só identificadores opacos e tokens; DPA da Google aceite; cláusulas contratuais-tipo | baixo `[a confirmar]` |
| 12 | Tratamento de dados de pessoas vulneráveis sem capacidade de consentir | média | alto | consentimento do cuidador com declaração de autorização/representação, versionada; nota de privacidade simples no primeiro ecrã do telemóvel da pessoa | médio `[rever com apoio jurídico]` |

## 4. Subprocessadores e transferências
`[a preencher: contratos e localização exata]`

| Subprocessador | Para quê | Dados | Localização |
|---|---|---|---|
| Fornecedor da VPS | alojamento | tudo, cifrado como descrito | UE `[a escolher]` |
| Google (Firebase Cloud Messaging) | enviar notificações | token do telemóvel, tipo de evento, id opaco | `[a confirmar; transferência para fora da UE]` |
| Apple (APNs) | notificações no iPhone | idem | idem |
| Apple / Google (início de sessão) | autenticação opcional | identificador estável e email (se partilhado) | idem |
| Fornecedor de email | recuperação de palavra-passe | email do cuidador, link com token | UE `[a escolher]` |
| Armazenamento de backups | cópias cifradas | backups cifrados (ilegíveis sem a chave privada) | UE `[a escolher]` |

## 5. Conclusão e consulta
- **Resultado:** os riscos 1 a 8 e 11 ficam baixos com as medidas implementadas e testadas. Ficam por fechar os riscos **9, 10 e 12** (cofre de chaves com ensaio de recuperação, fiabilidade real dos alarmes, e a base legal para pessoas sem capacidade).
- **Consulta prévia à CNPD (art. 36.º):** `[decidir após fechar 9, 10 e 12]`.
- **Revisão:** a cada alteração relevante do tratamento e, pelo menos, uma vez por ano. Próxima revisão: `[a preencher]`.

Aprovação: `[nome, cargo, data]`
