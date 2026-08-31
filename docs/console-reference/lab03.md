# Console Reference — Lab 03 (GuardDuty)

**Lab:** 03
**Relacionado:** `terraform/environments/lab03/`, [ADR-015 a ADR-021](../decisions.md), [cli-reference/lab03.md](../cli-reference/lab03.md), [labs/01-detection/03-guardduty/README.md](../../labs/01-detection/03-guardduty/README.md), [attack-scenarios/](../../attack-scenarios/)

> ⚠️ **Status: referência não executada.** Este documento **não** foi clicado tela a tela nem validado campo a campo (diferente dos `setup-*.md`). É a tradução manual, feita em 2026-08-31, do que o Terraform do Lab 03 gerencia + o kit de investigação de findings — versão "console web" do [cli-reference/lab03.md](../cli-reference/lab03.md), material de estudo para o SCS-C03 (saber **onde no console** mora cada recurso e cada ação de análise), **não é fonte da verdade**. Pode divergir dos `.tf` a qualquer momento. Confira contra `terraform/environments/lab03/*.tf` antes de usar.

## Objetivo

Duas metades, iguais às do CLI ref:

1. **Recriar pelo console** o que o Terraform do Lab 03 cria: detector do GuardDuty + 2 protection plans ligados (e 4 fixados desligados), regra EventBridge com input transformer, tópico SNS com policy e assinatura, parâmetros SSM.
2. **Kit de investigação** — as telas do console que você usa de verdade durante o lab para caçar e dissecar um finding, e para executar os dois cenários de troubleshooting.

Nível "orientado a telas".

## Contexto — vale para todas as telas

| Item | Valor | Onde no console |
|---|---|---|
| Região | **N. Virginia — us-east-1** — **a mesma da EC2 do Lab 01** | seletor no canto superior direito. **GuardDuty é regional**: um finding só aparece na região onde a atividade ocorreu. |
| Account ID | `230650392331` | menu da conta |
| Tags | `Project=aws-security-specialty-lab`, `Lab=lab03`, `Environment=study`, `ManagedBy=terraform` | painel **Tags** (SNS, EventBridge, parâmetros SSM). O detector do GuardDuty também aceita tags em **Settings**. |
| Persistência | Lab 03 **não** tem ciclo destroy/recreate (ADR-016). Aplicado uma vez, fica de pé. A EC2 do Lab 01 é que sobe/desce por sessão. | — |
| Dependência cross-lab | **nenhuma** — GuardDuty tem pipeline de dados próprio, não lê `/lab01` nem `/lab02` do SSM. Só o ataque proposital precisa da EC2 do Lab 01 no ar. | — |

> `ManagedBy=terraform` é só espelho do `default_tags`. Fazendo pelo console de verdade → `ManagedBy=manual`.

---

## 1. Detector + protection plans

**Console:** GuardDuty → **Enable GuardDuty** (primeira vez) — ou **Settings** se já ativo.

Ao habilitar, o GuardDuty entra com **trial de 30 dias** e — importante — liga **quase todos os protection plans por default** (descoberto na validação, ADR-017). Você precisa ir **desligar** os que não quer.

### 1a. Frequência de publicação de findings

**GuardDuty → Settings → "Updated findings"** (frequência de findings atualizados) → **15 minutes**.

- Default = 6 horas. Isso afeta só as **reocorrências** de um finding já existente — a **1ª ocorrência** sempre vai ao EventBridge em ~5 min. E **nunca** afeta o console (que atualiza em quase tempo real).
- Corresponde a `finding_publishing_frequency = "FIFTEEN_MINUTES"` no `guardduty.tf`.

### 1b. Protection plans

**GuardDuty → Protection plans** (menu à esquerda). Em cada página:

| Plano | Ação | Equivalente `.tf` |
|---|---|---|
| **S3 Protection** | **Enable** | `aws_guardduty_detector_feature S3_DATA_EVENTS = ENABLED` |
| **Malware Protection → Malware Protection for EC2** | **Enable** (agentless: snapshot + scan em conta gerenciada pela AWS; US$0 ocioso) | `EBS_MALWARE_PROTECTION = ENABLED` |
| **EKS Protection** | **Disable** | `EKS_AUDIT_LOGS = DISABLED` |
| **RDS Protection** | **Disable** | `RDS_LOGIN_EVENTS = DISABLED` |
| **Lambda Protection** | **Disable** | `LAMBDA_NETWORK_LOGS = DISABLED` |
| **Runtime Monitoring** | **Disable** (→ Lab 13) | `RUNTIME_MONITORING = DISABLED` |

### Verificar

- **GuardDuty → Settings** → *Detector ID* visível, *Status: Enabled*.
- **Protection plans** → S3 + Malware EC2 = *Enabled*; EKS/RDS/Lambda/Runtime = *Disabled*.
- Fontes base sempre on (não aparecem como plano): CloudTrail management events, VPC Flow Logs, DNS query logs.

> **Gotcha de exame:** detector novo **não nasce "só com a base"** — a AWS liga quase tudo por default. Ao habilitar qualquer serviço de detecção, **verifique o que ele ligou** (princípio de menor funcionalidade).

---

## 2. Tópico SNS + policy + assinatura

**Console:** SNS → **Topics** → **Create topic**

- **Type:** *Standard* · **Name:** `awssec-lab03-sns-guardduty-findings` · **Tags** padrão → **Create topic**

