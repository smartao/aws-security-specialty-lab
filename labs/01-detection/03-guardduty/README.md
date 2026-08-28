# Lab 03 — GuardDuty

**Status:** 🟡 Desenho fechado (9 decisões → ADR-015 a ADR-021) e Terraform escrito em `terraform/environments/lab03/` (`fmt` + `validate` limpos). **Pendente:** `terraform apply`, execução dos dois ataques propositais, dos dois cenários de troubleshooting, e coleta de evidências.

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

_(pendente de `terraform apply`)_ — roteiro:

1. `terraform plan` limpo; `apply` sem erro.
2. `aws guardduty list-detectors` → 1 detector; `get-detector <id>` → `Status = ENABLED`, `FindingPublishingFrequency = FIFTEEN_MINUTES`.
3. `aws guardduty list-detector-features` (ou `get-detector`) → `S3_DATA_EVENTS` e `EBS_MALWARE_PROTECTION` `ENABLED`.
4. `aws sns list-subscriptions-by-topic` → assinatura de e-mail (após confirmar o link, `SubscriptionArn` com ARN real).
5. `aws events describe-rule --name awssec-lab03-eventbridge-guardduty-findings` → `State = ENABLED`, pattern com `severity >= 4`.
6. **Teste de encanamento:** `aws guardduty create-sample-findings --detector-id <id> --finding-types 'Backdoor:EC2/C&CActivity.B!DNS'` → e-mail legível (via input transformer) chega em poucos minutos. **Aspas simples obrigatórias** — sem elas o `&` faz o zsh/bash colocar o comando em background e o `!` dispara history expansion, e nada é criado.
7. `aws ssm get-parameters-by-path --path /lab03 --recursive` → 3 parâmetros.

## Falha ou ataque proposital

Dois ataques (ADR-020), cada um exercitando um pipeline diferente:

### Ataque 1 — DNS Command & Control (pipeline de DNS query logs)

Da EC2 do Lab 01, via Session Manager (sem SSH, sem chave):

```bash
aws ssm start-session --target <instance-id>
# dentro da sessão:
dig guarddutyc2activityb.com          # domínio de teste oficial do GuardDuty
```

**Esperado:** finding `Backdoor:EC2/C&CActivity.B!DNS`, severidade **HIGH (8.0)**, em ~5–15 min → regra EventBridge → e-mail SNS.

### Ataque 2 — Bucket policy anônima (pipeline de S3 data events)

```bash
# criar uma bucket de teste e anexar policy com Principal "*"
aws s3api put-bucket-policy --bucket <bucket-teste> --policy '{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicRead", "Effect": "Allow", "Principal": "*",
    "Action": "s3:GetObject", "Resource": "arn:aws:s3:::<bucket-teste>/*"
  }]
}'
```

**Esperado:** finding `Policy:S3/BucketAnonymousAccessGranted`, severidade **HIGH** → e-mail.

⚠️ **Nota:** só desligar o Block Public Access (sem policy anônima) dispara `Policy:S3/BucketBlockPublicAccessDisabled`, que é **LOW (2.0)** — abaixo do limiar `severity >= 4`, **não** gera e-mail. Esse é o cenário de troubleshooting B.

## Detecção e investigação

Roteiro para cada finding (a preencher com saídas reais nas evidências):

1. **Ler o finding:** `aws guardduty get-findings --detector-id <id> --finding-ids <fid>` → dissecar:
   - `Type`, `Severity`, `Title`
   - `Service.Action.DnsRequestAction.Domain` (ataque 1) ou `Service.Action.*` conforme o tipo
   - `Resource.InstanceDetails` — instance ID, IAM role anexada, IPs privado/público
   - `Service.EventFirstSeen` / `EventLastSeen` / `Count`
2. **Correlacionar com o Lab 02 (investigação própria):**
   - **VPC Flow Logs** (CloudWatch Logs Insights) — o host só resolveu o DNS ou chegou a abrir conexão para o IP resolvido? Filtrar pelo IP / pela ENI da instância.
   - **CloudTrail** — o que a IAM role da instância fez em volta do horário do finding? Algum uso de credencial fora do padrão?
3. **Lacunas conscientes** (viram labs futuros):
   - Qual **processo** na instância fez o lookup — GuardDuty não diz sem Runtime Monitoring → **Lab 13**.
   - DNS query logs consultáveis de forma dedicada → **Lab 06** (Route 53 Resolver query logging).
   - Grafo de relação entre entidades do finding → **Lab 10** (Detective).
4. **Concluir:** o quê / quando / qual recurso / origem / impacto (nenhum — domínio de teste / bucket de estudo) / contenção (isolar SG e/ou remover a policy — automação no **Lab 09**).

## Troubleshooting

Item explícito da lista do `agents.md` ("GuardDuty sem finding esperado"). Processo: sintoma → hipóteses → evidências → causa → correção → validação. A documentar em `docs/troubleshooting.md` (próximos IDs: TS-007, TS-008).

