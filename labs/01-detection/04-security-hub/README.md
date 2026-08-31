# Lab 04 — Security Hub

**Status:** 🚧 Design fechado (10 forks socráticos → **ADR-022 a ADR-029** em [docs/decisions.md](../../../docs/decisions.md), + atualização da ADR-018). Terraform escrito (`terraform/environments/lab04/`, 11 arquivos `.tf`), `terraform validate` OK — `apply` + validação campo a campo pendentes; pré-requisito de bootstrap ([setup-log-bucket-bootstrap.md](../../../docs/setup/setup-log-bucket-bootstrap.md) §8) ainda não aplicado. Base: **AWS Security Hub CSPM clássico** (não o Hub unificado novo de dez/2025 — ver "O split de produto"). Persistente, fora do `manage-foundation.sh`.

## SCS-C03

- Domínio/Fase: **Domínio 1 — Detecção (16%)** (toca o Domínio 6 — Governança, 14%)
- Habilidades:
  - **1.1.3** — agregar eventos de segurança e monitoramento
  - **1.1.4** — métricas/alertas/painéis para dados e eventos anômalos (GuardDuty, Security Hub, Macie, Security Lake)
  - **1.1.5** — automações de avaliação/investigação regulares (Security Hub, conformance packs do Config, SSM State Manager)
  - **1.3.1 / 1.3.2** — analisar funcionalidade/permissão/config de recursos; corrigir configuração incorreta
  - **6.3.1** — regras para detectar e corrigir recursos fora de conformidade (Config + Security Hub)
- ⚠️ O guia do SCS-C03 **removeu "ASFF"** da Tarefa 1.1 (era conteúdo do SCS-C02). Ainda é o mecanismo de normalização, mas não é foco de estudo para a prova.

## Objetivo

Transformar findings dispersos (GuardDuty do Lab 03, Inspector, checks de postura) num **painel único, normalizado e priorizável**, e passar do "detectar → investigar" (Lab 03) para "**detectar → priorizar → rotear → remediar → medir**". Deixar montada a camada de **gestão de postura contínua** (CSPM) — *security score*, detecção de drift, ciclo `FAILED → PASSED` — e o ponto único de roteamento sobre o qual o Lab 09 pendura a resposta automatizada.

## Cenário

O Lab 03 colocou um detector que emite findings acionáveis. Mas: (1) GuardDuty é **uma** fonte — Inspector (vulnerabilidades) e a postura de configuração (bucket que ficou público, SG que abriu `0.0.0.0/0`) não têm quem observe; (2) não há **priorização** entre findings de fontes diferentes, com formatos diferentes; (3) não há **medição** de postura ao longo do tempo. O Lab 04 fecha isso com o Security Hub como **camada** — agregador + CSPM + motor de triagem.

### Conceito-chave: Security Hub CSPM precisa do AWS Config

Diferente do GuardDuty (pipeline de dados próprio — ver Lab 03), os *security standards* do Security Hub CSPM são **quase inertes sem um AWS Config recorder rodando**. A maioria dos controls FSBP é lastreada por Config managed rules que o Security Hub provisiona sozinho, mas que só avaliam se o Config estiver gravando aquele tipo de recurso. Por isso o Lab 04 sobe um Config **mínimo** (recorder + delivery channel), com o Config-serviço completo (rules próprias, conformance packs, remediação, aggregators) ficando para o **Lab 20**.

### O split de produto (dez/2025)

Em 2 dez 2025 (re:Invent) a AWS deu GA num **novo "AWS Security Hub" unificado** — schema **OCSF**, APIs **v2**, *exposure findings* correlacionando GuardDuty + Inspector + CSPM. O serviço original virou **"AWS Security Hub CSPM"** (schema **ASFF**, APIs **v1**), plenamente suportado, sem timeline de deprecação. **Este lab usa o CSPM clássico**: é o que o provider Terraform cobre de forma estável (`aws_securityhub_*` = v1; o suporte v2 é issue aberta) e o que mapeia no guia do exame atual. O Hub novo é tratado conceitualmente aqui + um toggle CLI manual opcional no `cli-reference`; a implementação real (central configuration multi-conta) fica para o **Lab 19**.

