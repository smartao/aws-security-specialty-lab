# CLI Reference — Lab 03 (GuardDuty)

**Lab:** 03
**Relacionado:** [ADR-015 a ADR-021](../decisions.md), `terraform/environments/lab03/`, [labs/01-detection/03-guardduty/README.md](../../labs/01-detection/03-guardduty/README.md)

> ⚠️ **Status: referência não executada.** Este documento **não** foi rodado nem validado campo a campo (diferente dos `setup-*.md`). É uma tradução manual, feita em 2026-08-27, do que o Terraform do Lab 03 gerencia + o kit de investigação de findings — útil como material de estudo para o SCS-C03 (entender o equivalente AWS CLI de cada recurso e os comandos de análise), mas **não é fonte da verdade**. Pode divergir dos `.tf` a qualquer momento. Confira contra `terraform/environments/lab03/*.tf` antes de usar.

## Objetivo

Duas metades:

1. **Recriar via CLI** o que o Terraform do Lab 03 cria: detector do GuardDuty + 2 protection plans, regra EventBridge com input transformer, tópico SNS, parâmetros SSM.
2. **Kit de investigação** — os comandos que você roda de verdade durante o lab para caçar e dissecar um finding, e para executar os dois cenários de troubleshooting.

## Variáveis usadas em todos os comandos

```bash
export AWS_PROFILE=sergei-upstart
export AWS_REGION=us-east-1          # mesma região da EC2 do Lab 01 — GuardDuty é regional
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
EMAIL="voce@exemplo.com"            # assinatura do tópico SNS de findings
```

---

## 1. Detector + protection plans

```bash
# Habilita o detector (persistente — ADR-015). FIFTEEN_MINUTES = latência mínima
# de REOCORRÊNCIA de finding ao EventBridge (a 1ª ocorrência vai em ~5 min sempre).
DETECTOR_ID=$(aws guardduty create-detector \
  --enable \
  --finding-publishing-frequency FIFTEEN_MINUTES \
  --tags Name=awssec-lab03-guardduty-detector,Project=aws-security-specialty-lab,Lab=lab03 \
  --query DetectorId --output text)
echo "$DETECTOR_ID"

# S3 Protection (ADR-017) — pipeline próprio de S3 data events
aws guardduty update-detector \
  --detector-id "$DETECTOR_ID" \
  --features '[{"Name":"S3_DATA_EVENTS","Status":"ENABLED"}]'

# Malware Protection for EC2 (ADR-017) — snapshot + scan agentless de EBS
aws guardduty update-detector \
  --detector-id "$DETECTOR_ID" \
  --features '[{"Name":"EBS_MALWARE_PROTECTION","Status":"ENABLED"}]'
```

Equivalente Terraform: `aws_guardduty_detector.main` + 2× `aws_guardduty_detector_feature`.

### Verificar

```bash
aws guardduty list-detectors
aws guardduty get-detector --detector-id "$DETECTOR_ID"
# -> Status=ENABLED, FindingPublishingFrequency=FIFTEEN_MINUTES,
#    Features[] com S3_DATA_EVENTS e EBS_MALWARE_PROTECTION = ENABLED
```

---

## 2. Tópico SNS + policy + assinatura

```bash
TOPIC_ARN=$(aws sns create-topic --name awssec-lab03-sns-guardduty-findings \
  --query TopicArn --output text)

# Policy: deixa o EventBridge publicar no tópico
aws sns set-topic-attributes --topic-arn "$TOPIC_ARN" --attribute-name Policy --attribute-value "{
  \"Version\": \"2012-10-17\",
  \"Statement\": [{
    \"Sid\": \"AllowEventBridgePublish\",
    \"Effect\": \"Allow\",
    \"Principal\": {\"Service\": \"events.amazonaws.com\"},
    \"Action\": \"sns:Publish\",
    \"Resource\": \"$TOPIC_ARN\"
  }]
}"

# Assinatura por e-mail (exige clicar no link de confirmação; como o Lab 03 é
# persistente, isso é feito uma vez só — não recai no TS-005 do Lab 02)
aws sns subscribe --topic-arn "$TOPIC_ARN" --protocol email --notification-endpoint "$EMAIL"
```

Equivalente Terraform: `aws_sns_topic` + `aws_sns_topic_policy` + `aws_sns_topic_subscription` (`count` condicional em `var.finding_notification_email`).

---

## 3. Regra EventBridge (findings ≥ MEDIUM) + input transformer

