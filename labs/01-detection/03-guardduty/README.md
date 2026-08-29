# Lab 03 — GuardDuty

**Status:** ✅ Implementado e validado campo a campo em 2026-08-28. Detector persistente `ENABLED` (`FINDING_PUBLISHING_FREQUENCY = FIFTEEN_MINUTES`), features exatamente as decididas (`S3_DATA_EVENTS` + `EBS_MALWARE_PROTECTION` on; `EKS_AUDIT_LOGS`/`RDS_LOGIN_EVENTS`/`LAMBDA_NETWORK_LOGS`/`RUNTIME_MONITORING` fixadas off — a AWS ligava por default, ver ADR-017). Encanamento EventBridge → SNS → e-mail validado ponta a ponta (`Invocations`/`NumberOfMessagesPublished`). **Dois ataques propositais executados e investigados** (Ataque 1 — DNS C&C, `Backdoor:EC2/C&CActivity.B!DNS` HIGH; Ataque 2 — bucket anônima, `Policy:S3/BucketAnonymousAccessGranted` HIGH). **Dois cenários de troubleshooting executados** (TS-007 suppression rule, TS-008 filtro de severidade). Evidências em [`evidence/lab03/`](../../../evidence/lab03/). Design: 9 decisões → ADR-015 a ADR-021.

## SCS-C03

- Domínio/Fase: **Domínio 1 — Detecção (16%)**
- Habilidades tocadas:
  - **1.1.x** — configurar serviços de detecção de ameaças (GuardDuty) e suas fontes
  - **1.2.1 / 1.2.2** — analisar e priorizar findings de segurança; investigar a partir de um alerta
  - **1.3.x** — automatizar o roteamento de findings (EventBridge) — a *notificação* aqui, a *resposta* no Lab 09
  - **2.x** (prévia) — o finding é o ponto de entrada do ciclo de resposta a incidentes

## Objetivo

Ativar detecção de ameaças baseada em ML + threat intelligence sobre a conta e a VPC do Lab 01, entender a **anatomia de um finding** (tipo, severidade, recurso, ação, contexto), e praticar o ciclo `detectar → investigar` com um evento **real e controlado** — não só *sample findings*. Deixar montada a camada de **notificação** de findings (EventBridge → SNS → e-mail), sobre a qual o Lab 09 vai pendurar a resposta automatizada.

## Cenário

A fundação (Lab 01) e o logging (Lab 02) estão de pé, mas **nada interpreta** essa atividade em busca de comportamento malicioso. Um `DescribeInstances` em massa, um lookup de DNS para um domínio de C2, ou uma bucket policy liberando acesso anônimo passariam despercebidos — o CloudTrail registra, mas ninguém está olhando. O Lab 03 fecha essa lacuna de **análise**, colocando um detector que correlaciona três fontes e emite findings acionáveis.

### Conceito-chave: o GuardDuty tem pipeline de dados próprio

O GuardDuty **não consome** os destinos de log configurados no Lab 02 (S3 / CloudWatch Logs). Ele tem um pipeline **independente e direto** para:

- **CloudTrail management events** (não precisa de um trail configurado)
- **VPC Flow Logs** (não precisa dos flow logs do Lab 02)
- **DNS query logs** (via o resolver da VPC — não existe em lugar nenhum como log consultável sem o Route 53 Resolver query logging, que é do Lab 06)

Basta **habilitar o detector**. O Lab 02 continua valendo para a **sua** investigação cruzada de um finding (correlacionar com CloudTrail e Flow Logs), que é o que este lab exercita e o Lab 10 aprofunda — mas não é pré-requisito para o GuardDuty funcionar.

## Requisitos de segurança

