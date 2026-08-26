# Lab 02 — Centralized Logging Foundation

**Status:** ✅ Implementado e validado via CLI campo a campo em 2026-08-26 — `terraform apply` de 22 recursos sem erros, CloudTrail logando (`IsLogging=True`), Flow Logs `ACTIVE` (S3 + CloudWatch, `ALL`), entrega confirmada no log bucket (`CloudTrail/`, `CloudTrail-Digest/`, `vpcflowlogs/`). Falha proposital, troubleshooting e evidências ainda pendentes.

## SCS-C03

- Domínio/Fase: Fase 0 — Foundation
- Habilidades tocadas neste lab:
  - **1.1.1 / 1.1.2** — Design e configuração de fontes de log (CloudTrail, VPC Flow Logs) para detecção
  - **1.2.1** — Análise de eventos de segurança a partir de fontes de log centralizadas
  - **6.2.1** — IaC consistente e seguro (Terraform: naming, tags, SSM)
  - **6.3.x** — Retenção e proteção de logs de auditoria

## Objetivo

Construir a fundação de observabilidade da plataforma: rastreabilidade de toda chamada de API (CloudTrail) e de todo o tráfego de rede da VPC (Flow Logs), com um destino de logs que é ao mesmo tempo durável/barato (S3, para Athena no Lab 06) e consultável quase em tempo real (CloudWatch Logs, para metric filters e Logs Insights). Sem esta camada, os Labs 06 (Analytics), 10 (Forensics) e 12 (Network) não têm matéria-prima para investigar nada.

## Cenário

O Lab 01 entregou rede e identidade, mas terminou com uma lacuna deliberada: nenhuma chamada de API é registrada, nenhum pacote de rede é auditado. Um atacante que comprometesse uma credencial hoje operaria "no escuro" — sem qualquer rastro para investigação posterior. O Lab 02 fecha essa lacuna antes de qualquer workload real ou controle de detecção (GuardDuty, Lab 03) entrar em cena.

## Requisitos de segurança

- **CloudTrail multi-region** — elimina o ponto cego de um atacante operar deliberadamente numa região não coberta por um trail single-region.
- **Data events de S3 habilitados** (todos os buckets, atuais e futuros), **excluindo o próprio log bucket** — visibilidade sobre `GetObject`/`PutObject`, não só sobre a API de controle.
- **Entrega dupla (S3 + CloudWatch Logs)** para CloudTrail e para VPC Flow Logs — S3 para retenção barata/Athena, CloudWatch para metric filters/Logs Insights em tempo quase real.
- **VPC Flow Logs com tráfego `ALL`** (não só `REJECT`) — um ataque bem-sucedido anda sobre tráfego aceito; `REJECT`-only cegaria justamente o cenário que a forense (Lab 10) mais precisa enxergar.
- **Alarme de uso da conta root** — a conta root nunca deveria ser usada no dia a dia; qualquer uso é, por si só, um evento suspeito.
- **Log bucket persistente**, fora do ciclo de destroy/recreate do resto do lab — é evidência, não configuração descartável.
- **Retenção de 180 dias no CloudWatch Logs** — alinhada ao horizonte de 6 meses da conta (teto de custo do projeto).

## Arquitetura

```text
                         AWS Account
                              │
        ┌─────────────────────┴─────────────────────┐
        ▼                                             ▼
   CloudTrail                                  VPC Flow Logs
 (multi-region,                                (VPC do Lab 01,
  data events S3)                               tráfego ALL)
        │                                             │
   ┌────┴────┐                                   ┌────┴────┐
   ▼         ▼                                   ▼         ▼
CloudWatch   S3 (log bucket persistente,     CloudWatch    S3 (mesmo
  Logs        fora do state — bootstrap)       Logs         log bucket)
   │              │
   │              ▼
   │         Athena (Lab 06) ──▶ bucket de resultados (ephemeral)
   │
   ▼
Metric Filter (root account usage)
   │
   ▼
CloudWatch Alarm ──▶ SNS Topic
```