### Cenário A (principal) — suppression rule arquivando o finding

1. Criar um filtro/suppression rule (via console ou `aws guardduty create-filter ... --action ARCHIVE`) casando `type = Backdoor:EC2/C&CActivity.B!DNS`.
2. Rodar o Ataque 1 de novo.
3. **Sintoma:** nenhum e-mail; o finding não aparece na lista default do console.
4. **Investigar:** `aws guardduty list-findings --detector-id <id> --finding-criteria '{"Criterion":{"service.archived":{"Eq":["true"]}}}'` → o finding **existe**, mas arquivado. `aws guardduty list-filters` + `get-filter` → a suppression rule com `Action = ARCHIVE`.
5. **Causa:** suppression rule auto-arquiva o finding; findings arquivados **não** vão para o EventBridge.
6. **Correção:** `aws guardduty delete-filter` (ou ajustar o critério). Validar re-disparando o ataque.

A suppression rule **não** está no Terraform — é passo manual do exercício.

### Cenário B (secundário) — filtro de severidade engolindo um finding LOW

1. Só desligar o Block Public Access de uma bucket (sem policy anônima).
2. **Sintoma:** nenhum e-mail, apesar de haver um finding novo no console.
3. **Investigar:** o finding é `Policy:S3/BucketBlockPublicAccessDisabled`, `Severity = 2.0` (LOW). O `event_pattern` da regra EventBridge exige `severity >= 4`.
4. **Causa:** design deliberado (ADR-018) — LOW não notifica. Não é bug.
5. **Correção:** nenhuma (comportamento esperado) — ou baixar `finding_severity_threshold` se o objetivo mudar.

### Notas de rodapé (C e D)

- **C — região errada:** `list-findings` em `us-west-2` enquanto o detector e o finding estão em `us-east-1`. GuardDuty é regional.
- **D — latência de reocorrência:** com `finding_publishing_frequency` alta (default AWS 6 h), a **reocorrência** de um finding demora a chegar ao EventBridge. Por isso o Lab usa `FIFTEEN_MINUTES`.

## Remediação

_(pendente — a documentar junto com TS-007/TS-008)_

- **Ataque 1:** remover qualquer persistência na instância; no cenário real, isolar via SG (Lab 09). No lab, encerrar a sessão SSM basta (nada foi instalado).
- **Ataque 2:** `aws s3api delete-bucket-policy --bucket <bucket-teste>` (ou remover a statement anônima) e deletar a bucket de teste.
- **Troubleshooting A:** `delete-filter` da suppression rule.

## Evidências

Pasta [evidence/lab03/](../../../evidence/lab03/) — a coletar:

- Saída de `get-detector` e `list-detector-features` pós-apply.
- E-mail do sample finding (encanamento).
- `get-findings` JSON do `Backdoor:EC2/C&CActivity.B!DNS` real + screenshot do console.
- `get-findings` JSON do `Policy:S3/BucketAnonymousAccessGranted` + screenshot.
- TS-007 (suppression rule): `list-findings` com `service.archived = true` + `get-filter`.
- TS-008 (filtro de severidade): finding LOW no console sem e-mail correspondente.

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

## Perguntas de revisão para a certificação

1. **(Múltipla escolha)** Uma equipe habilita o GuardDuty numa conta que **não** tem nenhum trail do CloudTrail configurado. O GuardDuty gera findings baseados em `Recon:IAMUser/*` mesmo assim. Por quê?
2. **(Múltipla resposta)** Quais afirmações sobre `finding_publishing_frequency` do GuardDuty são verdadeiras? (a) afeta a 1ª entrega de um finding novo ao EventBridge; (b) afeta a entrega de atualizações/reocorrências; (c) valores possíveis: 15 min, 1 h, 6 h; (d) afeta a latência do console.
3. **(Ordenação)** Coloque em ordem: investigar um finding `Backdoor:EC2/C&CActivity.B!DNS` — (i) correlacionar IP resolvido nos VPC Flow Logs; (ii) `get-findings` para extrair o domínio e a instância; (iii) verificar no CloudTrail o uso da IAM role da instância; (iv) decidir contenção.
4. **(Correspondência)** Ligue o finding à fonte de dados: `Backdoor:EC2/C&CActivity.B!DNS` ↔ ? · `Policy:S3/BucketAnonymousAccessGranted` ↔ ? · `Recon:IAMUser/MaliciousIPCaller` ↔ ? (opções: DNS query logs, S3 data events, CloudTrail management events)
5. **(Múltipla escolha)** Um finding esperado não chega por e-mail nem aparece na lista default do console, mas `list-findings` com `service.archived = true` o retorna. Qual a causa mais provável?
6. **(Múltipla escolha)** Por que exportar findings do GuardDuty para S3 exige uma KMS CMK, e qual a alternativa para agregar findings de várias fontes sem esse export?