- **Detector habilitado na região da EC2 do Lab 01** — GuardDuty é regional; um finding só aparece na região onde a atividade ocorreu.
- **S3 Protection** — visibilidade sobre ameaças em S3 data events (acesso anônimo, exfiltração anômala), pipeline próprio, independente do data event selector do CloudTrail do Lab 02.
- **Malware Protection for EC2** — capacidade de snapshot + scan agentless de EBS pronta para os Labs 08/10, sem custo enquanto ociosa.
- **Todo finding MEDIUM+ notifica um humano** — mesmo princípio do alarme de root usage do Lab 02: um evento suspeito precisa gerar um alerta que sai do console.
- **Detector persistente** — o baseline de ML de findings de anomalia leva 7–14 dias para amadurecer; destruir/recriar o detector a cada sessão o zeraria.
- **Latência de reocorrência baixa** (`FIFTEEN_MINUTES`) — para um re-teste na mesma sessão de estudo produzir notificação nova.

## Arquitetura

```text
        EC2 (Lab 01)                Conta AWS                    Buckets S3
             │                          │                             │
     DNS query / atividade      CloudTrail mgmt events         S3 data events
             │                          │                             │
             └──────────┬───────────────┴──────────────┬──────────────┘
                        ▼                               ▼
              ┌───────────────────────────────────────────────┐
              │   Amazon GuardDuty  (detector, us-east-1)      │
              │   + S3 Protection   + Malware Protection EC2   │
              │   finding_publishing_frequency = 15 min        │
              └───────────────────────┬───────────────────────┘
                                      │ finding (severity ≥ 4)
                                      ▼
                        ┌─────────────────────────────┐
                        │  EventBridge rule           │
                        │  source = aws.guardduty     │
                        │  detail.severity >= 4        │
                        │  + input transformer        │
                        └──────────────┬──────────────┘
                                       ▼
                        SNS topic ──▶ assinatura e-mail
                    (awssec-lab03-sns-guardduty-findings)
                                       │
                                       ▼
                     SSM /lab03/{detector_id, sns_topic_arn,
                                  eventbridge_rule_name}
                                       │
                                       ▼
                     Lab 09 pendura aqui a resposta automatizada
                     (Lambda: isola SG, snapshot, tag)
```

## Serviços AWS envolvidos

- **Amazon GuardDuty** — detector, features `S3_DATA_EVENTS` e `EBS_MALWARE_PROTECTION`, suppression filter (no exercício de troubleshooting)
- **Amazon EventBridge** — regra de captura de findings + input transformer
- **Amazon SNS** — tópico + assinatura por e-mail (notificação)
- **AWS Systems Manager** — Parameter Store (outputs `/lab03/...`) e Session Manager (executar o ataque na EC2 sem SSH)
- **Amazon S3** — alvo do segundo ataque proposital (bucket policy anônima)
- **AWS IAM** — policy do tópico SNS permitindo `events.amazonaws.com` publicar

## Implementação

### Terraform — `terraform/environments/lab03/`

| Arquivo | Conteúdo |
|---|---|
| `versions.tf` | `required_version >= 1.10`, provider `aws ~> 6.0`, backend S3 (key `lab03/terraform.tfstate`, `use_lockfile`) |
| `provider.tf` | região/profile via var, `default_tags` (`Lab = lab03`) |
| `variables.tf` | `aws_region`, `aws_profile`, `finding_notification_email`, `finding_severity_threshold` (default 4) |
| `data.tf` | só `aws_caller_identity` + `aws_region` — **nenhum** `aws_ssm_parameter` (sem dependência cross-lab, de propósito) |
| `guardduty.tf` | `aws_guardduty_detector` (`finding_publishing_frequency = "FIFTEEN_MINUTES"`) + `aws_guardduty_detector_feature`: pin `ENABLED` em `S3_DATA_EVENTS` e `EBS_MALWARE_PROTECTION`, pin `DISABLED` em `EKS_AUDIT_LOGS`, `RDS_LOGIN_EVENTS`, `LAMBDA_NETWORK_LOGS`, `RUNTIME_MONITORING` (a AWS liga esses por default num detector novo — ver ADR-017) |
| `findings.tf` | `aws_sns_topic` + `aws_sns_topic_policy` (EventBridge → `sns:Publish`) + `aws_sns_topic_subscription` (e-mail, `count` condicional) + `aws_cloudwatch_event_rule` (pattern `severity >= var`) + `aws_cloudwatch_event_target` (input transformer) |
| `ssm.tf` | `/lab03/detector_id`, `/lab03/sns_topic_arn`, `/lab03/eventbridge_rule_name` |
| `outputs.tf` | detector ID, SNS ARN, nome da regra, status dos 2 protection plans |