## Requisitos de segurança

- **Toda fonte de finding relevante conflui para um painel** — GuardDuty, Inspector, checks de postura, num formato normalizado (ASFF).
- **Postura medida continuamente** — *security score* + control status; um bucket que fica público ou um SG que abre `0.0.0.0/0` viram finding sem ninguém olhar.
- **Todo finding MEDIUM+ notifica um humano** — mesmo princípio dos Labs 02/03, agora **agregado** (uma fonte de e-mail, não uma por serviço).
- **Caminho de automação preservado** — a resposta latência-crítica (Lab 09) dispara direto da fonte, não espera a ingestão do Security Hub.
- **Persistência** — *security score* e histórico de findings só fazem sentido com continuidade; destruir/recriar zeraria a tendência.
- **Custo contido** — sem Free Tier (ADR-007): só FSBP, Config com escopo restrito, stack persistente com custo ocioso ≈ 0.

## Arquitetura

```text
  Espécimes (lab04)      Fundação (lab01, quando no ar)     Detector (lab03)
   S3 · SG · VPC              EC2 · VPC · S3 · IAM            GuardDuty
        │                          │                             │
        ▼                          ▼                             ▼
  ┌──────────────┐        ┌─────────────────┐          (integração de serviço)
  │  AWS Config  │────────│ configuration   │                   │
  │  recorder    │        │ items (escopo   │                   │
  │  (contínuo,  │        │ ~12 tipos)      │                   │
  │   escopado)  │        └────────┬────────┘                   │
  └──────┬───────┘                 │                            │
         │ snapshots/history       ▼                            │
   awssec-logs-<acct>     ┌───────────────────────┐             │
   (bucket persistente)   │ Config managed rules  │             │
                          │ (provisionadas pelo   │             │
                          │  Security Hub)        │             │
                          └───────────┬───────────┘             │
                                      ▼                         ▼
                     ┌──────────────────────────────────────────────┐
                     │       AWS Security Hub CSPM (us-east-1)       │
                     │  standard: FSBP  ·  score  ·  ASFF findings   │
                     │  finding aggregator (ALL_REGIONS, home ue-1)  │
                     │  + Amazon Inspector (EC2 scan) ── CVEs ───────┤
                     └──────┬──────────────────────────┬────────────┘
                            │ Findings - Imported      │ Findings - Custom Action
                            │ (Severity.Label MEDIUM+  │ ("Escalar" — triagem manual)
                            │  Workflow.Status = NEW    │
                            │  RecordState = ACTIVE)    │
                            ▼                          ▼
                     ┌────────────────────────────────────┐
                     │  EventBridge → SNS → e-mail         │
                     │  awssec-lab04-sns-securityhub-…     │
                     └────────────────────────────────────┘

  Cano direto (lab03, reproposto):  GuardDuty → EventBridge → [Lab 09: Lambda de contenção]
                                    (var.direct_guardduty_notification_enabled = false)

  SSM /lab04/{securityhub_hub_arn, config_recorder_name, finding_aggregator_arn,
              securityhub_sns_topic_arn, securityhub_eventbridge_rule_name, custom_action_arn}
```

## Serviços AWS envolvidos

