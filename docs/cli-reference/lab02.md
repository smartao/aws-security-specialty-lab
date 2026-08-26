# CLI Reference — Lab 02 (Centralized Logging Foundation)

**Lab:** 02
**Relacionado:** [ADR-009 a ADR-014](../decisions.md), `terraform/environments/lab02/`, [setup-log-bucket-bootstrap.md](../setup-log-bucket-bootstrap.md)

> ⚠️ **Status: referência não executada.** Este documento **não** foi rodado nem validado campo a campo (diferente dos `setup-*.md`, que carregam esse selo). É uma tradução manual, feita em 2026-08-26, do que o Terraform do Lab 02 já gerencia — útil como material de estudo para o exame SCS-C03 (entender o equivalente em AWS CLI de cada recurso), mas **não é fonte da verdade**. Pode divergir do Terraform real a qualquer momento que `terraform/environments/lab02/*.tf` mudar, sem nenhum aviso automático (não há `plan`/`state` cobrindo este arquivo). Se for usar de verdade, confira contra os `.tf` atuais antes de rodar.

## Objetivo

Mostrar, comando a comando, como recriar via AWS CLI os recursos que o Terraform do Lab 02 cria hoje: CloudTrail multi-region com dual delivery, metric filter + alarme de uso de root, VPC Flow Logs (`ALL`, dual delivery) e o bucket de resultados do Athena. O bucket de logs persistente (`awssec-logs-230650392331`) **não** está aqui — ele já é criado via CLI de verdade em [setup-log-bucket-bootstrap.md](../setup-log-bucket-bootstrap.md), fora do ciclo de vida deste lab.

## Variáveis usadas em todos os comandos

```bash
export AWS_PROFILE=sergei-upstart
export AWS_REGION=us-east-1
ACCOUNT_ID=230650392331
LOG_BUCKET=awssec-logs-230650392331
TRAIL_NAME=awssec-lab02-trail
```

## 1. CloudWatch Log Group — CloudTrail

```bash
aws logs create-log-group \
  --log-group-name "/aws/cloudtrail/${TRAIL_NAME}" \
  --tags Project=aws-security-specialty-lab,Lab=lab02,Environment=study,ManagedBy=terraform,Name=awssec-lab02-loggroup-cloudtrail

aws logs put-retention-policy \
  --log-group-name "/aws/cloudtrail/${TRAIL_NAME}" \
  --retention-in-days 180
```

## 2. IAM role que o CloudTrail assume para escrever no log group

```bash
cat > /tmp/cloudtrail-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "cloudtrail.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name awssec-lab02-role-cloudtrail-cloudwatch \
  --assume-role-policy-document file:///tmp/cloudtrail-trust-policy.json \
  --tags Key=Project,Value=aws-security-specialty-lab Key=Lab,Value=lab02 Key=Environment,Value=study Key=ManagedBy,Value=terraform

cat > /tmp/cloudtrail-cw-write-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "WriteToLogGroup",
    "Effect": "Allow",
    "Action": ["logs:CreateLogStream", "logs:PutLogEvents"],
    "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/cloudtrail/${TRAIL_NAME}:*"
  }]
}
EOF

aws iam put-role-policy \
  --role-name awssec-lab02-role-cloudtrail-cloudwatch \
  --policy-name awssec-lab02-policy-cloudtrail-cloudwatch-write \
  --policy-document file:///tmp/cloudtrail-cw-write-policy.json
```

> Gotcha real do CLI (Terraform absorve isso sozinho): se o `create-trail` do próximo passo rodar imediato após o `create-role`, às vezes falha por propagação IAM ainda não ter se espalhado — se acontecer, é só re-tentar em alguns segundos.

## 3. O Trail em si (multi-region, dual delivery)