**Persistência (ADR-015 / ADR-016):** o Lab 03 é aplicado **uma vez** e mantido de pé. Não entra no `scripts/manage-foundation.sh` (que faz up/down por sessão). `terraform destroy` só ao encerrar os estudos.

```bash
cd terraform/environments/lab03
# e-mail persistido em terraform.tfvars (gitignored), mesmo padrão do Lab 02:
#   finding_notification_email = "voce@exemplo.com"
terraform init
terraform fmt -check && terraform validate
terraform plan
terraform apply
# depois do apply: confirmar o link de assinatura que a AWS manda por e-mail (1x só)
```

### AWS CLI

O equivalente CLI de cada recurso + o kit de investigação (`get-detector`, `list-findings`, `get-findings`, `create-sample-findings`, `list-organization-admin-accounts`) está em [docs/cli-reference/lab03.md](../../../docs/cli-reference/lab03.md) — referência de estudo **não executada** (mesmo selo do `lab02.md`).

## Testes

Validado campo a campo em 2026-08-28 (o primeiro `apply` foi corrigido — ver ADR-017, atualização):

1. `terraform apply` — recursos criados sem erro; segundo `apply` adicionou os 4 pins `DISABLED` de feature (0 change, 0 destroy).
2. `get-detector` → `Status: ENABLED`, `FindingPublishingFrequency: FIFTEEN_MINUTES`.
3. `get-detector` → features `ENABLED` são **exatamente** `CLOUD_TRAIL`, `DNS_LOGS`, `FLOW_LOGS`, `S3_DATA_EVENTS`, `EBS_MALWARE_PROTECTION` (EKS/RDS/Lambda/Runtime revertidos a `DISABLED`).
4. `sns list-subscriptions-by-topic` → `sergei.martao@gmail.com` com `SubscriptionArn` real (`...:5ea53fe6-...`), não `PendingConfirmation`.
5. `events describe-rule` → `State: ENABLED`, pattern `"severity":[{"numeric":[">=",4]}]`; `list-targets-by-rule` → alvo = ARN do tópico SNS.
6. **Encanamento:** `create-sample-findings --finding-types 'Backdoor:EC2/C&CActivity.B!DNS'` (aspas simples obrigatórias — sem elas o `&` joga o comando pra background e o `!` dispara history expansion no zsh, e nada é criado) → em poucos minutos: `EventBridge Invocations = 1`, `SNS NumberOfMessagesPublished = 1`, `FailedInvocations = []`, e-mail formatado pelo input transformer recebido.
7. `ssm get-parameters-by-path --path /lab03 --recursive` → 3 parâmetros (`detector_id`, `sns_topic_arn`, `eventbridge_rule_name`).

## Falha ou ataque proposital

Dois ataques (ADR-020), executados 2026-08-28. IPs de origem = `168.232.226.99` (estação do operador).

> **Roteiro genérico e reutilizável** de cada um em [`attack-scenarios/`](../../../attack-scenarios/): [`compromised-ec2`](../../../attack-scenarios/compromised-ec2/README.md) (Ataque 1, fase C2/DNS) e [`public-s3`](../../../attack-scenarios/public-s3/README.md) (Ataque 2). Abaixo, o registro do que foi executado **neste** lab.

### Ataque 1 — DNS Command & Control (pipeline de DNS query logs)

Da EC2 do Lab 01 (`i-0a784c2586f40a2e5`), via Session Manager:

```bash
aws ssm start-session --target i-0a784c2586f40a2e5
# dentro da sessão:
for i in 1 2 3; do getent hosts guarddutyc2activityb.com; done   # dig/nslookup não instalados na AMI
```

