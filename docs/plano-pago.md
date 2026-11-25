# Plano gratuito e plano pago

Estado: **proposta para decidir**. Nada aqui está implementado. Relacionado com [[plano]], [[design]], [[varios-cuidadores]], [[fotos-de-receitas]], [[diario-do-cuidador]], [[diario-de-sinais]], [[consultas-e-analises]], [[motivacao]] e [[politica-privacidade-rascunho]].

> **Para quem vai implementar: desenhar primeiro.** Os ecrãs desta funcionalidade (a apresentação do plano, o estado da subscrição, a gestão) desenham-se no artefacto do Claude Design (https://claude.ai/artifact/M1NgwcwbWDTxp2fK6r7s9R, ver [[design]]) antes de qualquer código na app. A lista está em "Desenho (fazer primeiro)". Os limites e a verificação no servidor podem avançar em paralelo.

## Decisões já tomadas

- A app é **gratuita no essencial e tem um plano pago com extras.**
- **Sem anúncios e sem venda de dados**, nunca. É uma promessa de produto e entra na [[politica-privacidade-rascunho]].
- A app **não substitui o médico**: nenhum extra pago pode ser uma "análise" ou um "conselho".
- Os utilizadores são um **misto**: famílias, pessoas autónomas e cuidadores. O plano tem de servir bem as famílias sem prejudicar quem usa a app sozinho.

## Princípios

1. **A segurança é sempre gratuita.** Tomas, alarmes, alertas de toma não confirmada, alertas de receita a acabar e o registo do histórico nunca ficam atrás de pagamento. Se um alerta falhar porque o plano acabou, isso é um risco de saúde.
2. **A acessibilidade é sempre gratuita.** Modo simples, tamanho de letra, alto contraste, leitura em voz alta e confirmação por voz ([[widget-e-modo-simples]]) nunca se cobram. Quem mais precisa deles é quem mais teria dificuldade em pagar.
3. **Cobra-se o que custa a gerar ou o que serve famílias maiores:** armazenamento (fotos, anexos), mais pessoas acompanhadas, mais cuidadores e o conforto extra (resumos, diários).
4. **Um plano que acaba nunca apaga nem desliga nada de seguro.** Ver "Quando o plano acaba".
5. **Os direitos do RGPD nunca se cobram.** Exportar e apagar os dados é gratuito, sempre.
6. **Preço claro, sem armadilhas.** Sem contagens decrescentes, sem textos de culpa, sem cobrar sem avisar.
7. **Quem não paga nunca vê o pedido onde não deve.** O telemóvel de uma pessoa acompanhada nunca vê nada sobre planos.

## O que é gratuito e o que é pago

Esta é a **proposta de partida**, para discutir. Os números (2 pessoas, 2 cuidadores) são hipóteses a validar com utilizadores.

| Funcionalidade | Gratuito | Pago | Porquê |
|---|:-:|:-:|---|
| Tomas, alarmes, alertas, histórico completo | sim | | Segurança |
| Receitas, stock, reposição, pausa ([[reposicao-stock]]) | sim | | Núcleo do produto |
| Funcionar sem rede ([[fila-offline]]) | sim | | Segurança |
| Modo simples, voz, alto contraste, tamanho do texto | sim | | Acessibilidade |
| Widget no ecrã inicial | sim | | Ajuda a registar a tempo |
| Resumo semanal, sequência, marcos, mensagens da família ([[motivacao]]) | sim | | Mantêm o hábito, que é segurança |
| Notas de sintomas e efeitos ([[sintomas-e-efeitos]]), histórico completo | sim | | Ajuda a levar informação à consulta |
| Consultas e análises, sem anexos ([[consultas-e-analises]]) | sim | | Organização básica |
| **Pessoas acompanhadas** | até 2 | mais de 2 | Famílias maiores ou cuidadores profissionais |
| **Cuidadores por pessoa** | dono + 1 | mais de 2 | Custo de suporte e de alertas |
| Diário do cuidador ([[diario-do-cuidador]]) | | sim | Só faz sentido em equipa |
| Diário de sinais ([[diario-de-sinais]]) | | sim | Mais dados, uso avançado |
| Fotos de receitas e anexos ([[fotos-de-receitas]]) | | sim | Custa armazenamento |
| Resumo para o médico em PDF | | sim | Conforto extra |
| Exportação RGPD e apagar a conta | sim | | É um direito: nunca se cobra |

Regras que atravessam a tabela:
- **Quem paga é o dono do perfil**, e as vantagens valem para o perfil **e para todos os cuidadores dele**. Uma família paga uma vez, não cada pessoa.
- Um cuidador sem plano que é convidado para um perfil com plano **usa tudo** nesse perfil.
- No telemóvel da pessoa acompanhada, tudo o que o dono tem pago funciona sem nunca mostrar um pedido de pagamento.

## Quando o plano acaba

Nunca se perde segurança nem dados. As regras:

| Situação | O que acontece |
|---|---|
| Tem 3 pessoas e deixa de pagar | As **3 mantêm** tomas, alarmes e alertas. Só não pode **adicionar** novas pessoas além das 2 gratuitas |
| Tem 3 cuidadores e deixa de pagar | Os 3 **mantêm** o acesso. Só não se podem convidar mais |
| Tem fotos e anexos | Ficam **guardados e legíveis**, e deixa de se poder acrescentar novas |
| Tem diário do cuidador e de sinais | Ficam **guardados e legíveis**, e deixa de se poder escrever |
| Quer apagar ou exportar | Sempre possível, sem plano |
| Volta a pagar | Tudo volta a funcionar de imediato, sem perder nada |

Se alguém precisar de reduzir (por exemplo, apagar uma pessoa), o limite deixa de pesar sozinho, **mas a app nunca desliga a segurança de uma pessoa por causa de um limite**.

Período de graça: 7 dias depois de a loja avisar que a renovação falhou, antes de a subscrição passar a "expirada", para um cartão caducado não fechar as portas a ninguém.

## Como se cobra (técnica)

### Lojas

Numa app móvel, as subscrições de funcionalidades digitais têm de passar pelas **lojas** (Google Play Billing, Apple In-App Purchase). A app não recebe pagamentos diretamente nem guarda dados de cartões. As lojas ficam com uma percentagem (**confirmar as taxas atuais** antes de fixar preços; os programas para pequenos programadores reduzem-nas). A versão web em Chrome só serve para testar durante o desenvolvimento e não vende nada.

### Servidor

O servidor é a fonte de verdade sobre o plano; a app só mostra.

```sql
create table subscricoes (
  user_id uuid primary key references users (id) on delete cascade,
  plano text not null check (plano in ('gratuito', 'familia')),
  estado text not null check (estado in ('ativa', 'em_graca', 'expirada', 'cancelada')),
  loja text check (loja in ('google', 'apple')),
  ref_loja_hash bytea,               -- identificador da compra, só o hash
  expira_em timestamptz,
  atualizada_em timestamptz not null default now()
);
```

- **Verificação:** quando a app diz "comprei", o servidor **confirma com a loja** (as APIs do Google Play e da Apple) e só então atualiza. Nunca se confia na app.
- **Atualizações:** as notificações das lojas (Google: RTDN por Pub/Sub; Apple: App Store Server Notifications) chegam a uma rota própria, com assinatura verificada e tratamento **idempotente** (pelo identificador da notificação), para renovações, cancelamentos e reembolsos.
- **Limites num só sítio:** uma função `limitesDe(userId)` devolve `{ maxPessoas, maxCuidadoresPorPessoa, diarioCuidador, sinais, imagens, resumoPdf }`. Todas as rotas que criam pessoas, convites, imagens, notas de diário e sinais passam por ela e devolvem `plano_necessario` (402) **só** quando se tenta **criar** algo além do limite. Leituras nunca são bloqueadas.
- **Quem paga:** o limite calcula-se pelo **dono do perfil** (`profile_access.papel = 'owner'`). Para um cuidador convidado, vale o plano do dono do perfil onde está.
- **Passar a titularidade** ([[varios-cuidadores]], fase 3): o plano **não acompanha** o perfil. O novo dono tem 30 dias de plano emprestado para decidir, e depois aplicam-se as regras acima.

### Opção de serviço de terceiros

Um serviço como o RevenueCat trata de recibos e de ambas as lojas. A vantagem é poupar trabalho; o custo é um terceiro que vê as compras (**não** os dados de saúde). Decidir antes de começar. Se se usar, apenas o identificador interno da conta se partilha, nunca o email nem nada de saúde.

### Privacidade

- **Sem anúncios, sem venda de dados**, escrito na política e repetido no ecrã do plano.
- **Sem SDKs de análise que vejam o uso de saúde.** Métricas só agregadas e do servidor (quantas subscrições, quantas renovam), nunca "o que cada pessoa tomou".
- Os dados de pagamento ficam nas lojas; a nossa base só guarda o estado e o hash da referência.

## Experiência de utilizador

### Regras

- **Mostrar o plano só quando a pessoa toca numa funcionalidade paga**, uma vez por funcionalidade, e com "Agora não" sempre ao lado. Nunca em cima de alarmes, tomas ou alertas.
- Linguagem clara: o que se ganha, o que custa, quando se renova, como cancelar (e o link para a loja).
- **Experimentar:** um mês grátis com tudo (a loja trata do período e da conversão).
- Nunca aparece no telemóvel da pessoa acompanhada.
- Os extras pagos aparecem **sempre visíveis** (não escondidos), com um pequeno sinal "Plano" e a explicação do que é.

### Textos

- "Com o plano Família pode acompanhar mais pessoas e partilhar fotos e diários com os outros cuidadores."
- "Os alarmes, os alertas e o histórico são sempre gratuitos."
- "Nunca mostramos anúncios nem vendemos os seus dados."

## Preço

**A definir.** Não se fixa um número antes de validar. Método sugerido:

1. **Estimar o custo por perfil ativo:** armazenamento de fotos (ver a estimativa em [[fotos-de-receitas]]), notificações push, servidor, e as taxas das lojas.
2. **Testar a disponibilidade para pagar** com 10 a 20 famílias do círculo próximo (perguntas diretas, sem ancorar com um valor).
3. **Opções a comparar:**

   | Modelo | Vantagem | Desvantagem |
   |---|---|---|
   | Plano único "Família" (mensal e anual) | Simples de explicar | Quem só quer mais uma pessoa paga tudo |
   | Plano "Família" + extra de fotos | Cobre melhor o custo de armazenamento | Dois preços, mais confuso |
   | Anual com desconto | Menos churn | Pagamento maior de uma vez |

4. **Recomendação:** começar com um **plano único**, mensal e anual (o anual com cerca de dois meses grátis em relação ao mensal), e rever após os primeiros meses de uso.

## Aspetos legais (Portugal e UE)

- **Subscrições em lojas:** informação de preço com IVA incluído, renovação automática bem visível e cancelamento fácil já são parte das regras das lojas; mesmo assim, a app repete-as.
- **Direito de livre resolução (14 dias)** em conteúdos digitais: tratado pelas lojas; confirmar o texto aplicável.
- **Não fazer alegações de saúde** no ecrã do plano ("controle a sua tensão", "previne…"). Só se descreve o que a app **regista** e **lembra**.
- **Dispositivo médico:** manter a regra "só regista e mostra" ([[diario-de-sinais]]) evita entrar nesse âmbito. Confirmar com apoio jurídico antes de cobrar pelo diário de sinais.
- Atualizar a [[politica-privacidade-rascunho]] e a [[dpia-rascunho]] (tratamento do estado da subscrição, ligação às lojas).

## Desenho (fazer primeiro)

No artefacto do Claude Design, nos temas claro e escuro:

1. **Apresentação do plano** ("O que inclui", gratuito e pago, preço, "Experimentar", "Agora não").
2. **Pedido no ponto de uso:** o cartão que aparece ao tocar numa funcionalidade paga (uma por funcionalidade).
3. **Estado da subscrição** (ativa, em período de graça, expirada, cancelada) e como gerir na loja.
4. **Limites:** "Já tem 2 pessoas. Com o plano pode acompanhar mais." sem tirar nada às que já tem.
5. **Quando o plano acaba:** mensagem tranquila, a explicar o que continua a funcionar.
6. **Compra concluída:** o ecrã de sucesso unificado.
7. Confirmar que **nada disto aparece** no telemóvel da pessoa acompanhada.

Decisões a resolver no desenho:
- Onde fica o acesso à gestão do plano, fora das Definições, mas fácil de encontrar (proposta: no ecrã da pessoa, junto de "Quem cuida").
- Como assinalar um extra pago sem o tornar um alvo de pressão.

## Ordem de trabalho

1. **Decidir** com este documento: tabela gratuito/pago, preço e se se usa um serviço de terceiros.
2. **Desenho** e aprovação.
3. **Limites no servidor** com tudo gratuito durante a fase de testes (`limitesDe` devolve os limites do plano pago a todos). Permite construir e testar sem cobrar.
4. Integração com as lojas (compra, verificação, notificações) e a tabela `subscricoes`.
5. Ecrãs da app (plano, pedidos, estado).
6. Lançar o plano pago **só quando** houver pelo menos dois extras prontos e fiáveis (por exemplo, vários cuidadores e fotos), para o pagamento fazer sentido.
7. Atualizar [[politica-privacidade-rascunho]], [[dpia-rascunho]] e [[design]].

## Testes

- Cada limite: criar além do limite dá `plano_necessario`; **ler** nunca é bloqueado.
- Plano que acaba: as pessoas e os cuidadores que já existiam continuam com alarmes, alertas e acesso; só se bloqueia criar novos.
- A verificação com a loja: um recibo falso não ativa nada; uma notificação repetida não duplica.
- O telemóvel da pessoa nunca recebe `plano_necessario` nem texto sobre planos.
- O cuidador convidado usa as vantagens do plano do dono.
- Exportar e apagar a conta funcionam sem plano.

## Riscos

- **Cobrar demais cedo:** com poucos extras prontos, a subscrição não se justifica. Por isso o passo 6.
- **Sentir-se "refém":** quem acompanha uma pessoa frágil não pode sentir que perde segurança se não pagar. Os princípios 1 e 4 existem para isso.
- **Dependência das lojas:** as regras e as taxas mudam. Confirmar antes de lançar.
- **Quem paga é uma pessoa e quem usa são várias:** o plano do dono vale para todos, e isso tem de se perceber no ecrã.

## Perguntas em aberto

1. Os limites (2 pessoas, 2 cuidadores) estão bem?
2. Usar um serviço de terceiros para as compras ou integrar diretamente as lojas?
3. Plano único ou com extras separados (por exemplo, só fotos)?
4. As notas de sintomas ficam mesmo todas gratuitas?
5. Lançar só com Android ou com iPhone também (o iPhone exige macOS ou a ferramenta `xtool`)?