- **AWS Security Hub CSPM** — `aws_securityhub_account` (consolidated control findings), standard FSBP, `finding_aggregator`, *automation rule* (no exercício de troubleshooting), *custom action*
- **AWS Config** — recorder + delivery channel, escopo restrito de ~12 tipos, entrega no log bucket persistente
- **Amazon Inspector** — scan de EC2 (`aws_inspector2_enabler`), findings de vulnerabilidade fluindo automático para o Security Hub
- **Amazon EventBridge** — regra `Security Hub Findings - Imported` (filtrada) + regra do *custom action*
- **Amazon SNS** — tópico + assinatura por e-mail (notificação agregada)
- **Amazon GuardDuty** — fonte de findings via integração de serviço; alvo do sub-exercício de tamper (`GuardDuty.1`)
- **AWS Systems Manager** — Parameter Store (`/lab04/...`); a EC2 da fundação como *managed instance* para o Inspector
- **Amazon S3** — bucket-espécime (alvo do ataque) + log bucket (destino do Config)
- **AWS IAM** — service-linked roles do Security Hub/Config/Inspector; policy do log bucket para `config.amazonaws.com`

## Implementação

### Terraform — `terraform/environments/lab04/`

| Arquivo | Conteúdo |
|---|---|
| `versions.tf` | `>= 1.10`, `aws ~> 6.0`, backend S3 (key `lab04/terraform.tfstate`, `use_lockfile`) |
| `provider.tf` | região/profile via var, `default_tags` (`Lab = lab04`) |
| `variables.tf` | `aws_region`, `aws_profile`, `finding_notification_email` (tfvars gitignored), `finding_severity_label` |
| `data.tf` | só `aws_caller_identity` + `aws_region` — **nenhum** `aws_ssm_parameter` do `/lab03` (integração é via serviço). Log bucket = `awssec-logs-${account_id}` |
| `config.tf` | `aws_config_configuration_recorder` (`recording_group` restrito) + `aws_config_delivery_channel` (→ log bucket) + `aws_config_configuration_recorder_status` |
| `securityhub.tf` | `aws_securityhub_account` (`control_finding_generator = "SECURITY_CONTROL"`, `auto_enable_controls = true`) + `aws_securityhub_standards_subscription` (FSBP) + `aws_securityhub_finding_aggregator` (`ALL_REGIONS`) + `aws_securityhub_standards_control_association` (disable-list curada como passo do lab) |
| `inspector.tf` | `aws_inspector2_enabler` (`resource_types = ["EC2"]`) |
| `routing.tf` | `aws_cloudwatch_event_rule` (`Security Hub Findings - Imported`, filtrada) + target SNS + input transformer; `aws_sns_topic` + policy + subscription e-mail; `aws_securityhub_action_target` ("Escalar") + sua regra EventBridge |
| `specimens.tf` | `aws_vpc` `10.4.0.0/28` (pelado) + `aws_security_group` + `aws_s3_bucket` (BPA on por padrão) |
| `ssm.tf` | `/lab04/{securityhub_hub_arn, config_recorder_name, finding_aggregator_arn, securityhub_sns_topic_arn, securityhub_eventbridge_rule_name, custom_action_arn}` |
| `outputs.tf` | idem + IDs dos espécimes + ARN do standard FSBP |

**Persistência (ADR-023):** aplicado **uma vez** e mantido de pé. Não entra no `scripts/manage-foundation.sh`. `terraform destroy` só ao encerrar os estudos.

**Pré-requisito de bootstrap (ADR-024):** antes do primeiro `terraform apply`, adicionar ao [docs/setup/setup-log-bucket-bootstrap.md](../../../docs/setup/setup-log-bucket-bootstrap.md) (e aplicar) o statement de bucket policy do log bucket para `config.amazonaws.com` (`s3:PutObject` com `bucket-owner-full-control`, `s3:GetBucketAcl`, `s3:GetBucketPolicy`). Sem isso o `aws_config_delivery_channel` falha no apply.

```bash
cd terraform/environments/lab04
# finding_notification_email em terraform.tfvars (gitignored), padrão dos Labs 02/03
terraform init
terraform fmt -check && terraform validate
terraform plan
terraform apply
# depois: confirmar o link de assinatura do SNS (1x)
# depois: re-aplicar o Lab 03 com  direct_guardduty_notification_enabled = false
#         (ADR-018 atualizada / ADR-027)
```

