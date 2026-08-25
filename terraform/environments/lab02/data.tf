data "aws_caller_identity" "current" {}

# O log bucket é persistente e criado fora do state deste lab (ADR-009,
# docs/setup-log-bucket-bootstrap.md) — lido aqui via data source, nunca
# gerenciado por este Terraform. Um "terraform destroy" do Lab 02 não o afeta.
data "aws_s3_bucket" "log" {
  bucket = "awssec-logs-230650392331"
}

# VPC do Lab 01, publicada via SSM Parameter Store (ADR-004) — não lida via
# terraform_remote_state. Requer que o Lab 01 esteja aplicado nesta sessão.
data "aws_ssm_parameter" "lab01_vpc_id" {
  name = "/lab01/vpc_id"
}
