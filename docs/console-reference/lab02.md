# Console Reference — Lab 02 (Centralized Logging Foundation)

**Lab:** 02
**Relacionado:** `terraform/environments/lab02/`, [ADR-009 a ADR-014](../decisions.md), [cli-reference/lab02.md](../cli-reference/lab02.md), [setup/setup-log-bucket-bootstrap.md](../setup/setup-log-bucket-bootstrap.md), [labs/00-foundation/02-centralized-logging-foundation/README.md](../../labs/00-foundation/02-centralized-logging-foundation/README.md)

> ⚠️ **Status: referência não executada.** Este documento **não** foi clicado tela a tela nem validado campo a campo (diferente dos `setup-*.md`, que carregam esse selo). É a tradução manual, feita em 2026-08-31, do que o Terraform do Lab 02 já gerencia — versão "console web" do [cli-reference/lab02.md](../cli-reference/lab02.md), útil como material de estudo para o exame SCS-C03 (saber **onde no console** mora cada recurso e o que o exame cobra de cada tela), mas **não é fonte da verdade**. Pode divergir do Terraform real a qualquer momento que `terraform/environments/lab02/*.tf` mudar, sem nenhum aviso automático. Se for reproduzir de verdade, confira contra os `.tf` atuais antes de clicar.

## Objetivo

Mostrar, tela a tela, como recriar pelo **AWS Management Console** os recursos que o Terraform do Lab 02 cria hoje: CloudTrail multi-region com dual delivery (S3 + CloudWatch Logs), metric filter + alarme de uso de root, VPC Flow Logs (`ALL`, dual delivery) e o bucket de resultados do Athena. Nível "orientado a telas".

**O bucket de logs persistente (`awssec-logs-230650392331`) NÃO está aqui** — ele é criado via AWS CLI de verdade em [setup/setup-log-bucket-bootstrap.md](../setup/setup-log-bucket-bootstrap.md), fora do ciclo de vida deste lab (ADR-009). O wizard de *Create trail* do console **quer criar um bucket novo pra você** — não deixe; aponte para o bucket existente (passo 3).

## Contexto — vale para todas as telas

| Item | Valor | Onde no console |
|---|---|---|
| Região | **N. Virginia — us-east-1** | seletor no canto superior direito. **Confira antes de cada recurso.** |
| Account ID | `230650392331` | menu da conta |
| Tags em todo recurso | `Project=aws-security-specialty-lab`, `Lab=lab02`, `Environment=study`, `ManagedBy=terraform` | painel **Tags** de cada tela |
| Dependência do Lab 01 | VPC ID lido de `/lab01/vpc_id` (SSM) | Systems Manager → Parameter Store, ou VPC → Your VPCs. O Lab 01 precisa estar aplicado nesta sessão. |

> `ManagedBy=terraform` é só para espelhar o `default_tags` do provider. Fazendo isso de verdade pelo console (fora do Terraform), o padrão do projeto é `ManagedBy=manual`. O console não tem "default tags" — repita as 5 tags em cada tela, ou use **Tag Editor** depois.

---

## 1. CloudWatch Log Group — CloudTrail

**Console:** CloudWatch → **Log groups** → **Create log group**

- **Log group name:** `/aws/cloudtrail/awssec-lab02-trail`
- **Retention setting:** `180 days` (o default é **Never expire** — troque)
- **Tags:** as 5 padrão → **Create**

> O wizard de *Create trail* (passo 3) se oferece para criar esse log group sozinho, com nome automático (`aws-cloudtrail-logs-<acct>-<hash>`) e retenção **Never expire**. Criar antes, com o nome exato e 180 dias, bate com `aws_cloudwatch_log_group.cloudtrail` no `cloudtrail.tf`.

---

## 2. IAM role que o CloudTrail assume para escrever no log group

**Console:** IAM → **Roles** → **Create role**

Não existe tile de use case "CloudTrail", então:

- **Trusted entity type:** *Custom trust policy* → cole:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Principal": { "Service": "cloudtrail.amazonaws.com" }, "Action": "sts:AssumeRole" }
  ]
}
```

- **Skip** permissions por ora → **Role name:** `awssec-lab02-role-cloudtrail-cloudwatch` → **Create role**
- Abra a role → **Add permissions → Create inline policy** → aba **JSON**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "WriteToLogGroup",
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
      "Resource": "arn:aws:logs:us-east-1:230650392331:log-group:/aws/cloudtrail/awssec-lab02-trail:*"
    }
  ]
}
```

- **Policy name:** `awssec-lab02-policy-cloudtrail-cloudwatch-write` → **Create policy**

> Se você deixar o wizard de *Create trail* criar essa role, ela sai com o nome `CloudTrailRoleForCloudWatchLogs_awssec-lab02-trail`. Criar na mão dá o nome do `.tf`.
> **Gotcha de propagação:** se o passo 3 falhar logo em seguida por a role "não existir ainda", espere alguns segundos e refaça.

---

## 3. O Trail em si (multi-region, dual delivery)

**Console:** CloudTrail → **Trails** → **Create trail**

**Página 1 — General details:**

- **Trail name:** `awssec-lab02-trail` — **tem que bater exatamente.** A bucket policy do log bucket (definida no bootstrap) escopa `s3:PutObject` por `aws:SourceArn` contendo o ARN deste trail. Nome errado → `LatestDeliveryError: AccessDenied` na entrega (é o TS-006).
- **Storage location:** *Use existing S3 bucket* → `awssec-logs-230650392331`. **Não** marque *Create new S3 bucket*.
- **Log file SSE-KMS encryption:** **Disabled.** O console default é *Enabled* + criar uma KMS key nova; o log bucket é SSE-S3 (ADR-013) e o `create-trail` da CLI também não usa KMS.
- **Log file validation:** *Enabled* (`enable_log_file_validation = true`)
- **SNS notification delivery:** *Disabled* (o `.tf` não configura SNS no trail em si)
- **CloudWatch Logs:** *Enabled* → *Existing log group* → `/aws/cloudtrail/awssec-lab02-trail` → *Existing role* → `awssec-lab02-role-cloudtrail-cloudwatch`
- **Tags:** as 5 padrão → **Next**

**Multi-region:** o wizard novo de *Create trail* **cria multi-region por padrão** e **não expõe toggle** de single-region — só a API/CLI (`--no-is-multi-region-trail`) cria um single-region. `include_global_service_events` também vem ligado. Corresponde a `is_multi_region_trail = true` + `include_global_service_events = true`.

---

## 4. Advanced event selectors — management + data events do S3 (exceto o log bucket)

Ainda no wizard, **Página 2 — Choose log events:**

- **Management events:** marcado, *Read* **e** *Write*. (É o "advanced event selector" de `eventCategory = Management` — o 1º bloco `advanced_event_selector` do `.tf`.)
- **Data events:** marque → **Add data event type** → *Data event type:* **S3**.
  - **Log selector template:** *Custom*
  - Adicione a condição: campo **`resources.ARN`** → operador **`doesn't start with`** → valor `arn:aws:s3:::awssec-logs-230650392331/`
  - Isso equivale ao 2º bloco `advanced_event_selector` (`eventCategory=Data` + `resources.type=AWS::S3::Object` + `resources.ARN NotStartsWith` o log bucket).
- **Insights events:** desmarcado.
- **Create trail**

> **Por que excluir o log bucket:** sem o `NotStartsWith`, cada `PutObject` que o próprio CloudTrail faz ao entregar log no bucket viraria um data event novo — loop autorreferencial de ruído e custo.
> **Gotcha de exame:** um trail usa **ou** basic **ou** advanced event selectors, não os dois. Só o advanced consegue filtrar por `resources.ARN` / `NotStartsWith` — o basic não faz o "exceto o log bucket".