### AWS CLI

Equivalente CLI de cada recurso + kit de investigação (`get-findings` com filtros ASFF, `batch-update-findings`, `describe-standards-controls`, `list-enabled-products-for-import`, `get-enabled-standards`, `configservice describe-configuration-recorder-status`, `start-config-rules-evaluation`) em [docs/cli-reference/lab04.md](../../../docs/cli-reference/lab04.md) — referência de estudo **não executada** (mesmo selo do `lab03.md`).

## Testes

Plano de validação campo a campo, a executar na implementação:

1. `terraform apply` sem erro; segundo `apply` idempotente.
2. `securityhub get-enabled-standards` → só FSBP; `describe-hub` → `ControlFindingGenerator: SECURITY_CONTROL`.
3. `configservice describe-configuration-recorder-status` → `recording: true`, `lastStatus: SUCCESS`; `describe-delivery-channels` → log bucket.
4. Em algumas horas: `securityhub get-findings` retorna controls avaliados (não todos `NO_DATA`); *security score* visível no console.
5. `inspector2 batch-get-account-status` → `EC2: ENABLED`; com a fundação no ar, finding de CVE aparece no Security Hub (`ProductName = "Inspector"`).
6. `securityhub describe-action-targets` → custom action "Escalar"; `events describe-rule` → regra `Security Hub Findings - Imported` `ENABLED` com o pattern filtrado.
7. `sns list-subscriptions-by-topic` → e-mail confirmado (não `PendingConfirmation`).
8. `ssm get-parameters-by-path --path /lab04 --recursive` → 6 parâmetros.
9. Lab 03 re-aplicado com o toggle → `events describe-rule` da regra do Lab 03 sem alvo de e-mail / desabilitada.

## Falha ou ataque proposital

Deriva de postura em 2 passos, nos espécimes (ADR-028). IP de origem = estação do operador.

### Passo 1 — Security group permissivo

```bash
aws ec2 authorize-security-group-ingress --group-id <sg-especime> \
  --protocol tcp --port 22 --cidr 0.0.0.0/0
```

→ control **`EC2.13`** (FSBP) vira `FAILED`; finding ASFF `Severity.Label = HIGH`, `Compliance.Status = FAILED`, `Workflow.Status = NEW`.

### Passo 2 — Bucket anônimo

```bash
BUCKET=<bucket-especime>
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{"Version":"2012-10-17","Statement":[{"Sid":"PublicRead","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::'"$BUCKET"'/*"}]}'
```

→ controls **`S3.1` / `S3.8`** `FAILED` **+** finding do **GuardDuty** `Policy:S3/BucketAnonymousAccessGranted` (pipeline de CloudTrail management events — a mecânica aprendida no Lab 03), tudo agregado no Security Hub.

### Sub-exercício — tamper no detector (`GuardDuty.1`)

```bash
aws guardduty update-detector --detector-id <id> --no-enable   # cega o sensor
# ... observar GuardDuty.1 = FAILED no Security Hub ...
aws guardduty update-detector --detector-id <id> --enable      # re-habilitar NA HORA
```

Lição: o atacante desliga a detecção, mas a **postura** (Security Hub/Config) registra a evasão. Risco ao baseline de ML (ADR-015) aceito como baixo — janela de segundos, baseline de anomalia não cultivado.

## Detecção e investigação

Com N findings de **3 produtos** (GuardDuty, Inspector, Security Hub/Config) no mesmo painel:

