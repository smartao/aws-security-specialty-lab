# O Lab 04 não tem dependência cross-lab via Terraform: a ingestão de findings do
# GuardDuty (Lab 03) e do Inspector no Security Hub é por integração de serviço,
# não por data source. NÃO há nenhum "data aws_ssm_parameter" de /lab03 aqui, de
# propósito (ADR-029) — mesma independência que o Lab 03 tem do Lab 01/02.
data "aws_caller_identity" "current" {}

locals {
  # Log bucket persistente do bootstrap (ADR-009), fora de qualquer state.
  # Construído a partir do account ID, sem hardcode (ADR-024 / ADR-029).
  log_bucket_name = "awssec-logs-${data.aws_caller_identity.current.account_id}"
}

# Lido, nunca gerenciado — o "terraform destroy" do Lab 04 não o alcança.
# O statement de bucket policy para config.amazonaws.com é pré-requisito MANUAL
# (docs/setup/setup-log-bucket-bootstrap.md, seção 8 — ADR-024). Sem ele o
# aws_config_delivery_channel falha no apply com InsufficientDeliveryPolicyException.
data "aws_s3_bucket" "log" {
  bucket = local.log_bucket_name
}