```bash
aws cloudtrail create-trail \
  --name "$TRAIL_NAME" \
  --s3-bucket-name "$LOG_BUCKET" \
  --is-multi-region-trail \
  --include-global-service-events \
  --enable-log-file-validation \
  --cloud-watch-logs-log-group-arn "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/cloudtrail/${TRAIL_NAME}:*" \
  --cloud-watch-logs-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/awssec-lab02-role-cloudtrail-cloudwatch" \
  --tags-list Key=Name,Value=$TRAIL_NAME Key=Project,Value=aws-security-specialty-lab Key=Lab,Value=lab02 Key=Environment,Value=study Key=ManagedBy,Value=terraform
```

## 4. Advanced event selectors — management + data events do S3 (exceto o log bucket)

```bash
cat > /tmp/advanced-event-selectors.json <<EOF
[
  {
    "Name": "Management events (todos)",
    "FieldSelectors": [
      { "Field": "eventCategory", "Equals": ["Management"] }
    ]
  },
  {
    "Name": "S3 data events, todos os buckets, exceto o log bucket",
    "FieldSelectors": [
      { "Field": "eventCategory", "Equals": ["Data"] },
      { "Field": "resources.type", "Equals": ["AWS::S3::Object"] },
      { "Field": "resources.ARN", "NotStartsWith": ["arn:aws:s3:::${LOG_BUCKET}/"] }
    ]
  }
]
EOF

aws cloudtrail put-event-selectors \
  --trail-name "$TRAIL_NAME" \
  --advanced-event-selectors file:///tmp/advanced-event-selectors.json
```

## 5. Ligar o logging

`create-trail` não liga o trail sozinho (diferente do `aws_cloudtrail` do Terraform, que já chama `StartLogging` como parte do apply):

```bash
aws cloudtrail start-logging --name "$TRAIL_NAME"
```

## 6. Metric filter + SNS + alarme de uso de root

```bash
aws logs put-metric-filter \
  --log-group-name "/aws/cloudtrail/${TRAIL_NAME}" \
  --filter-name awssec-lab02-metricfilter-root-usage \
  --filter-pattern '{ ($.userIdentity.type = "Root") && ($.userIdentity.invokedBy NOT EXISTS) && ($.eventType != "AwsServiceEvent") }' \
  --metric-transformations 'metricName=RootAccountUsageCount,metricNamespace=awssec/lab02,metricValue=1,defaultValue=0'

TOPIC_ARN=$(aws sns create-topic \
  --name awssec-lab02-sns-security-alarms \
  --tags Key=Name,Value=awssec-lab02-sns-security-alarms Key=Project,Value=aws-security-specialty-lab Key=Lab,Value=lab02 Key=Environment,Value=study Key=ManagedBy,Value=terraform \
  --query 'TopicArn' --output text)

# opcional — a inscrição por e-mail exige confirmação manual no link recebido
aws sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol email \
  --notification-endpoint sergei.martao@gmail.com

aws cloudwatch put-metric-alarm \
  --alarm-name awssec-lab02-alarm-root-usage \
  --alarm-description "Disparado quando a conta root da AWS é usada diretamente (fora de eventos automáticos de serviço)." \
  --namespace "awssec/lab02" \
  --metric-name RootAccountUsageCount \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$TOPIC_ARN" \
  --tags Key=Name,Value=awssec-lab02-alarm-root-usage Key=Project,Value=aws-security-specialty-lab Key=Lab,Value=lab02 Key=Environment,Value=study Key=ManagedBy,Value=terraform
```

## 7. VPC Flow Logs — log group + role + os dois flow logs (ALL, dual delivery)