- **Priorizar** — `securityhub get-findings` com filtros ASFF (`SeverityLabel`, `ProductName`, `ResourceId`, `ComplianceStatus`, `WorkflowStatus`, `RecordState`); ordenar por severidade normalizada.
- **Correlacionar** — o mesmo `ResourceId` (o bucket) aparecendo num finding do GuardDuty **e** num control `S3.1` — duas lentes sobre a mesma misconfig.
- **Medir** — a queda do *security score* após os passos 1–2; a recuperação após a remediação.
- **Rotear** — o e-mail agregado (ADR-027) chega só para os MEDIUM+ com `Workflow.Status = NEW`; a *custom action* "Escalar" dispara triagem manual do console.
- **Triagem** — `batch-update-findings` movendo `Workflow.Status` `NEW → NOTIFIED → RESOLVED`; diferença entre *control PASSED* (compliance) e *finding fechado* (workflow).

## Troubleshooting

Detalhe completo (sintoma → hipóteses → evidências → causa → correção → validação) em [docs/troubleshooting.md](../../../docs/troubleshooting.md) na execução. Continua a numeração do Lab 03 (TS-007/008).

| ID | Cenário | Sintoma | Causa | Como se distingue |
|---|---|---|---|---|
| **TS-009** | Escopo do Config recorder | Standard habilitado, controls em `NO_DATA`, sem findings de compliance | O recorder não grava aquele tipo de recurso (escopo restrito, ADR-024) | `describe-configuration-recorder-status` (`recording`/`lastStatus`); `recordingGroup` sem o tipo; control com `ComplianceStatus: NO_DATA` |
| **TS-010** | Automation rule | Finding crítico sem e-mail, ou finding esperado "sumiu" da fila | `Criteria` larga demais (suprime crítico) / estreita demais (não dispara) / `RuleOrder` + `IsTerminal` interrompendo | Finding **existe** com `Workflow.Status = SUPPRESSED` + `NoteUpdatedBy`; `RecordState` não arquivado; comparar com o filtro `Workflow.Status = NEW` da regra (ADR-027) |

**Distinção-chave para o SCS-C03:** "o time não foi alertado" pode ser **(a)** control em `NO_DATA` — recorder (TS-009); **(b)** finding suprimido por automation rule (TS-010); **(c)** filtro de severidade/workflow no roteamento (herdado do TS-008 do Lab 03); **(d)** integração de produto não habilitada / região errada. Cada um se diagnostica diferente.

### Notas de rodapé (não executadas)

- **"Corrigi mas continua `FAILED`"** — latência de reavaliação do Config (forçar com `start-config-rules-evaluation`) vs. recurso ainda não-conforme num detalhe (removeu `:22`, deixou `:3389`) vs. confusão control-`PASSED` × finding-`Workflow.Status`.
- **Finding do GuardDuty ausente no Security Hub** — `list-enabled-products-for-import`; região (Security Hub em us-east-1).

## Remediação

- **Passo 1:** `aws ec2 revoke-security-group-ingress --group-id <sg> --protocol tcp --port 22 --cidr 0.0.0.0/0` → `EC2.13` volta a `PASSED` na próxima avaliação.
- **Passo 2:** `aws s3api delete-bucket-policy --bucket <bucket>` + `aws s3api put-public-access-block ... true,true,true,true` → `S3.1`/`S3.8` `PASSED`.
- **Tamper:** `update-detector --enable` (feito na hora).
- **TS-010:** `aws securityhub batch-delete-automation-rules` / ajustar `Criteria`.
- Validar: *security score* recupera; `get-findings` mostra `Compliance.Status = PASSED` e `Workflow.Status = RESOLVED` / `RecordState = ARCHIVED`.

## Evidências

A coletar na execução — pasta [evidence/lab04/](../../../evidence/):

- Console do *security score* antes/depois dos passos 1–2 e após remediação.
- `get-findings` JSON mostrando o mesmo `ResourceId` num finding do GuardDuty e num control `S3.1` (agregação/correlação).
- E-mail agregado (input transformer) de um finding MEDIUM+.
- `describe-configuration-recorder-status` + control em `NO_DATA` (TS-009).
- Automation rule + finding com `Workflow.Status = SUPPRESSED` (TS-010).
- `GuardDuty.1 = FAILED` no console durante o tamper.