**Resultado:** finding `Backdoor:EC2/C&CActivity.B!DNS` (ID `b8d023e3b299723f3ddd0b9fb26e3805`), **HIGH (8.0)**, `Count: 4` (queries agregadas entre `09:47:30` e `09:47:52 UTC`), `ResourceRole: TARGET`, `Blocked: false`, threat list `Amazon`. E-mail entregue ~09:55 UTC. `Could not resolve host` (NXDOMAIN) **não** impede o finding — o gatilho é a *query* enviada ao resolver da VPC, não uma resolução com sucesso.

### Ataque 2 — Bucket policy anônima (pipeline de CloudTrail management events)

```bash
BUCKET="awssec-lab03-attack2-${ACCOUNT_ID}"
aws s3api create-bucket --bucket "$BUCKET" --region us-east-1
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{"Version":"2012-10-17","Statement":[{"Sid":"PublicRead","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::'"$BUCKET"'/*"}]}'
```

Gera **dois** findings:

| Ação | Finding | Sev. | E-mail | ID |
|---|---|---|---|---|
| `put-public-access-block` | `Policy:S3/BucketBlockPublicAccessDisabled` | 2.0 LOW | ❌ (< 4) → **é o TS-008** | `d2d024f4ca88ca1ac4d4609fdb526383` |
| `put-bucket-policy` | `Policy:S3/BucketAnonymousAccessGranted` | HIGH | ✅ | `44d024f4cb82589dd7939eb2f400e961` |

O finding HIGH mostra `Api: PutBucketPolicy`, `EffectivePermission: PUBLIC`, `RemoteIP: 168.232.226.99`, `ResourceRole: TARGET`, `Count: 1` — o GuardDuty essencialmente faz *replay* do management event do CloudTrail + avalia o acesso público resultante. Por isso funciona **sem** a feature `S3_DATA_EVENTS` (essa adiciona findings de *data events* object-level, que dependem de baseline — não exercitados neste lab).

## Detecção e investigação

### Ataque 1 — timeline reconstruída (UTC)

| Hora | Evento | Fonte | Ator |
|---|---|---|---|
| 09:43:44 | `RunInstances` — a EC2 nasce | CloudTrail (`lookup-events`) | `sergei` (apply Lab 01) |
| 09:47:14 | `StartSession` em `i-0a784c...` | CloudTrail | `assumed-role/AWSReservedSSO_AdministratorAccess.../sergei` de `168.232.226.99` |
| 09:47:30 → 09:47:52 | 4× query DNS `guarddutyc2activityb.com` | GuardDuty (`EventFirstSeen`/`LastSeen`/`Count`) | processo na sessão SSM |
| ~09:55 | finding gerado + e-mail | GuardDuty | — |
| 10:01:00 | `TerminateInstances` — teardown | CloudTrail | `sergei` |

**Elo-chave:** `StartSession` → primeira query DNS em **16 segundos**. É assim que se amarra atividade suspeita a uma identidade (principal SSO `sergei`, IP `168.232.226.99`).

### Conclusão (6 perguntas)

- **O quê:** a EC2 fez 4 consultas DNS a um domínio de C&C conhecido (threat list "Amazon").
- **Quando:** 2026-08-28 09:47:30–09:47:52 UTC. `EventFirstSeen` é a hora do fato, não a da entrega.
- **Qual recurso:** `i-0a784c2586f40a2e5`, subnet `subnet-06330a363e382093c` (privada, sem IP público), SG `awssec-lab01-sg-ec2-app`, profile `awssec-lab01-profile-ec2-app`.
- **Origem:** sessão SSM interativa aberta pelo principal SSO `sergei` de `168.232.226.99`; a query saiu de um processo dentro dela.
- **Impacto:** **nenhum** — NXDOMAIN → sem IP → canal de C&C impossível. A role da instância não fez nenhuma chamada de API de controle (`lookup-events` por `Username` da role → vazio). `ResourceRole: TARGET` = o ator no modelo do GuardDuty é o servidor de C&C remoto; a instância é o alvo dessa relação.
- **Conter/recuperar:** real → isolar SG + snapshot EBS + análise de processo (automação no Lab 09); no lab → `exit` da sessão (nada foi instalado) + instância já terminada.

### Lacunas conscientes / lição do teardown

O ambiente do Lab 01/02 foi destruído no meio da investigação (fim de sessão de estudo, ADR-007). Consequências:

- **VPC Flow Logs — perdidos.** O log group era efêmero (Lab 02). A pergunta "houve conexão de saída após a query?" ficou sem resposta direta (respondida por inferência — NXDOMAIN torna a conexão impossível). Além disso, Flow Logs **não** capturam queries ao resolver da VPC de qualquer forma → GuardDuty as vê pelo pipeline próprio de DNS (Route 53 Resolver), não pelos Flow Logs. Query DNS como log consultável = **Lab 06**.
- **CloudTrail — recuperável.** `lookup-events` (Event history) é always-on, retém 90 dias de management events, independe do trail destruído. Os logs no S3 (`awssec-logs-230650392331`) são persistentes (ADR-009) e cobrem data events também.
- **Finding — intacto.** Detector persistente (ADR-015) + retenção de 90 dias. Todo o contexto (instance ID, IPs, profile, subnet, SGs, timestamps, domínio, contagem) está congelado no JSON — investiga-se um finding sobre um recurso que já não existe.
- **Lição operacional:** evidência volátil se coleta **antes** do teardown. Num incidente real não se destrói o ambiente antes da forense — disciplina do Lab 10.

- Qual **processo** fez o lookup — GuardDuty não diz sem Runtime Monitoring → **Lab 13**.
- Grafo de entidades do finding → **Lab 10** (Detective).

## Troubleshooting

Item explícito da lista do `agents.md` ("GuardDuty sem finding esperado"). Dois cenários executados 2026-08-28; detalhe completo (sintoma → hipóteses → evidências → causa → correção → validação) em [`docs/troubleshooting.md`](../../../docs/troubleshooting.md).

| ID | Cenário | Sintoma | Causa | Como se distingue |
|---|---|---|---|---|
| **TS-007** | Suppression rule (`aws_guardduty_filter`, `--action ARCHIVE`) casando `Backdoor:EC2/C&CActivity.B!DNS` | Sample gerado, **sem e-mail**, ausente da lista default | Finding **auto-arquivado na geração** → não vai ao EventBridge (`Invocations = []`) | Finding **existe** só com `service.archived=true`; `list-filters` mostra o filtro `ARCHIVE` |
| **TS-008** | Filtro de severidade da regra EventBridge (`severity >= 4`, ADR-018) | Finding LOW no console, **sem e-mail**; o HIGH irmão notificou | Design deliberado: `Policy:S3/BucketBlockPublicAccessDisabled` = 2.0 < 4 → não casa o pattern | Finding **existe e NÃO está arquivado** — some só da notificação; comparar `Severity` com o `event_pattern` |

Distinção-chave para o SCS-C03: "o time não foi alertado" pode ser **(a)** detector/feature off (`get-detector`), **(b)** filtro de severidade no roteamento — TS-008 (finding existe, não arquivado), ou **(c)** suppression rule — TS-007 (finding existe, arquivado, zero invocações). Cada um se diagnostica diferente. A suppression rule **não** está no Terraform — é passo manual do exercício, removida ao final.

### Notas de rodapé (não executadas)

- **Região errada:** `list-findings` em `us-west-2` com o detector/finding em `us-east-1` — GuardDuty é regional.
- **Latência de reocorrência:** `finding_publishing_frequency` alta (default AWS 6 h) atrasa a **reocorrência** ao EventBridge. Por isso o lab usa `FIFTEEN_MINUTES`.

## Remediação

- **Ataque 1:** nada instalado na instância → `exit` da sessão SSM; instância já terminada no teardown. Real: isolar SG + snapshot + rotacionar credenciais da role (automação no Lab 09).
- **Ataque 2:** `aws s3api delete-bucket-policy --bucket <bucket>` + `aws s3 rb s3://<bucket> --force`.
- **TS-007:** `aws guardduty delete-filter --detector-id <id> --filter-name awssec-lab03-suppress-c2dns` → `list-filters` → `FilterNames: []`. Confirmado.
- **TS-008:** nenhuma correção — comportamento esperado (ADR-018).

## Evidências

Pasta [evidence/lab03/](../../../evidence/lab03/):

