# Publica os outputs do Lab 01 no SSM Parameter Store (ADR-004) — labs
# downstream leem por aqui, não via terraform_remote_state.
#
# Prefixo NÃO pode começar com "awssec" (nem qualquer coisa iniciando com
# "aws" ou "ssm", case-insensitive) - nome reservado pela AWS para o SSM
# Parameter Store, rejeitado com AccessDeniedException (ver TS-003).
locals {
  ssm_prefix = "/lab01"
}

resource "aws_ssm_parameter" "vpc_id" {
  name  = "${local.ssm_prefix}/vpc_id"
  type  = "String"
  value = aws_vpc.main.id
}

resource "aws_ssm_parameter" "subnet_public_a_id" {
  name  = "${local.ssm_prefix}/subnet_public_a_id"
  type  = "String"
  value = aws_subnet.public_a.id
}

resource "aws_ssm_parameter" "subnet_public_b_id" {
  name  = "${local.ssm_prefix}/subnet_public_b_id"
  type  = "String"
  value = aws_subnet.public_b.id
}

resource "aws_ssm_parameter" "subnet_private_a_id" {
  name  = "${local.ssm_prefix}/subnet_private_a_id"
  type  = "String"
  value = aws_subnet.private_a.id
}

resource "aws_ssm_parameter" "subnet_private_b_id" {
  name  = "${local.ssm_prefix}/subnet_private_b_id"
  type  = "String"
  value = aws_subnet.private_b.id
}

resource "aws_ssm_parameter" "subnet_isolated_a_id" {
  name  = "${local.ssm_prefix}/subnet_isolated_a_id"
  type  = "String"
  value = aws_subnet.isolated_a.id
}

resource "aws_ssm_parameter" "subnet_isolated_b_id" {
  name  = "${local.ssm_prefix}/subnet_isolated_b_id"
  type  = "String"
  value = aws_subnet.isolated_b.id
}

resource "aws_ssm_parameter" "sg_ec2_app_id" {
  name  = "${local.ssm_prefix}/sg_ec2_app_id"
  type  = "String"
  value = aws_security_group.ec2_app.id
}

resource "aws_ssm_parameter" "s3_data_bucket_name" {
  name  = "${local.ssm_prefix}/s3_data_bucket_name"
  type  = "String"
  value = aws_s3_bucket.data.bucket
}