## Custos e cleanup

**Restrição do projeto:** teto de **US$ 100 / 6 meses** (absoluto) — ver `docs/decisions.md` (ADR-007). Sem Free Tier desde 2026-08-25.

| Item | Custo estimado |
|---|---|
| Security Hub — *security checks* (só FSBP, poucos recursos) | tiered (US$0,0010 os primeiros 100k/mês); volume de estudo → **centavos/mês** |
| Security Hub — ingestão de findings | 10.000 eventos/conta/região/mês grátis; GuardDuty/Inspector ingeridos sem custo → **US$0** no volume de estudo |
| AWS Config — configuration items | escopo ~12 tipos + espécimes estáticos → **poucos centavos/sessão**; idle (fundação parada) ≈ **US$0** |
| AWS Config — avaliações de rule | primeiros 100k/mês a US$0,001 → **centavos** |
| Amazon Inspector — scan EC2 | ~US$0,002/instância/hora, pró-rata → **~US$0,006 por sessão de 3 h**; **US$0** sem EC2 |
| Finding aggregator, EventBridge, SNS e-mail | **US$0** |
| **Total** | **~US$ 0,50–1,50 por sessão de estudo ativa; ≈ US$0 ocioso** — projetado em **US$ 15–40** no projeto |

**Escape hatch:** o AWS Budget alerta em US$ 5 / US$ 10; mitigação de uma linha é `aws configservice stop-configuration-recorder` entre sessões, ou `terraform destroy` do lab04.

**Cleanup:**

```text
# Durante os estudos: NAO destruir (ADR-023) — o Lab 04 fica de pe, como o Lab 03.

# So ao encerrar os estudos:
terraform -chdir=terraform/environments/lab04 destroy
   └── Security Hub (account + standard + aggregator), Config (recorder + channel),
       Inspector enabler, regras EventBridge, topico SNS + assinatura, especimes, /lab04/*

# Manual, se criados no exercicio:
aws securityhub batch-delete-automation-rules --automation-rules-arns <arn>   # TS-010
# reverter o toggle no Lab 03 se quiser a notificacao direta de volta:
#   direct_guardduty_notification_enabled = true  + terraform apply (lab03)
```

O log bucket (bootstrap, ADR-009) persiste — o `destroy` do lab04 remove só o recorder/channel que ele criou, não o bucket.

## Relação com SCS-C03

```text
SCS-C03
├── Dominio 1 — Deteccao (16%)
│   ├── Tarefa 1.1 — monitoramento e alertas
│   │   ├── 1.1.3 agregar eventos de seguranca → Security Hub (GuardDuty + Inspector + Config)
│   │   ├── 1.1.4 detectar dados/eventos anomalos → security score, insights, roteamento
│   │   └── 1.1.5 automacoes de avaliacao regular → standards, automation rules
│   └── Tarefa 1.3 — troubleshooting de logging/alerta/monitoramento
│       ├── 1.3.1 funcionalidade/permissao/config de recurso → TS-009 (Config recorder)
│       └── 1.3.2 corrigir configuracao incorreta → ciclo FAILED → PASSED
└── Dominio 6 — Governanca (14%)
    └── Tarefa 6.3 — avaliar conformidade
        └── 6.3.1 detectar e corrigir recurso fora de conformidade (Config + Security Hub)

Conteudo adjacente coberto conceitualmente:
- Security Hub unificado novo (OCSF, v2) vs. CSPM classico (ASFF, v1) — split de dez/2025
- Delegated administrator / central configuration / cross-Region aggregation → Lab 19
- AWS Config aprofundado (rules, conformance packs, remediacao, aggregators) → Lab 20
```

## Revisão para a certificação

A criar ao fim do lab: quiz em `docs/quiz/lab04-exam-review.md` (mesmo header + uma seção `## Lab 04`), com esta seção linkando para lá, conforme a convenção iniciada no Lab 02.