- `ts-007-guardduty-cc-dns-finding.json` — `get-findings` do `Backdoor:EC2/C&CActivity.B!DNS` real (ID `b8d023e3...`).
- `ts-008-guardduty-s3-anonymous-access-finding.json` — `get-findings` do `Policy:S3/BucketAnonymousAccessGranted` (ID `44d024f4...`).
- `ts-008-guardduty-sns-s3-anonymous-access-email.png` / `ts-008-guardduty-console-s3-severity-contrast.png` — e-mail (input transformer) + console do finding S3 HIGH.
- Timeline do `lookup-events` (Ataque 1) + saídas de validação do encanamento (`Invocations`, `NumberOfMessagesPublished`).
- TS-007: `list-findings` com `service.archived=true` retornando o sample suprimido + `get-filter` (`Action: ARCHIVE`) + `Invocations = []`.
- TS-008: finding LOW `Policy:S3/BucketBlockPublicAccessDisabled` (sev 2.0) no console, sem e-mail correspondente.

## Custos e cleanup

**Restrição do projeto:** teto de **US$ 100 / 6 meses** (absoluto) — ver [[project-budget-constraint]] / `docs/decisions.md`.

**Custo estimado:**

| Item | Custo |
|---|---|
| Detector + análise base (mgmt events, Flow Logs, DNS) | Grátis nos 30 dias de trial; depois **centavos/mês** no volume de estudo |
| S3 Protection | ~US$0,80 / milhão de S3 data events → **centavos** |
| Malware Protection for EC2 | **US$0** enquanto ocioso; ~US$0,40 por scan de um volume de 8 GB quando disparar |
| EventBridge rule + SNS e-mail | **US$0** |
| **Total** | **< US$1/mês**, tipicamente centavos |

**Cleanup:**

```text
# Durante os estudos: NÃO destruir (ADR-016) — o Lab 03 fica de pé.
# A EC2 do Lab 01 é que sobe/desce por sessão (manage-foundation.sh).

# Só ao encerrar os estudos:
terraform -chdir=terraform/environments/lab03 destroy
   └── destrói: detector (+ features), regra EventBridge, tópico SNS,
                assinatura, policy do tópico, parâmetros SSM /lab03/*

# Limpeza dos artefatos dos exercícios (manual, se criados):
aws s3api delete-bucket-policy --bucket <bucket-teste>   # ataque 2
aws s3 rb s3://<bucket-teste> --force                     # ataque 2
aws guardduty delete-filter --detector-id <id> --filter-name <nome>  # TS-007
```

## Relação com SCS-C03

```text
SCS-C03
└── Domínio 1 — Detecção (16%)
    ├── Tarefa 1.1 — implementar e configurar serviços de detecção
    │   ├── GuardDuty: detector, fontes (CloudTrail/Flow Logs/DNS), protection plans
    │   └── pipeline independente vs. destinos de log (CloudTrail/Flow Logs do Lab 02)
    ├── Tarefa 1.2 — analisar e priorizar findings
    │   ├── anatomia do finding, severidade (LOW/MEDIUM/HIGH/CRITICAL)
    │   ├── sample findings vs. findings reais
    │   └── suppression rules / filtros (arquivar ruído sem perder o registro)
    └── Tarefa 1.3 — automatizar resposta a findings
        ├── EventBridge (source aws.guardduty, detail-type "GuardDuty Finding")
        ├── finding publishing frequency (1ª ocorrência ~5 min vs. reocorrência)
        └── delegated administrator / multi-account (conceitual → Lab 19)
```

## Revisão para a certificação

Quiz de revisão (6 perguntas + 1 complementar, formatos variados: múltipla escolha, múltipla resposta, ordenação, correspondência) em [docs/quiz/lab03-exam-review.md](../../../docs/quiz/lab03-exam-review.md) — placar **4,25/6**: nenhum erro na alternativa central de nenhuma questão, mas 3 com *over-selection* (alternativa errada marcada junto da certa). Gap conceitual anotado: `finding_publishing_frequency` — afeta **reocorrências**, não a 1ª entrega, e **nunca** o console.