---

## 5. Ligar o logging

Diferente da CLI (`create-trail` **não** liga o trail; precisa de `start-logging`), **o console liga sozinho** ao fim do wizard. Na página do trail, o toggle **Logging** aparece **On**.

- Verificar: CloudTrail → Trails → `awssec-lab02-trail` → toggle **Logging = On**, e **Status** sem `LatestDeliveryError`.
- Parar/religar depois: botão **Stop logging** / **Start logging** no topo da página do trail.

---

## 6. Metric filter + SNS + alarme de uso de root

### 6a. Tópico SNS

**Console:** SNS → **Topics** → **Create topic**

- **Type:** *Standard* · **Name:** `awssec-lab02-sns-security-alarms` · **Tags** padrão → **Create topic**
- **Assinatura (opcional)** → **Create subscription** → *Protocol* **Email** → *Endpoint* `sergei.martao@gmail.com` → confirme no link que a AWS envia. No `.tf` isso é `count` condicional em `var.alarm_notification_email`.

### 6b. Metric filter

**Console:** CloudWatch → **Log groups** → `/aws/cloudtrail/awssec-lab02-trail` → aba **Metric filters** → **Create metric filter**

- **Filter pattern:**

```
{ ($.userIdentity.type = "Root") && ($.userIdentity.invokedBy NOT EXISTS) && ($.eventType != "AwsServiceEvent") }
```

- (opcional) **Test pattern** contra sample log data → **Next**
- **Filter name:** `awssec-lab02-metricfilter-root-usage`
- **Metric namespace:** `awssec/lab02`
- **Metric name:** `RootAccountUsageCount`
- **Metric value:** `1`
- **Default value:** `0` → **Next** → **Create metric filter**

### 6c. Alarme

No metric filter recém-criado → **Create alarm** (ou CloudWatch → **Alarms** → **Create alarm** → *Select metric* → `awssec/lab02` → `RootAccountUsageCount`):

- **Statistic:** *Sum* · **Period:** *5 minutes*
- **Threshold type:** *Static* · **Whenever RootAccountUsageCount is** *Greater/Equal* than `1`
- **Additional configuration:** *Datapoints to alarm* `1` de `1` · *Treat missing data as* **notBreaching** ("Treat missing data as good")
- **Notification:** *In alarm* → *Send to* → tópico `awssec-lab02-sns-security-alarms`
- **Alarm name:** `awssec-lab02-alarm-root-usage`
- **Description:** `Disparado quando a conta root da AWS é usada diretamente (fora de eventos automáticos de serviço).`
- **Create alarm**

> **Alarme → SNS não exige topic policy.** O CloudWatch já é publisher confiável do tópico por padrão. (Diferente de EventBridge → SNS no Lab 03, que exige *resource policy* explícita — pegadinha clássica de prova.)

---

## 7. VPC Flow Logs — log group + role + os dois flow logs (ALL, dual delivery)

### 7a. Log group

**Console:** CloudWatch → **Log groups** → **Create log group** → nome `/aws/vpc-flow-logs/awssec-lab02`, retenção `180 days`, tags padrão.

### 7b. Role

**Console:** IAM → **Roles** → **Create role** → *Custom trust policy*:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Principal": { "Service": "vpc-flow-logs.amazonaws.com" }, "Action": "sts:AssumeRole" }
  ]
}
```

- **Role name:** `awssec-lab02-role-flowlogs-cloudwatch`
- Inline policy (JSON), nome `awssec-lab02-policy-flowlogs-cloudwatch-write`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "WriteToLogGroup",
      "Effect": "Allow",
      "Action": ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"],
      "Resource": "arn:aws:logs:us-east-1:230650392331:log-group:/aws/vpc-flow-logs/awssec-lab02:*"
    }
  ]
}
```