```bash
aws events put-rule \
  --name awssec-lab03-eventbridge-guardduty-findings \
  --description "GuardDuty findings com severidade >= 4 -> SNS -> e-mail" \
  --event-pattern '{
    "source": ["aws.guardduty"],
    "detail-type": ["GuardDuty Finding"],
    "detail": { "severity": [ { "numeric": [ ">=", 4 ] } ] }
  }'

# Alvo = SNS, com input transformer para e-mail legível
aws events put-targets \
  --rule awssec-lab03-eventbridge-guardduty-findings \
  --targets '[{
    "Id": "sns-guardduty-findings",
    "Arn": "'"$TOPIC_ARN"'",
    "InputTransformer": {
      "InputPathsMap": {
        "id": "$.detail.id", "account": "$.account", "region": "$.region",
        "type": "$.detail.type", "severity": "$.detail.severity",
        "title": "$.detail.title", "desc": "$.detail.description",
        "resource": "$.detail.resource.resourceType", "time": "$.time"
      },
      "InputTemplate": "\"GuardDuty finding (Lab 03)\"\n\"Titulo    : <title>\"\n\"Tipo      : <type>\"\n\"Severidade: <severity>\"\n\"Recurso   : <resource>\"\n\"Conta     : <account>  Regiao: <region>\"\n\"Quando    : <time>\"\n\"Finding ID: <id>\"\n\"Descricao : <desc>\""
    }
  }]'
```

Equivalente Terraform: `aws_cloudwatch_event_rule` + `aws_cloudwatch_event_target` (bloco `input_transformer`).

**Gotcha de exame:** o `detail.severity` é um **número** (8.0), não a string "High". O filtro numérico do EventBridge (`{"numeric":[">=",4]}`) é a forma certa; casar por string não funcionaria.

---

## 4. Outputs → SSM Parameter Store

```bash
aws ssm put-parameter --name /lab03/detector_id --type String --value "$DETECTOR_ID" --overwrite
aws ssm put-parameter --name /lab03/sns_topic_arn --type String --value "$TOPIC_ARN" --overwrite
aws ssm put-parameter --name /lab03/eventbridge_rule_name --type String \
  --value awssec-lab03-eventbridge-guardduty-findings --overwrite

aws ssm get-parameters-by-path --path /lab03 --recursive
```

---

## 5. Kit de investigação

### Teste de encanamento (sample findings — fabricados, mas passam pela regra igual aos reais)

```bash
# ASPAS SIMPLES obrigatórias em cada tipo: o "&" sem aspas joga o comando pra
# background e o "!" dispara history expansion no zsh/bash — sem aspas, nada é criado.
aws guardduty create-sample-findings --detector-id "$DETECTOR_ID" \
  --finding-types 'Backdoor:EC2/C&CActivity.B!DNS' 'Policy:S3/BucketAnonymousAccessGranted'
# aguarde alguns minutos -> e-mail legível deve chegar
```

### Listar e dissecar findings reais

```bash
# IDs dos findings ativos (não arquivados), mais recentes primeiro
aws guardduty list-findings --detector-id "$DETECTOR_ID" \
  --sort-criteria '{"AttributeName":"updatedAt","OrderBy":"DESC"}'

# Detalhe completo (JSON) — é aqui que mora a anatomia do finding
aws guardduty get-findings --detector-id "$DETECTOR_ID" --finding-ids <FINDING_ID>

# Campos-chave a olhar:
#   .Findings[].Type                                  -> Backdoor:EC2/C&CActivity.B!DNS
#   .Findings[].Severity                              -> 8
#   .Findings[].Service.Action.DnsRequestAction.Domain-> guarddutyc2activityb.com
#   .Findings[].Resource.InstanceDetails.InstanceId   -> i-xxxx
#   .Findings[].Resource.InstanceDetails.IamInstanceProfile.Arn
#   .Findings[].Service.EventFirstSeen / .EventLastSeen / .Count

# Estatística por tipo/severidade
aws guardduty get-findings-statistics --detector-id "$DETECTOR_ID" \
  --finding-statistic-types COUNT_BY_SEVERITY
```

### Correlação com o Lab 02 (investigação própria)

```bash
# VPC Flow Logs — o host chegou a CONECTAR no IP resolvido, ou só resolveu DNS?
LG=$(aws ssm get-parameter --name /lab02/vpc_flow_logs_log_group_name --query Parameter.Value --output text)
aws logs start-query --log-group-name "$LG" \
  --start-time $(date -d '-1 hour' +%s) --end-time $(date +%s) \
  --query-string 'fields @timestamp, srcAddr, dstAddr, dstPort, action | filter dstAddr = "<IP_RESOLVIDO>" | sort @timestamp desc'

# CloudTrail — a IAM role da instância fez algo anômalo perto do horário do finding?
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=i-xxxx \
  --start-time <ISO> --end-time <ISO>
```