```bash
aws logs create-log-group \
  --log-group-name "/aws/vpc-flow-logs/awssec-lab02" \
  --tags Project=aws-security-specialty-lab,Lab=lab02,Environment=study,ManagedBy=terraform,Name=awssec-lab02-loggroup-vpc-flow-logs

aws logs put-retention-policy \
  --log-group-name "/aws/vpc-flow-logs/awssec-lab02" \
  --retention-in-days 180

cat > /tmp/flowlogs-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "vpc-flow-logs.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name awssec-lab02-role-flowlogs-cloudwatch \
  --assume-role-policy-document file:///tmp/flowlogs-trust-policy.json \
  --tags Key=Project,Value=aws-security-specialty-lab Key=Lab,Value=lab02 Key=Environment,Value=study Key=ManagedBy,Value=terraform

cat > /tmp/flowlogs-cw-write-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "WriteToLogGroup",
    "Effect": "Allow",
    "Action": ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"],
    "Resource": "arn:aws:logs:${AWS_REGION}:${ACCOUNT_ID}:log-group:/aws/vpc-flow-logs/awssec-lab02:*"
  }]
}
EOF

aws iam put-role-policy \
  --role-name awssec-lab02-role-flowlogs-cloudwatch \
  --policy-name awssec-lab02-policy-flowlogs-cloudwatch-write \
  --policy-document file:///tmp/flowlogs-cw-write-policy.json

VPC_ID=$(aws ssm get-parameter --name /lab01/vpc_id --query 'Parameter.Value' --output text)

aws ec2 create-flow-logs \
  --resource-type VPC --resource-ids "$VPC_ID" \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name "/aws/vpc-flow-logs/awssec-lab02" \
  --deliver-logs-permission-arn "arn:aws:iam::${ACCOUNT_ID}:role/awssec-lab02-role-flowlogs-cloudwatch" \
  --tag-specifications 'ResourceType=vpc-flow-log,Tags=[{Key=Name,Value=awssec-lab02-flowlog-cloudwatch},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab02},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]'

aws ec2 create-flow-logs \
  --resource-type VPC --resource-ids "$VPC_ID" \
  --traffic-type ALL \
  --log-destination-type s3 \
  --log-destination "arn:aws:s3:::${LOG_BUCKET}" \
  --tag-specifications 'ResourceType=vpc-flow-log,Tags=[{Key=Name,Value=awssec-lab02-flowlog-s3},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab02},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]'
```

Repare que o flow log com destino S3 **não** leva `--deliver-logs-permission-arn` — a entrega para S3 usa a bucket policy do log bucket (`delivery.logs.amazonaws.com` + `aws:SourceAccount`), já configurada no bootstrap CLI, não uma IAM role.

## 8. Bucket de resultados do Athena (ephemeral — este sim ficaria no state do Terraform)

```bash
BUCKET=awssec-lab02-s3-athena-results-${ACCOUNT_ID}

aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION"

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-bucket-tagging \
  --bucket "$BUCKET" \
  --tagging 'TagSet=[{Key=Name,Value=awssec-lab02-s3-athena-results},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab02},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]'
```

## 9. Outputs → SSM Parameter Store

```bash
aws ssm put-parameter --name /lab02/cloudtrail_name --type String --overwrite --value "$TRAIL_NAME"
aws ssm put-parameter --name /lab02/cloudtrail_log_group_name --type String --overwrite --value "/aws/cloudtrail/${TRAIL_NAME}"
aws ssm put-parameter --name /lab02/vpc_flow_logs_log_group_name --type String --overwrite --value "/aws/vpc-flow-logs/awssec-lab02"
aws ssm put-parameter --name /lab02/log_bucket_name --type String --overwrite --value "$LOG_BUCKET"
aws ssm put-parameter --name /lab02/athena_results_bucket_name --type String --overwrite --value "$BUCKET"
aws ssm put-parameter --name /lab02/security_alarms_sns_topic_arn --type String --overwrite --value "$TOPIC_ARN"
```

## Notas para a prova (SCS-C03)

- **`ManagedBy=terraform`** nas tags acima é só para espelhar fielmente o Terraform — se isso fosse rodado de verdade fora do Terraform, o padrão do próprio projeto (ver [setup-log-bucket-bootstrap.md](../setup-log-bucket-bootstrap.md)) usaria `ManagedBy=manual`.
- A ordem importa em dois pontos que o Terraform resolve via grafo de dependência mas o CLI não: (1) a role do CloudTrail precisa existir *antes* do `create-trail`; (2) o `start-logging` precisa vir *depois* do `create-trail` — a API não liga sozinha.
- Flow log com destino S3 depende de bucket policy (`delivery.logs.amazonaws.com`), não de IAM role — diferente do destino CloudWatch Logs, que exige `--deliver-logs-permission-arn`.