> A tela de *Create flow log* oferece um "Create new IAM role" que gera algo tipo `flowlogsRole`. Criar na mão dá o nome do `.tf`.

### 7c. Flow log 1 → CloudWatch Logs

**Console:** VPC → **Your VPCs** → selecione `awssec-lab01-vpc` → aba **Flow logs** → **Create flow log**

- **Name:** `awssec-lab02-flowlog-cloudwatch`
- **Filter:** **All** (não *Accept*, não *Reject* — ADR-012)
- **Maximum aggregation interval:** *10 minutes* (default; o `.tf` não sobrescreve)
- **Destination:** *Send to CloudWatch Logs*
- **Destination log group:** `/aws/vpc-flow-logs/awssec-lab02`
- **IAM role:** `awssec-lab02-role-flowlogs-cloudwatch`
- **Log record format:** *AWS default format* · **Tags** padrão → **Create flow log**

### 7d. Flow log 2 → S3

Mesma VPC → aba **Flow logs** → **Create flow log** de novo:

- **Name:** `awssec-lab02-flowlog-s3`
- **Filter:** **All**
- **Destination:** *Send to an Amazon S3 bucket*
- **S3 bucket ARN:** `arn:aws:s3:::awssec-logs-230650392331`
- **Sem campo de IAM role** — a entrega para S3 usa a **bucket policy** do log bucket (`delivery.logs.amazonaws.com` + `aws:SourceAccount`), já configurada no bootstrap, não uma IAM role.
- **Log file format:** *Plain text* · *Hive-compatible S3 prefixes*: off · *Partition logs by time*: off (defaults; o `.tf` não seta) · **Tags** padrão → **Create flow log**

> **Contraste que a prova cobra:** destino CloudWatch Logs → precisa de **IAM role** (`iam_role_arn`). Destino S3 → precisa de **bucket policy** com `delivery.logs.amazonaws.com`, **sem** role.

---

## 8. Bucket de resultados do Athena (ephemeral — este sim ficaria no state do Terraform)

**Console:** S3 → **Buckets** → **Create bucket**

- **Bucket name:** `awssec-lab02-s3-athena-results-230650392331` · **Region:** `us-east-1`
- **Block Public Access:** as 4 caixas marcadas
- **Bucket Versioning:** *Disable* (bate com o `.tf`)
- **Default encryption:** *SSE-S3* / `AES256`
- **Tags** padrão → **Create bucket**

> Diferente do log bucket, este é **ephemeral** e *viveria* no state do Terraform (ADR-014) — resultado de query é regenerável. `force_destroy = true` não tem campo na tela (é só comportamento de exclusão).

---

## 9. Outputs → SSM Parameter Store

**Console:** Systems Manager → **Parameter Store** → **Create parameter** (6×). Cada um: **Tier** *Standard*, **Type** *String*.

| Name | Value |
|---|---|
| `/lab02/cloudtrail_name`                | `awssec-lab02-trail` |
| `/lab02/cloudtrail_log_group_name`      | `/aws/cloudtrail/awssec-lab02-trail` |
| `/lab02/vpc_flow_logs_log_group_name`   | `/aws/vpc-flow-logs/awssec-lab02` |
| `/lab02/log_bucket_name`                | `awssec-logs-230650392331` |
| `/lab02/athena_results_bucket_name`     | `awssec-lab02-s3-athena-results-230650392331` |
| `/lab02/security_alarms_sns_topic_arn`  | ARN do tópico (SNS → Topics → copiar ARN) |

Labs 06 (Security Analytics), 10 (Forensics) e 12 (Network Security) leem por aqui (ADR-004).

---

## Desmontar (ordem inversa — não toque no que é persistente)