---

## 6. Cenário de troubleshooting A — suppression rule

```bash
# Cria a suppression rule que auto-arquiva o finding de DNS C&C
aws guardduty create-filter --detector-id "$DETECTOR_ID" \
  --name awssec-lab03-suppress-c2dns \
  --action ARCHIVE \
  --finding-criteria '{"Criterion":{"type":{"Eq":["Backdoor:EC2/C&CActivity.B!DNS"]}}}'

# ... rodar o Ataque 1 de novo -> nenhum e-mail, finding some da lista default

# Investigar: o finding EXISTE, só está arquivado
aws guardduty list-findings --detector-id "$DETECTOR_ID" \
  --finding-criteria '{"Criterion":{"service.archived":{"Eq":["true"]}}}'

aws guardduty list-filters --detector-id "$DETECTOR_ID"
aws guardduty get-filter --detector-id "$DETECTOR_ID" --filter-name awssec-lab03-suppress-c2dns
# -> Action = ARCHIVE  => causa raiz

# Correção
aws guardduty delete-filter --detector-id "$DETECTOR_ID" --filter-name awssec-lab03-suppress-c2dns
```

**Por que nenhum e-mail:** findings arquivados (por suppression rule) **não** são enviados ao EventBridge. O registro continua existindo para auditoria — suppression ≠ delete.

---

## 7. Cenário de troubleshooting B — filtro de severidade

```bash
# Desliga só o Block Public Access de uma bucket (SEM policy anônima)
aws s3api put-public-access-block --bucket <bucket-teste> \
  --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

# -> finding Policy:S3/BucketBlockPublicAccessDisabled aparece no console, Severity 2.0 (LOW)
# -> NENHUM e-mail: o event_pattern da regra exige severity >= 4. Comportamento esperado (ADR-018).
aws guardduty get-findings --detector-id "$DETECTOR_ID" --finding-ids <FID> \
  --query 'Findings[].{Type:Type,Severity:Severity}'
```

---

## 8. Multi-account / delegated admin (conceitual — implementação no Lab 19)

```bash
# A conta já é management da org o-23e9438ykt. Estes comandos são o QUE seria
# feito no Lab 19, quando existirem contas member:
aws guardduty list-organization-admin-accounts
# aws guardduty enable-organization-admin-account --admin-account-id <SECURITY_ACCOUNT_ID>
# aws guardduty update-organization-configuration --detector-id <id> --auto-enable-organization-members ALL
```

Modelo: uma conta vira **delegated administrator** do GuardDuty para a org; ela vê e gerencia os findings de todas as contas **member**; `auto-enable` liga o GuardDuty automaticamente em contas novas. Centraliza a detecção sem depender de export para S3.

---

## Notas para a prova (SCS-C03)

- **GuardDuty é regional.** Um finding só aparece na região onde a atividade ocorreu. Ameaça multi-região → habilitar em todas as regiões (ou via org config).
- **Pipeline de dados próprio.** GuardDuty não precisa de trail do CloudTrail, nem dos VPC Flow Logs configurados, nem de DNS logging — ele lê essas fontes direto. Habilitar o detector basta.
- **`finding_publishing_frequency`** afeta **reocorrências/atualizações** de um finding, não a 1ª entrega (sempre ~5 min ao EventBridge). Valores: `FIFTEEN_MINUTES`, `ONE_HOUR`, `SIX_HOURS` (default).
- **Suppression rule / filtro com `ARCHIVE`** arquiva o finding e **impede o envio ao EventBridge**, mas mantém o registro. Diferente de não ter finding nenhum.
- **Export de findings para S3 exige KMS CMK** (SSE-S3 não é aceito). Para agregar findings sem export: Security Hub (integração de serviço direta) ou Security Lake.
- **Severity:** 1.0–3.9 LOW · 4.0–6.9 MEDIUM · 7.0–8.9 HIGH · 9.0–10.0 CRITICAL. No evento do EventBridge é número, não string.
- **Sample findings** (`create-sample-findings`) têm `service.additionalInfo.sample = true` mas carregam a severidade real do tipo — servem para testar automação/roteamento.
- **Malware Protection for EC2** é acionado por findings suspeitos de EC2 (ou on-demand); tira snapshot do EBS e escaneia numa conta gerenciada pela AWS. Não é scan contínuo.