**Access policy** — abra o tópico → **Edit** → seção **Access policy** → adicione o statement que deixa o EventBridge publicar:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEventBridgePublish",
      "Effect": "Allow",
      "Principal": { "Service": "events.amazonaws.com" },
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:us-east-1:230650392331:awssec-lab03-sns-guardduty-findings"
    }
  ]
}
```

> **Isso É necessário** — ao contrário do alarme CloudWatch → SNS do Lab 02, que não precisa de policy. **EventBridge → SNS exige** a resource policy no tópico. Para um alvo Lambda, o console adiciona a permissão sozinho; para SNS, você mesmo põe a topic policy.

**Assinatura** — **Create subscription** → *Protocol* **Email** → *Endpoint* `sergei.martao@gmail.com` → confirme no link que a AWS envia.

> Como o Lab 03 é **persistente** (ADR-016) e nunca sofre destroy/recreate, a confirmação é feita **uma vez só** — não recai na classe de bug do TS-005 (assinatura perdida no ciclo) do Lab 02.

Corresponde a `aws_sns_topic` + `aws_sns_topic_policy` + `aws_sns_topic_subscription` (`count` condicional em `var.finding_notification_email`).

---

## 3. Regra EventBridge (findings ≥ MEDIUM) + input transformer

**Console:** EventBridge → **Rules** → **Create rule** (event bus `default`)

- **Name:** `awssec-lab03-eventbridge-guardduty-findings`
- **Description:** `GuardDuty findings com severidade >= 4 -> SNS -> e-mail`
- **Event bus:** *default* · **Rule type:** *Rule with an event pattern* → **Next**
- **Event source:** *AWS events* · **Creation method:** *Custom pattern (JSON editor)*:

```json
{
  "source": ["aws.guardduty"],
  "detail-type": ["GuardDuty Finding"],
  "detail": { "severity": [ { "numeric": [ ">=", 4 ] } ] }
}
```

- **Target 1:** *AWS service* → **SNS topic** → `awssec-lab03-sns-guardduty-findings`
- **Additional settings → Configure target input:** **Input transformer**
  - **Input path:**

```json
{
  "id": "$.detail.id",
  "account": "$.account",
  "region": "$.region",
  "type": "$.detail.type",
  "severity": "$.detail.severity",
  "title": "$.detail.title",
  "desc": "$.detail.description",
  "resource": "$.detail.resource.resourceType",
  "time": "$.time"
}
```

  - **Template:**

```
"GuardDuty finding (Lab 03)"
""
"Titulo    : <title>"
"Tipo      : <type>"
"Severidade: <severity>"
"Recurso   : <resource>"
"Conta     : <account>   Regiao: <region>"
"Quando    : <time>"
"Finding ID: <id>"
""
"Descricao : <desc>"
""
"Console: https://console.aws.amazon.com/guardduty/home?region=<region>#/findings"
```

- **Tags** padrão → **Create rule**

Corresponde a `aws_cloudwatch_event_rule` + `aws_cloudwatch_event_target` (bloco `input_transformer`).

> **Gotcha de exame:** `detail.severity` é um **número** (8.0), não a string "High". O filtro numérico (`{"numeric":[">=",4]}`) é a forma certa; casar por string não funcionaria. Faixas: 1,0–3,9 LOW · 4,0–6,9 MEDIUM · 7,0–8,9 HIGH · 9,0–10 CRITICAL.

---

## 4. Outputs → SSM Parameter Store

**Console:** Systems Manager → **Parameter Store** → **Create parameter** (3×). Cada um: **Tier** *Standard*, **Type** *String*.

| Name | Value |
|---|---|
| `/lab03/detector_id`           | GuardDuty → Settings → *Detector ID* |
| `/lab03/sns_topic_arn`         | SNS → Topics → copiar ARN |
| `/lab03/eventbridge_rule_name` | `awssec-lab03-eventbridge-guardduty-findings` |

Labs 04 (Security Hub), 09 (Automated Incident Response) e 10 (Forensics) leem por aqui (ADR-004).

---

## 5. Kit de investigação

### Teste de encanamento — sample findings

**GuardDuty → Settings → Sample findings → Generate sample findings.**

- Cria **um sample de cada tipo** de finding, prefixado `[SAMPLE]`. Carregam `service.additionalInfo.sample = true` mas com a **severidade real** do tipo — passam pela regra do EventBridge igual aos reais. Em poucos minutos, o e-mail formatado (input transformer) deve chegar para os ≥ 4.
- O console é **tudo ou nada** — só a CLI (`create-sample-findings --finding-types ...`) escolhe tipos específicos.
- **Validar o encanamento:** EventBridge → Rules → a regra → aba **Monitoring** → métrica `Invocations` / `TriggeredRules`; SNS → tópico → **Monitoring** → `NumberOfMessagesPublished`.

### Listar e dissecar findings reais

**GuardDuty → Findings.** Vista default = ativos (não arquivados), mais recentes primeiro.

Clique num finding → painel de detalhe. Campos-chave (espelham os paths do `get-findings` no CLI ref):

| No console | Path equivalente (JSON) |
|---|---|
| **Finding type** | `.Findings[].Type` — ex. `Backdoor:EC2/C&CActivity.B!DNS` |
| **Severity** | `.Findings[].Severity` — ex. `8` |
| **Action → DNS request → Domain** | `.Service.Action.DnsRequestAction.Domain` |
| **Resource affected → Instance ID** | `.Resource.InstanceDetails.InstanceId` |
| **Resource affected → IAM instance profile ARN** | `.Resource.InstanceDetails.IamInstanceProfile.Arn` |
| **Additional information → First/Last seen, Count** | `.Service.EventFirstSeen` / `.EventLastSeen` / `.Count` |
| **Actor → Remote IP / API** (ataque S3) | `Api: PutBucketPolicy`, `EffectivePermission: PUBLIC`, `RemoteIP` |
| **Sample** (sim/não) | `.Service.AdditionalInfo.sample` |

- **Barra de filtro** no topo da lista de Findings: adicione critérios (`severity ≥`, `resource.resourceType`, `service.archived`…). É o equivalente console do `list-findings --finding-criteria`.
- **Estatística:** GuardDuty → **Summary** (dashboard) → contagem por severidade / por tipo / recursos mais afetados — equivalente do `get-findings-statistics`.

### Correlação com o Lab 02 (investigação própria)

- **VPC Flow Logs** — o host chegou a **conectar** no IP resolvido, ou só resolveu DNS? Console: CloudWatch → **Logs Insights** → log group de `/lab02/vpc_flow_logs_log_group_name` → query:

```
fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter dstAddr = "<IP_RESOLVIDO>"
| sort @timestamp desc
```

  (Flow Logs **não** capturam query ao resolver da VPC — o GuardDuty as vê pelo pipeline próprio de DNS. Query DNS como log consultável = Lab 06 / Route 53 Resolver query logging.)

- **CloudTrail** — a IAM role da instância fez algo anômalo perto do horário do finding? Console: CloudTrail → **Event history** → filtro **Resource name** = `i-xxxx` (ou **User name** = a sessão da role). Event history é always-on, 90 dias, independe do trail do Lab 02 — **sobrevive** a um teardown do Lab 01/02.

> **Lição operacional:** evidência volátil (Flow Logs em log group efêmero) se coleta **antes** do teardown. O finding em si fica congelado (detector persistente + retenção de 90 dias) — investiga-se um finding sobre um recurso que já não existe.

---

## 6. Cenário de troubleshooting A — suppression rule

**Criar a suppression rule (console):** GuardDuty → **Findings** → na barra de filtro, adicione o critério **Finding type = `Backdoor:EC2/C&CActivity.B!DNS`** → botão **Save** ao lado do filtro → marque **Suppress findings matching this filter** → nome `awssec-lab03-suppress-c2dns`. (Também dá para gerenciar em **Settings → Suppression rules**.)

- Rode o Ataque 1 de novo (ou gere sample) → **nenhum e-mail**, e o finding **some da lista default**.
- Investigar: o finding **existe**, só está **arquivado**. Findings → filtro **`service.archived = true`** (ou aba *Archived*) → lá está o finding suprimido.
- GuardDuty → **Settings → Suppression rules** → mostra a regra → ação = *archive* dos findings que casam → **causa raiz**.
- **Correção:** apagar a suppression rule.

> **Por que nenhum e-mail:** findings arquivados por suppression rule **não** são enviados ao EventBridge (`Invocations = []`). O registro continua existindo para auditoria — **suppression ≠ delete**. É um filtro do **lado do GuardDuty** (Settings → Suppression rules), não do EventBridge.

---

## 7. Cenário de troubleshooting B — filtro de severidade

- Desligue **só o Block Public Access** de uma bucket de teste (sem policy anônima): S3 → bucket → **Permissions** → **Block public access** → **Edit** → desmarque as 4 → **Save changes**.
- → finding `Policy:S3/BucketBlockPublicAccessDisabled` aparece no console do GuardDuty, **Severity 2.0 (LOW)**.
- → **NENHUM e-mail:** o event pattern da regra exige `severity >= 4`. Comportamento esperado (ADR-018).
- Diagnosticar: GuardDuty → Findings → abrir o finding LOW → `Severity 2.0`. Comparar com o pattern da regra em EventBridge → Rules → a regra → **Event pattern**. O finding **existe e NÃO está arquivado** — some só da **notificação**.

> **Distinção-chave para o SCS-C03** — "o time não foi alertado" pode ser:
> - **(a)** detector/feature off → GuardDuty → Settings / Protection plans
> - **(b)** filtro de severidade no roteamento — **TS-008** (finding existe, não arquivado)
> - **(c)** suppression rule — **TS-007** (finding existe, arquivado, zero invocações no EventBridge)
>
> Cada um se diagnostica diferente.

---

## 8. Multi-account / delegated administrator (conceitual — implementação no Lab 19)

A conta já é management da org `o-23e9438ykt`. No console, o que seria feito no **Lab 19**:

- Da conta **management**: GuardDuty → **Settings → Accounts** → **Delegated administrator** → informar o ID da conta de segurança → **Delegate**.
- Da conta **delegated admin**: GuardDuty → **Accounts** → **Auto-enable** → ligar GuardDuty automaticamente para todas as contas da org (existentes + novas).

Modelo: uma conta vira **delegated administrator** do GuardDuty para a org; ela vê e gerencia os findings de todas as contas **member**; `auto-enable` liga o GuardDuty automaticamente em contas novas. Centraliza a detecção sem depender de export para S3.

---

## Desmontar (só ao encerrar os estudos — ADR-016)

Durante os estudos o Lab 03 **fica de pé**. Só no fim de tudo:

1. **EventBridge → Rules** → apagar `awssec-lab03-eventbridge-guardduty-findings`.
2. **SNS** → apagar assinatura + tópico `awssec-lab03-sns-guardduty-findings`.
3. **GuardDuty → Settings → Disable GuardDuty** (apaga o detector + todos os findings). *Suspend* mantém a config e só para a análise — para bater com `terraform destroy`, use **Disable**.
   - Desabilitar **apaga os findings e zera o baseline de ML** — é exatamente por isso que o ADR-015 mantém o detector persistente durante os estudos.
4. **Parameter Store** → apagar `/lab03/*`.
5. **Artefatos dos exercícios:** apagar bucket(s) de teste + bucket policy (Ataque 2); apagar a suppression rule se ainda existir (TS-007).

---

## Notas para a prova (SCS-C03)

- **GuardDuty é regional.** Um finding só aparece na região onde a atividade ocorreu. Ameaça multi-região → habilitar em todas as regiões (ou via org config / auto-enable).
- **Detector novo não nasce "só com a base".** O console liga quase todos os protection plans por default no primeiro *enable*. Vá em **Protection plans** e desligue o que ainda não estuda (menor funcionalidade).
- **Pipeline de dados próprio.** GuardDuty não precisa de trail do CloudTrail, nem dos VPC Flow Logs configurados, nem de DNS logging — lê essas fontes direto. Habilitar o detector basta. Os destinos de log do Lab 02 são para a **sua** investigação cruzada, não pré-requisito.
- **`Updated findings` frequency** (Settings) afeta **reocorrências/atualizações** de um finding, não a 1ª entrega (sempre ~5 min ao EventBridge), e **nunca** o console. Valores: 15 min, 1 h, 6 h (default).
- **Suppression rule / filtro com archive** arquiva o finding e **impede o envio ao EventBridge**, mas mantém o registro. Diferente de não ter finding nenhum. É filtro do lado do GuardDuty (Settings → Suppression rules), não do EventBridge.
- **Export de findings para S3 exige KMS CMK** (SSE-S3 não é aceito). Para agregar findings sem export: **Security Hub** (integração de serviço direta — Lab 04) ou Security Lake. Por isso o Lab 03 não faz export (ADR-019).
- **Severity é número no evento do EventBridge**, não string. Faixas: 1,0–3,9 LOW · 4,0–6,9 MEDIUM · 7,0–8,9 HIGH · 9,0–10 CRITICAL.
- **Sample findings** (Settings → Generate sample findings): prefixo `[SAMPLE]` + `sample = true`, mas severidade real do tipo — servem para testar automação/roteamento. O console gera um de **cada** tipo; só a CLI escolhe tipos.
- **EventBridge → SNS exige a resource policy do tópico** (`events.amazonaws.com` : `sns:Publish`). Alarme CloudWatch → SNS (Lab 02) não. Para alvo Lambda o console adiciona a permissão sozinho; para SNS você põe a topic policy.
- **Malware Protection for EC2** é acionado por findings suspeitos de EC2 (ou on-demand); tira snapshot do EBS e escaneia numa conta gerenciada pela AWS. Não é scan contínuo.
- **Lab 03 é persistente** — sem destroy/recreate por sessão (ADR-016), então a confirmação da assinatura SNS é feita uma vez só. A EC2 do Lab 01 é que sobe/desce por sessão.