1. **Flow logs** (2×) — VPC → Your VPCs → `awssec-lab01-vpc` → aba **Flow logs** → selecionar → *Delete*.
2. **CloudWatch alarm** `awssec-lab02-alarm-root-usage` → *Delete*.
3. **Metric filter** em `/aws/cloudtrail/awssec-lab02-trail` (aba *Metric filters*) → *Delete*.
4. **SNS** — subscription + tópico `awssec-lab02-sns-security-alarms` → *Delete*.
5. **CloudTrail** → Trails → `awssec-lab02-trail` → **Delete** (para o logging sozinho). O conteúdo do log bucket **fica**.
6. **Athena results bucket** → *Empty* → *Delete*.
7. **CloudWatch log groups** `/aws/cloudtrail/awssec-lab02-trail` e `/aws/vpc-flow-logs/awssec-lab02` → *Delete*.
8. **IAM roles** `awssec-lab02-role-cloudtrail-cloudwatch` e `awssec-lab02-role-flowlogs-cloudwatch` → *Delete*.
9. **Parameter Store** `/lab02/*` → *Delete*.
10. **NÃO mexer** em `awssec-logs-230650392331` (persistente — ADR-009), nos parâmetros `/lab01/*`, nem na VPC do Lab 01.

---

## Notas para a prova (SCS-C03)

- **Trail criado pelo console é sempre multi-region.** O wizard novo não tem toggle de single-region — só API/CLI (`--no-is-multi-region-trail`). `include_global_service_events` também vem ligado.
- **O nome do trail casa com a bucket policy.** Quando o bucket S3 já existe (não foi criado pelo wizard), a policy dele escopa `s3:PutObject` por `aws:SourceArn`/`aws:SourceAccount` de um trail específico. Nome divergente → `LatestDeliveryError: AccessDenied` (TS-006). Confira em **Trails → trail → Status**.
- **Defaults do wizard que este projeto sobrescreve:** (a) criar bucket S3 novo, (b) SSE-KMS com chave nova, (c) criar role própria de CloudWatch Logs, (d) log group com retenção *Never expire*. Os quatro são trocados aqui.
- **Console liga o logging sozinho;** a CLI (`create-trail`) não — precisa de `start-logging`.
- **Management vs Data events:** a 1ª cópia de management events por trail é grátis; data events (S3/Lambda/DynamoDB) custam por evento e vêm **desligados** — você opta por tipo de recurso, via selector.
- **Advanced vs basic event selectors:** só o advanced filtra por `resources.ARN` / `NotStartsWith` (o "exceto o log bucket"). Um trail usa um estilo só.
- **Destino do flow log define o modelo de auth:** CloudWatch Logs → IAM role; S3 → bucket policy com `delivery.logs.amazonaws.com`, sem role. As telas refletem isso (o campo de role some no destino S3).
- **Flow logs `ALL` vs `REJECT`:** ataque bem-sucedido anda sobre tráfego `ACCEPT`ado (C2 em 443 liberada). `REJECT`-only mostra só tentativa que já falhou. `ALL` para forense (ADR-012).
- **Cadeia metric filter → metric → alarm** (tudo no CloudWatch): o filtro transforma linha de log em datapoint; `default_value = 0` faz "sem uso de root" virar um `0` real em vez de dado ausente, então o alarme consegue avaliar. `notBreaching` em *missing data* evita flapping quando genuinamente não há dado.
- **Padrão do filtro de root:** `userIdentity.type = "Root"` **E** `invokedBy NOT EXISTS` (exclui ação de serviço) **E** `eventType != "AwsServiceEvent"` — é o "um humano usou a conta root" canônico.
- **Alarme → SNS não precisa de topic policy** (CloudWatch é publisher confiável). EventBridge → SNS (Lab 03) precisa. Trap comum.
- **Log bucket é SSE-S3, não KMS** (ADR-013 — CMK adiado pro Lab 17). Lifecycle fica em Standard-IA sem Glacier (ADR-011) porque **Athena não lê objeto em classe Glacier** sem restore — relevante quando o Lab 06 consultar esse histórico.
