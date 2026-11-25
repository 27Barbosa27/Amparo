# Funcionar sem rede (fila offline)

Estado: por implementar. Está previsto em [[plano]] (secção Sync: "fila offline com idempotência, background fetch, estado offline visível").

## Problema

Hoje, marcar uma toma sem rede falha com `sem_rede` e a toma fica por registar. Para uma app de medicação isto é grave:

- a pessoa tomou o medicamento e a app não o sabe;
- o cuidador vê uma toma falhada que não foi falhada;
- a adesão (o dado que se mostra ao médico) fica errada.

A rede falha mais do que parece: elevadores, campo, dados esgotados, o telemóvel da pessoa idosa sem Wi-Fi.

## O que se quer

1. **Marcar tomada ou saltar sem rede:** funciona, fica guardado no telemóvel e envia-se sozinho quando há rede.
2. **O estado é visível:** uma faixa "Sem ligação. As confirmações ficam guardadas" e um sinal nas tomas ainda por enviar.
3. **Sem perdas nem duplicados:** reiniciar a app, ficar horas sem rede ou reenviar o mesmo pedido nunca duplica uma toma.
4. **Conflitos resolvidos:** se o cuidador marcou a mesma toma entretanto, ganha o evento mais recente (já é a regra do servidor).

Fora de âmbito (fases seguintes): criar e editar receitas sem rede; ver tomas de dias que nunca foram carregados; alarmes locais (são outra funcionalidade).

## O que o servidor já faz (não é preciso mexer)

`backend/src/tomas/registo.ts`, função `mudarEstado`:

- **Idempotência:** `idempotencyKey` (8 a 100 caracteres) guardada na toma. Um reenvio com a mesma chave devolve o resultado sem repetir.
- **Conflito:** `eventoEm` é a hora a que a pessoa fez a ação. Numa toma já registada, ganha o evento mais recente; se não for mais recente, responde `409 toma_ja_registada`.
- **Hora do evento:** nunca é do futuro (fica limitada a agora). Há um teste: "conflito da fila offline: ganha o evento mais recente".
- **Hora da toma:** `tomadaEmUtc` tem de estar entre "uma hora antes da hora prevista" e "agora"; senão `400 hora_invalida`.

Há então só trabalho na app. Há um defeito a corrigir: **a app nunca envia `eventoEm`** (`repositorio_api.dart`, `marcarTomada` e `saltar` enviam só `idempotencyKey`). Sem isso, o servidor usa a hora a que o pedido *chega*, não a hora a que a pessoa carregou, e a regra do conflito perde o sentido numa fila. Passa a enviar-se sempre.

## Desenho

### Peças

| Peça | Função |
|---|---|
| `FilaOffline` (novo, `lib/dados/fila_offline.dart`) | Guarda as ações pendentes, no disco, e entrega-as por ordem |
| `RepositorioComFila` (novo) | Envolve o `RepositorioApi`; quem o usa não nota a diferença |
| Estado da fila | Quantas ações pendentes, se está a enviar, para a faixa de aviso |

`RepositorioComFila implements Repositorio` e delega tudo no `RepositorioApi`, exceto `marcarTomada` e `saltar`. A ligação ao telemóvel da pessoa (`LigacaoApi`) usa o mesmo repositório, por isso o telemóvel do idoso também ganha isto sem mais trabalho.

### Uma ação na fila

```dart
class AcaoPendente {
  final String id;          // local, para apagar
  final String perfilId;
  final String tomaId;
  final TipoAcao tipo;      // tomada | saltada
  final DateTime eventoEm;  // quando a pessoa carregou (UTC)
  final DateTime? tomadaEm; // a hora real da toma, se escolheu "há 1 hora"
  final String chave;       // idempotencyKey: gera-se UMA vez, ao criar a ação
  final int tentativas;
}
```

**A chave gera-se ao pôr a ação na fila, não ao enviar.** Hoje `_chave()` gera uma nova em cada chamada; numa fila, o reenvio tem de levar a mesma chave, senão o servidor trata-o como pedido novo.

### Fluxo ao marcar

1. Tentar o pedido normal (com `chave` e `eventoEm` novos).
2. Se der `sem_rede` (ou erro 5xx / tempo esgotado): guardar a ação na fila e devolver uma `Toma` com o estado novo e `porEnviar: true`. A pessoa vê a toma marcada.
3. Outro erro (`409`, `400`, `404`): comportamento atual, mostra o erro.

Nunca se põe na fila um erro que o servidor decidiu (4xx): reenviá-lo daria sempre o mesmo resultado.

### Quando se envia a fila

- Ao abrir a app e quando volta ao primeiro plano (`AppLifecycleState.resumed`; o plano já o prevê para o `since`).
- Depois de qualquer pedido que corra bem (prova de que há rede).
- Com um temporizador de repetição (30 s, a duplicar até 5 min) enquanto houver ações pendentes.
- Botão "Tentar agora" na faixa de aviso.

Opcional mais tarde: `connectivity_plus` para reagir logo quando a rede volta. Não é necessário no início.

### Resultado de cada envio