## Serviços AWS envolvidos

- AWS CloudTrail (multi-region trail, data events, log file validation)
- Amazon CloudWatch Logs (log groups, metric filter, alarm)
- Amazon S3 (log bucket persistente + bucket de resultados do Athena, ephemeral)
- VPC Flow Logs
- Amazon SNS (notificação do alarme de conta root)
- Amazon Athena (consumo dos logs — habilitado formalmente no Lab 06)
- IAM (roles de serviço para CloudTrail → CloudWatch e Flow Logs → CloudWatch)
- SSM Parameter Store (outputs do Lab 02 para labs downstream)

## Implementação

### AWS CLI (bootstrap, fora do Terraform)

O log bucket (`awssec-logs-230650392331`) foi criado via CLI, uma única vez, fora do state do Lab 02 — mesmo padrão do bucket de backend do Terraform. Passo a passo completo, com todos os comandos e a bucket policy (TLS-only + delivery CloudTrail/Flow Logs), em [docs/setup-log-bucket-bootstrap.md](../../../docs/setup-log-bucket-bootstrap.md).

Validado campo a campo em 2026-08-25: versionamento `Enabled`, encryption `AES256` (SSE-S3), Block Public Access com os 4 campos `true`, lifecycle `Standard-IA aos 30 dias`, bucket policy com as 5 statements (CloudTrail ACL check/write, Flow Logs ACL check/write, deny insecure transport).

### Terraform

- **Layout:** root module único em `terraform/environments/lab02/` (state próprio, mesma decisão do Lab 01 — ver ADR-008), com arquivos separados por responsabilidade: `cloudtrail.tf`, `flowlogs.tf`, `storage.tf` (bucket Athena), `data.tf` (data sources externos), `ssm.tf`, `outputs.tf`.
- **Backend:** mesmo bucket de state do Lab 01 (`awssec-tfstate-230650392331`), key própria `lab02/terraform.tfstate`.
- **Dependência do Lab 01:** o Flow Logs lê `/lab01/vpc_id` via `data "aws_ssm_parameter"` — **o Lab 01 precisa estar aplicado (`terraform apply`) antes do `terraform apply` do Lab 02**, senão o `plan` falha ao resolver esse data source.
- **Log bucket:** lido via `data "aws_s3_bucket"` (não `resource`) — o Terraform do Lab 02 nunca gerencia nem destrói esse bucket (ADR-009).
- **CloudTrail:** `aws_cloudtrail.main`, `advanced_event_selector` com dois blocos (management events + data events de S3 excluindo o log bucket via `not_starts_with`), entrega para `aws_cloudwatch_log_group.cloudtrail` (retenção 180 dias) via IAM role dedicada.
- **Root account usage:** `aws_cloudwatch_log_metric_filter` com o pattern padrão CIS + `aws_cloudwatch_metric_alarm` + `aws_sns_topic` (assinatura por e-mail via `var.alarm_notification_email`).
- **VPC Flow Logs:** dois recursos `aws_flow_log` (um para CloudWatch, um para S3 — um único recurso não suporta os dois destinos ao mesmo tempo), `traffic_type = "ALL"`.
- **Athena:** `aws_s3_bucket.athena_results`, ephemeral, `force_destroy = true` (ADR-014).
- **SSM:** outputs publicados em `/lab02/...` (nome do trail, nomes dos log groups, nome dos buckets, ARN do tópico SNS).
- `terraform fmt`, `terraform validate` e `terraform plan` limpos antes do apply — 22 recursos criados, 0 erros, 0 drift.

### AWS CLI (validação pós-apply)

Validado campo a campo em 2026-08-26, logo após o `apply`:

- `aws cloudtrail get-trail-status --name awssec-lab02-trail` → `IsLogging: True`.
- `aws cloudtrail describe-trails` → `IsMultiRegionTrail: true`, `LogFileValidationEnabled: true`, `S3BucketName: awssec-logs-230650392331`.
- `aws cloudtrail get-event-selectors` → dois `AdvancedEventSelectors`: management events (todos) e data events de S3 com `NotStartsWith` excluindo o próprio log bucket.
- `aws ec2 describe-flow-logs` → 2 flow logs `ACTIVE` na VPC do Lab 01, um `s3` e um `cloud-watch-logs`, ambos `TrafficType: ALL`.
- `aws logs describe-log-groups` → `retentionInDays: 180` nos dois log groups (`/aws/cloudtrail/awssec-lab02-trail`, `/aws/vpc-flow-logs/awssec-lab02`).
- `aws cloudwatch describe-alarms` → alarme `awssec-lab02-alarm-root-usage` criado, estado `INSUFFICIENT_DATA` (esperado — sem uso de root ainda), `AlarmActions` apontando para o tópico SNS correto.
- `aws sns list-subscriptions-by-topic` → assinatura por e-mail com `SubscriptionArn: PendingConfirmation` (aguardando clique no link de confirmação).
- `aws s3 ls s3://awssec-logs-230650392331/AWSLogs/230650392331/` → prefixos `CloudTrail/`, `CloudTrail-Digest/`, `vpcflowlogs/` já presentes, confirmando entrega real no bucket.

## Testes

- `terraform plan` limpo antes do apply (21→22 recursos após adicionar `alarm_notification_email`, 0 to change, 0 to destroy).
- `terraform apply`: 22 recursos criados, 0 erros.
- Todas as validações de campo da seção anterior (AWS CLI pós-apply) confirmaram o comportamento esperado, sem divergência entre o desenhado (ADRs 009–014) e o implantado.

## Falha ou ataque proposital

_(a definir — candidatos identificados no design: CloudTrail sem logs por bucket policy divergente do nome do trail; Flow Logs sem entrega por IAM role incorreta; ver seção Troubleshooting do agents.md)_

## Detecção e investigação

_(a definir — CloudTrail/Flow Logs estão de pé; exercício de detecção/investigação fica para quando houver um evento real ou simulado para caçar, possivelmente já integrando o Lab 03/GuardDuty)_

## Troubleshooting

_(a definir — nenhum problema encontrado até aqui; o apply e a validação passaram de primeira)_

## Remediação

_(a definir)_

## Evidências

_(a definir — capturar outputs de CLI e/ou screenshots do console: trail, flow logs, alarme, e-mail de confirmação SNS)_

## Custos e cleanup

**Restrição do projeto:** teto de **US$ 100 / 6 meses** (absoluto, não mensal) — ver [[project-budget-constraint]] / `docs/decisions.md`.

**Custo estimado deste lab:** bem abaixo de US$ 1/mês. CloudTrail management events são gratuitos no primeiro trail da conta; data events e ingestão de CloudWatch Logs cobram por volume, mas o volume de um lab de estudo é mínimo; S3 é centavos mesmo com Standard-IA.

**Decisão:** o Terraform do Lab 02 (CloudTrail, Flow Logs, log groups, bucket Athena, SNS) segue o mesmo ciclo de destroy/recreate por sessão do Lab 01. **O log bucket (`awssec-logs-230650392331`) nunca é destruído** — é bootstrap, fora de qualquer state de lab (ADR-009).

**Checklist de cleanup:**

```text
terraform destroy (environments/lab02/)
   ├── destrói: trail do CloudTrail, log groups do CloudWatch,
   │            metric filter, alarm, tópico SNS, flow logs,
   │            IAM roles de serviço, bucket S3 do Athena
   │            (force_destroy=true)
   └── NÃO destrói: log bucket awssec-logs-230650392331
                     (fora do state, ver docs/setup-log-bucket-bootstrap.md)
```

## Relação com SCS-C03

```text
SCS-C03
└── Domínio 1 — Detecção
    ├── Habilidade 1.1.1 — design de fontes de log (CloudTrail, Flow Logs)
    ├── Habilidade 1.1.2 — configuração de destinos de log (S3 + CloudWatch)
    └── Habilidade 1.2.1 — análise de eventos de segurança centralizados
```
