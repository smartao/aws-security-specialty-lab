# Exam Review Log (SCS-C03)

Banco de questões de revisão, uma seção por lab, no formato do exame (múltipla escolha, múltipla resposta, ordenação, correspondência — nunca só múltipla escolha). Cada pergunta registra a resposta dada, o gabarito, o porquê de cada alternativa e a palavra-chave que deveria chamar atenção numa pergunta parecida na prova real.

Objetivo: revisão espaçada perto da prova, sem precisar reabrir o README de cada lab — e um sinal de quais domínios/conceitos precisam de mais prática, lab a lab.

---

## Lab 03 — GuardDuty

**Placar:** 4,25 / 6 — nenhum erro na alternativa central de nenhuma questão; 3 questões com *over-selection* (marcou uma alternativa errada junto da certa, sendo 5 e 6 de resposta única). Um gap conceitual real: `finding_publishing_frequency` (Pergunta 2 / Pergunta 7).

### Pergunta 1 (múltipla escolha)

Uma conta habilita o GuardDuty **sem nenhum trail do CloudTrail configurado**. Mesmo assim aparecem findings `Recon:IAMUser/*`. Por quê?

A) Ao ser habilitado, o GuardDuty cria automaticamente um trail multi-region na conta
B) O GuardDuty consome um fluxo próprio e independente de CloudTrail management events — não depende de trail nenhum configurado pelo cliente
C) `Recon:IAMUser/*` é derivado de VPC Flow Logs, não de CloudTrail
D) Findings de IAM só surgem se o AWS Config estiver ativo

**Resposta dada:** B
**Gabarito:** B — ✅ correto

- **A)** Falso — o GuardDuty nunca cria um trail; se criasse, `IsLogging` apareceria na conta e não aparece.
- **C)** Falso — `Recon:IAMUser/*` vem de CloudTrail; VPC Flow Logs alimentam os `Recon:EC2/*` e `Backdoor:EC2/*` de rede.
- **D)** Falso — nenhuma dependência de AWS Config.

**Palavra-chave:** "sem nenhum trail configurado" e mesmo assim gera finding → é a **independência de pipeline** do GuardDuty (mesmo princípio registrado na ADR-016: ele lê CloudTrail management events, VPC Flow Logs e DNS query logs por vias próprias, não pelos destinos que o cliente configura).

---

### Pergunta 2 (múltipla resposta)

Quais destas são verdadeiras sobre `finding_publishing_frequency`?

a) Afeta a latência da **1ª entrega** de um finding novo ao EventBridge
b) Afeta a entrega de **atualizações/reocorrências** de um finding já existente
c) Valores possíveis: 15 min, 1 h, 6 h
d) Afeta a latência com que o finding aparece no **console** do GuardDuty

**Resposta dada:** c, d
**Gabarito:** b, c — ⚠️ parcialmente correto (acertou c, faltou b, marcou d errado)

- **a)** ❌ Falso — a 1ª entrega de um finding **novo** ao EventBridge é sempre ~5 min, fixo; o parâmetro não mexe nisso.
- **b)** ✅ Verdadeiro — o parâmetro governa a cadência de export das **reocorrências/atualizações** de um finding que já existe.
- **c)** ✅ Verdadeiro — `FIFTEEN_MINUTES`, `ONE_HOUR`, `SIX_HOURS` (default AWS = 6 h; o Lab 03 usa 15 min).
- **d)** ❌ Falso — o **console** é quase tempo real e não é afetado; o parâmetro só controla a cadência de **export** (EventBridge + S3).

**Palavra-chave:** "console" é o distrator — nenhuma configuração de export/notificação afeta a latência do console. E "1ª entrega" vs "reocorrência": o parâmetro é sempre sobre o **repetido**, nunca sobre o primeiro.

**Para revisar antes da prova:** ver Pergunta 7 — o modelo mental de três caminhos (finding novo ≠ reocorrência ≠ console).

---

### Pergunta 3 (ordenação)

Coloque na ordem correta a investigação de um `Backdoor:EC2/C&CActivity.B!DNS`:

(i) Correlacionar o IP resolvido nos VPC Flow Logs
(ii) `get-findings` para extrair domínio, instância e timestamps
(iii) Verificar no CloudTrail o uso da IAM role da instância
(iv) Decidir a contenção

**Resposta dada:** ii, iii, i, iv
**Gabarito:** ii primeiro + iv por último são obrigatórios; a ordem i↔iii no meio é julgamento — resposta **aceita** ✅

- **ii primeiro:** levantar os fatos do finding (o quê / quando / qual recurso) antes de qualquer correlação.
- **iv por último:** conter só depois de entender o impacto.
- **i vs iii:** o modelo preferido é **ii → i → iii → iv** — depois de ler o finding, a pergunta de maior impacto é "houve conexão de fato?" (Flow Logs), que define a severidade real; só então "a credencial foi usada para pivotar?" (CloudTrail). A ordem invertida (credencial antes da rede) também se defende.

**Palavra-chave:** "decidir a contenção" no fim — contenção nunca é o primeiro passo num exercício de investigação; primeiro se estabelece o impacto.

---

### Pergunta 4 (correspondência)

Ligue cada finding à sua fonte de dados primária:

| Finding | Fonte |
|---|---|
| `Backdoor:EC2/C&CActivity.B!DNS` | DNS query logs (Route 53 Resolver) |
| `Policy:S3/BucketAnonymousAccessGranted` | CloudTrail management events |
| `Recon:EC2/PortProbeUnprotectedPort` | VPC Flow Logs |
| `Exfiltration:S3/AnomalousBehavior` | S3 data events (S3 Protection) |

**Resposta dada:** as 4 relações acima
**Gabarito:** 4/4 — ✅ correto

Inclui a que o próprio lab corrigiu (ADR-020, atualização): `Policy:S3/BucketAnonymousAccessGranted` vem de **CloudTrail management events** (evento `PutBucketPolicy`), **não** da feature `S3_DATA_EVENTS`.

**Palavra-chave:** `Policy:S3/*` e `Stealth:S3/*` = findings de config/API → CloudTrail. `Discovery` / `Exfiltration` / `Impact:S3/AnomalousBehavior` = plano de dados → exigem S3 Protection. O prefixo do finding entrega a fonte.

---

### Pergunta 5 (múltipla escolha)

Um finding esperado **não** chega por e-mail **e não** aparece na lista default do console — mas `list-findings` com `service.archived = true` o retorna. Causa mais provável?

A) O detector está suspenso
B) A regra do EventBridge tem filtro de severidade que exclui esse finding
C) Há uma suppression rule (filtro com ação `ARCHIVE`) casando o tipo do finding
D) A consulta está sendo feita na região errada

**Resposta dada:** C, D
**Gabarito:** C — ⚠️ era resposta única; C certo, D marcado errado

- **A)** ❌ Detector suspenso → nenhum finding é gerado; não haveria o que `list-findings` retornar.
- **B)** ❌ Filtro de severidade na regra → o finding continuaria na lista default do console (não arquivado), só sem e-mail. O enunciado diz que sumiu da lista default → não é B. (É o cenário do TS-008.)
- **D)** ❌ Se a região estivesse errada, `list-findings` com `service.archived=true` **naquela região** não retornaria nada — mas retorna. O próprio enunciado descarta D.

**Palavra-chave:** "`service.archived = true` o retorna" — o estado **arquivado** é o discriminador único; só uma suppression rule arquiva um finding automaticamente. É o TS-007.

---

### Pergunta 6 (múltipla escolha)

Sobre exportar findings do GuardDuty para S3:

A) O export aceita SSE-S3; CMK só é preciso para multi-region
B) O export exige uma KMS CMK (SSE-S3 não é aceita); para agregar findings sem export, o Security Hub ingere direto via integração de serviço
C) O export para S3 é a única forma de mandar findings ao Security Hub
D) Findings do GuardDuty não podem ir para S3, só para o EventBridge

**Resposta dada:** B, C
**Gabarito:** B — ⚠️ era resposta única; B certo, C marcado errado

- **A)** ❌ SSE-S3 é explicitamente não aceito para o export de findings; a CMK é obrigatória independente de região.
- **C)** ❌ Findings vão para o Security Hub pela **integração nativa GuardDuty↔Security Hub** (liga-se a integração, eles fluem). O export para S3 é para retenção longa / Athena / data lake próprio — não é rota para o Security Hub.
- **D)** ❌ Findings **podem** ser exportados para S3 (com a CMK).

**Palavra-chave:** "agregar findings de várias fontes **sem esse export**" → agregação é exatamente o trabalho do Security Hub, via integrações diretas (é o tema do Lab 04).

---

### Pergunta 7 (complementar — exercício de reforço)

Você recebeu o e-mail do `Backdoor:EC2/C&CActivity.B!DNS` às **09:55**. Na mesma sessão, roda `getent hosts guarddutyc2activityb.com` de novo às **10:05**, com `finding_publishing_frequency = FIFTEEN_MINUTES`. Quando esperar um novo e-mail, e por quê?

**Resposta dada:** "por volta das 10:10" — ancorando em "primeiro e-mail 09:55 + 15 min".
**Gabarito:** a estimativa cai na janela plausível, mas o **raciocínio está errado**.

- Os 15 min contam a partir da **reocorrência (10:05)**, não do primeiro e-mail.
- É um **flush recorrente**, não um timer por finding. A atividade das 10:05 atualiza o **mesmo finding** (`Count` sobe, `UpdatedAt`/`EventLastSeen` avançam) e essa atualização entra no **próximo ciclo de export**. Na prática: novo e-mail **em até ~15 min da reocorrência** → janela ~**10:05–10:20**. Se um ciclo cair logo após as 10:05, chega quase na hora.
- **Sem atividade nova = sem e-mail.** O ciclo de 15 min **não** é um heartbeat.
- O e-mail das 09:55 foi o caminho de **finding novo** (~5 min após o `EventFirstSeen` 09:47) — não existe "relógio de 09:55" para somar 15.

**Modelo mental:**

```
Finding NOVO        -> EventBridge ~5 min após o evento        (o parâmetro não mexe)
REOCORRÊNCIA        -> entra no próximo flush; e-mail em ATÉ ~15 min DA reocorrência
Sem reocorrência    -> nenhum e-mail, independente do tempo
Console             -> sempre quase tempo real
```

**Palavra-chave:** distinguir "quando o evento aconteceu" de "quando a notificação foi exportada" — e lembrar que a cadência só existe para o que **repete**.