| Resposta | O que fazer |
|---|---|
| `2xx` | Apagar da fila |
| `409 toma_ja_registada` | Apagar; recarregar as tomas; avisar "A toma de X já estava registada" |
| `404 toma_nao_encontrada` | Apagar (a toma deixou de existir: receita apagada ou refeita) |
| `400 hora_invalida` | Apagar; avisar que a hora já não era válida |
| `401` | Manter; a renovação da sessão trata do resto, volta a tentar |
| `sem_rede`, `5xx`, `429` | Manter; subir `tentativas`; esperar mais |

### Ordem e agrupamento

- Enviar por `eventoEm` crescente.
- Se há duas ações pendentes na mesma toma (marcou, depois saltou), ficar só com a mais recente.
- Ações com mais de 7 dias: não enviar, apagar e avisar. O servidor já terá marcado a toma como falhada e a hora deixou de ser válida.

### Dados no telemóvel

- **Fila:** contém só ids e horas (nenhum nome de medicamento nem dose). Não é preciso cifrar além do que o sistema já faz. Guardar com `shared_preferences` (funciona também na versão web, usada para testar) como lista JSON. Se vier a crescer, migrar para uma base local.
- **Ao terminar a sessão** (ou desligar o telemóvel da pessoa): se a fila não estiver vazia, avisar "Há N confirmações por enviar. Se sair agora, perdem-se." e deixar enviar antes. Nunca apagar em silêncio.
- **Cada utilizador tem a sua fila:** a chave de armazenamento leva o id do perfil, para uma conta nova não herdar a de outra.

### Ver as tomas sem rede (fase 2)

Sem ler as tomas, não se chega a marcá-las. Fase 2: guardar a última lista de "Hoje" recebida e mostrá-la sem rede, com a faixa de aviso. **Isto tem nomes e doses de medicamentos, ou seja, dados de saúde:** guardar cifrado (chave em `flutter_secure_storage`, dados num ficheiro cifrado) e apagar ao terminar a sessão. Está incluída aqui por completo, mas só deve avançar depois de se ter confirmado com a DPIA ([[dpia-rascunho]]) que este armazenamento local é aceitável.

Por isso a fase 1 funciona quando a app já está aberta com as tomas carregadas e a rede cai (o caso mais comum). Abrir a app *já sem rede* só passa a funcionar na fase 2.

### Interface

- **Faixa** no topo de "Hoje": "Sem ligação. As confirmações ficam guardadas." com o contador "3 por enviar" e "Tentar agora". Desaparece quando a fila esvazia. Reaproveitar o `semRede` que o ecrã já recebe (`cuidador_hoje.dart:129`).
- **Toma por enviar:** um pequeno relógio ou "a enviar…" no cartão, em vez do visto definitivo. Passa a visto quando o servidor confirma.
- **"Desfazer" desativado** enquanto a toma não chegou ao servidor (só funciona até 1 minuto depois do registo, no servidor). Em vez disso, cancelar a ação da fila.
- Mensagem curta quando a fila esvazia depois de ter tido rede: "Enviámos 3 confirmações".
- Textos em pt-PT, sem jargão ("fila", "sincronizar" não aparecem ao utilizador).

## Trabalho, por ordem

1. **Corrigir já** o envio de `eventoEm` em `marcarTomada` e `saltar` (e `tomadaEmUtc` quando há hora escolhida). Um teste a verificar o corpo do pedido.
2. `AcaoPendente` e `FilaOffline` (guardar, ler, ordenar, agrupar), com testes de unidade, incluindo reiniciar a app a meio.
3. `RepositorioComFila` e o envio com as regras da tabela de respostas. Testes com uma API falsa que falha e depois responde.
4. Ligar ao ciclo de vida da app e ao temporizador.
5. Faixa, sinal "por enviar" e aviso ao terminar sessão. Testes de widget.
6. Fase 2 (leitura sem rede, cifrada), só depois do ponto da DPIA.

## Testes

- Marcar sem rede: a toma aparece marcada; a ação está na fila com `chave` e `eventoEm`.
- Reiniciar a app: a fila mantém-se e envia-se.
- Dois reenvios da mesma ação: o servidor recebe a mesma `chave` (não duplica).
- Marcar e depois saltar a mesma toma offline: só a última segue.
- `409` apaga a ação e recarrega; `sem_rede` mantém.
- Ações com mais de 7 dias são descartadas com aviso.
- Terminar sessão com a fila cheia pede confirmação.
- Backend: já existe teste de idempotência e conflito; acrescentar um para "reenvio depois de uma hora" se o `eventoEm` for antigo.

## Riscos

- **Relógio do telemóvel errado:** o servidor limita `eventoEm` a "agora", mas um relógio atrasado dá eventos "antigos" que perdem conflitos contra o cuidador. Aceitável e raro.
- **Duas pessoas, um perfil, os dois offline:** ganha quem carregou por último, que é a regra de [[plano]]. O histórico fica completo no servidor.
- **A fila nunca esvazia** (erro permanente que não identificámos): o limite de 7 dias e o botão "Tentar agora" evitam que fique para sempre; registar a contagem de tentativas para poder diagnosticar.
