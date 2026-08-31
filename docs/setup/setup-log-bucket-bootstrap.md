# Setup — Log Bucket (bucket S3 persistente para CloudTrail + VPC Flow Logs)

**Lab:** 02 — mas o bucket não pertence ao ciclo de vida do lab (persistente, ver [ADR-009](decisions.md#adr-009--log-bucket-persistente-fora-do-state-do-lab-02))
**Relacionado:** [ADR-009](decisions.md#adr-009--log-bucket-persistente-fora-do-state-do-lab-02), [ADR-013](decisions.md#adr-013--encryption-sse-s3-no-log-bucket-cmk-adiado-para-o-lab-17), [ADR-024](decisions.md#adr-024--aws-config-no-lab-04-recorder-contínuo-escopo-restrito-entrega-no-log-bucket)
**Status:** ✅ Executado e validado via CLI campo a campo em 2026-08-25. ⏳ **Amendment do Lab 04 (seção 8) — pendente de aplicação** (statement do AWS Config, adicionado ao design em 2026-08-31).

## Objetivo

Criar, uma única vez e via AWS CLI (fora de qualquer ciclo de vida de lab), o bucket S3 que recebe a entrega do CloudTrail e das VPC Flow Logs do projeto inteiro. Diferente do restante do Lab 02 (destruído/recriado a cada sessão de estudo), este bucket é **evidência/histórico** — nunca deve ser destruído junto com o resto do lab. Mesmo padrão de raciocínio já aplicado ao bucket de backend do Terraform (ver [setup-backend-bootstrap.md](setup-backend-bootstrap.md)).

## Por que AWS CLI e não Terraform

Se este bucket vivesse dentro do state do Lab 02, um `terraform destroy` de rotina apagaria os logs junto — exatamente o oposto do objetivo (evidência histórica para os Labs 06 e 10). A alternativa de mantê-lo no state com `lifecycle { prevent_destroy = true }` foi descartada: esse bloco falha o `plan`/`destroy` **inteiro**, não só daquele recurso, quebrando o hábito de destroy/recreate do resto do Lab 02 a cada sessão.

## Nome e nomenclatura

Como o bucket de backend, este **não** segue o padrão `{projeto}-{lab}-{tipo-recurso}-{detalhe}` da ADR-005 — não pertence a um lab específico, é infraestrutura de bootstrap compartilhada por todo o projeto (CloudTrail é sempre conta inteira; VPC Flow Logs de labs futuros com VPC própria, ex: Lab 14/19, também podem apontar para cá).

```text
awssec-logs-230650392331
```

Prefixo do projeto + account ID, para unicidade global sem depender de sorte (mesmo padrão do `awssec-tfstate-230650392331`).

## Pré-requisitos

- Sessão autenticada via IAM Identity Center (`aws sso login --profile sergei-upstart`).
- Permissão de administrador na conta (permission set `AdministratorAccess`).

## Passo a passo (CLI)

### 1. Criar o bucket

```bash
aws s3api create-bucket \
  --bucket awssec-logs-230650392331 \
  --region us-east-1 \
  --profile sergei-upstart
```

### 2. Versionamento

```bash
aws s3api put-bucket-versioning \
  --bucket awssec-logs-230650392331 \
  --versioning-configuration Status=Enabled \
  --profile sergei-upstart
```

### 3. Block Public Access (explícito, mesmo sendo default em bucket novo)

```bash
aws s3api put-public-access-block \
  --bucket awssec-logs-230650392331 \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
  --profile sergei-upstart
```

### 4. Encryption — SSE-S3

```bash
aws s3api put-bucket-encryption \
  --bucket awssec-logs-230650392331 \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":true}]}' \
  --profile sergei-upstart
```

SSE-S3 (não SSE-KMS) por decisão explícita — ver [ADR-013](decisions.md#adr-013--encryption-sse-s3-no-log-bucket-cmk-adiado-para-o-lab-17): introduzir uma Customer Managed Key agora antecipa conteúdo do Lab 17 (KMS Key Policies) antes da hora, e este bucket não guarda dado sensível de negócio — guarda metadados de auditoria (quem fez o quê, quando).

### 5. Tags

```bash
aws s3api put-bucket-tagging \
  --bucket awssec-logs-230650392331 \
  --tagging 'TagSet=[{Key=Project,Value=aws-security-specialty-lab},{Key=Purpose,Value=centralized-logging-bootstrap},{Key=ManagedBy,Value=manual}]' \
  --profile sergei-upstart
```

`ManagedBy=manual` (não `terraform`), mesmo motivo do bucket de backend: este recurso nunca está dentro de um state Terraform.

### 6. Lifecycle — Standard-IA aos 30 dias, sem Glacier

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket awssec-logs-230650392331 \
  --lifecycle-configuration file://log-bucket-lifecycle.json \
  --profile sergei-upstart
```

`log-bucket-lifecycle.json`:

```json
{
  "Rules": [
    {
      "ID": "transition-to-standard-ia",
      "Status": "Enabled",
      "Filter": {},
      "Transitions": [
        { "Days": 30, "StorageClass": "STANDARD_IA" }
      ],
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }
  ]
}
```

Sem transição para Glacier — decisão do design do Lab 02 ([ADR-011](decisions.md#adr-011--lifecycle-standard-ia-aos-30-dias-sem-glacier)): Athena (Lab 06) não consulta objetos em classe Glacier sem um restore explícito, e o Lab 06 precisa consultar exatamente este histórico de logs.

### 7. Bucket policy — TLS-only + delivery CloudTrail + delivery VPC Flow Logs

```bash
aws s3api put-bucket-policy \
  --bucket awssec-logs-230650392331 \
  --policy file://log-bucket-policy.json \
  --profile sergei-upstart
```

`log-bucket-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::awssec-logs-230650392331",
      "Condition": {
        "StringEquals": {
          "aws:SourceArn": "arn:aws:cloudtrail:us-east-1:230650392331:trail/awssec-lab02-trail"
        }
      }
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::awssec-logs-230650392331/AWSLogs/230650392331/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control",
          "aws:SourceArn": "arn:aws:cloudtrail:us-east-1:230650392331:trail/awssec-lab02-trail"
        }
      }
    },
    {
      "Sid": "AWSFlowLogsAclCheck",
      "Effect": "Allow",
      "Principal": { "Service": "delivery.logs.amazonaws.com" },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::awssec-logs-230650392331",
      "Condition": { "StringEquals": { "aws:SourceAccount": "230650392331" } }
    },
    {
      "Sid": "AWSFlowLogsWrite",
      "Effect": "Allow",
      "Principal": { "Service": "delivery.logs.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::awssec-logs-230650392331/AWSLogs/230650392331/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control",
          "aws:SourceAccount": "230650392331"
        }
      }
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::awssec-logs-230650392331",
        "arn:aws:s3:::awssec-logs-230650392331/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

**Nota importante — acoplamento com o nome do trail:** as duas primeiras statements (`AWSCloudTrailAclCheck`/`AWSCloudTrailWrite`) restringem a escrita via `aws:SourceArn` ao trail **exato** `awssec-lab02-trail`, que ainda não existe neste ponto (será criado depois, via Terraform). Esse condicional previne o problema de "confused deputy" (outro trail, de outra conta, apontando para este bucket) — só funciona porque o nome do trail foi decidido *antes* de criar a policy, não porque o trail já existe. As statements de Flow Logs usam `aws:SourceAccount` em vez de `aws:SourceArn` porque o ID do flow log é gerado dinamicamente na criação (não dá pra prever o ARN com antecedência).

Se o nome do trail mudar no Terraform do Lab 02, esta policy precisa ser atualizada manualmente (é fora do state — não há `terraform plan` para avisar da divergência).

### 8. Amendment (Lab 04, [ADR-024](decisions.md#adr-024--aws-config-no-lab-04-recorder-contínuo-escopo-restrito-entrega-no-log-bucket)) — statement do AWS Config ⏳ pendente

O Lab 04 entrega o histórico do **AWS Config** neste mesmo bucket (recorder de escopo restrito, ADR-024). O `aws_config_delivery_channel` do Terraform do Lab 04 (`terraform/environments/lab04/config.tf`) **falha no `apply`** com `InsufficientDeliveryPolicyException` se a bucket policy não autorizar `config.amazonaws.com` **antes**. Mesmo padrão das statements de CloudTrail/Flow Logs acima — o bucket é bootstrap, fora de qualquer state, então isto é passo manual.

Adicionar estas 3 statements ao array `Statement` do `log-bucket-policy.json` (antes da `DenyInsecureTransport`, que deve permanecer por último) e reaplicar:

```json
{
  "Sid": "AWSConfigBucketPermissionsCheck",
  "Effect": "Allow",
  "Principal": { "Service": "config.amazonaws.com" },
  "Action": "s3:GetBucketAcl",
  "Resource": "arn:aws:s3:::awssec-logs-230650392331",
  "Condition": { "StringEquals": { "aws:SourceAccount": "230650392331" } }
},
{
  "Sid": "AWSConfigBucketExistenceCheck",
  "Effect": "Allow",
  "Principal": { "Service": "config.amazonaws.com" },
  "Action": "s3:ListBucket",
  "Resource": "arn:aws:s3:::awssec-logs-230650392331",
  "Condition": { "StringEquals": { "aws:SourceAccount": "230650392331" } }
},
{
  "Sid": "AWSConfigBucketDelivery",
  "Effect": "Allow",
  "Principal": { "Service": "config.amazonaws.com" },
  "Action": "s3:PutObject",
  "Resource": "arn:aws:s3:::awssec-logs-230650392331/AWSLogs/230650392331/Config/*",
  "Condition": {
    "StringEquals": {
      "s3:x-amz-acl": "bucket-owner-full-control",
      "aws:SourceAccount": "230650392331"
    }
  }
}
```

```bash
aws s3api put-bucket-policy \
  --bucket awssec-logs-230650392331 \
  --policy file://log-bucket-policy.json \
  --profile sergei-upstart
```

**Prefixo de entrega:** `AWSLogs/230650392331/Config/` — o Terraform do Lab 04 **não** define `s3_key_prefix` no delivery channel, então o Config usa o path padrão. Se um `s3_key_prefix` for adicionado depois, o `Resource` da statement `AWSConfigBucketDelivery` passa a `<prefix>/AWSLogs/230650392331/Config/*`.

**`aws:SourceAccount` em vez de `aws:SourceArn`:** o principal `config.amazonaws.com` é a conta inteira (um recorder por região/conta), não um recurso com ARN previsível — mesma razão das statements de Flow Logs.

Marcar esta seção como ✅ executada quando a policy for reaplicada, antes do primeiro `terraform apply` do Lab 04.

## Validação (CLI)

```bash
aws s3api get-bucket-versioning --bucket awssec-logs-230650392331 --profile sergei-upstart
aws s3api get-bucket-encryption --bucket awssec-logs-230650392331 --profile sergei-upstart
aws s3api get-public-access-block --bucket awssec-logs-230650392331 --profile sergei-upstart
aws s3api get-bucket-lifecycle-configuration --bucket awssec-logs-230650392331 --profile sergei-upstart
aws s3api get-bucket-policy --bucket awssec-logs-230650392331 --profile sergei-upstart
aws s3api get-bucket-tagging --bucket awssec-logs-230650392331 --profile sergei-upstart
```

**Confirmado em 2026-08-25:** `Status: Enabled` no versionamento, `SSEAlgorithm: AES256` na criptografia, os 4 campos de `PublicAccessBlockConfiguration` como `true`, lifecycle `transition-to-standard-ia` (30 dias, `STANDARD_IA`) presente, policy com as 5 statements acima refletida, tags (`Project`, `Purpose=centralized-logging-bootstrap`, `ManagedBy=manual`) e `ObjectOwnership: BucketOwnerEnforced` corretos.

## Regras de convivência com este bucket

- **Nunca** roda `terraform destroy` do Lab 02 esperando que ele alcance este bucket — ele está fora do state do lab (mesma regra do bucket de backend).
- Estrutura de prefixo dentro do bucket: `AWSLogs/230650392331/CloudTrail/...`, `AWSLogs/230650392331/vpcflowlogs/...` e `AWSLogs/230650392331/Config/...` (path padrão usado pelos serviços de entrega da AWS) — Lab 06 (Athena) vai apontar para esses prefixos.
- O `terraform destroy` do Lab 04 remove o recorder/delivery channel do Config, **não** este bucket nem os objetos já entregues. Se o Lab 04 for removido de vez, a statement do Config na policy pode ser retirada manualmente (opcional — não custa nada deixar).
- Se o Lab 02 (Terraform) for destruído e recriado com um nome de trail diferente de `awssec-lab02-trail`, a bucket policy precisa ser reaplicada manualmente com o novo `aws:SourceArn` antes do próximo `terraform apply` criar o trail — senão a entrega do CloudTrail falha silenciosamente por falta de permissão no bucket.
