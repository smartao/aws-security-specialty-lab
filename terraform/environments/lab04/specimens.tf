# =============================================================================
# Recursos-espécime — alvo determinístico e persistente do CSPM (ADR-023)
# =============================================================================
# Deliberadamente mínimos: 1 bucket S3 + 1 security group num VPC pelado
# (10.4.0.0/28, sem subnets / IGW / NAT). São o alvo sempre-presente dos
# controls FSBP e do ataque proposital de deriva de postura (ADR-028). EC2.13
# avalia security groups independente de anexação, então um SG solto serve.
# Auto-contido: não depende do NAT Gateway nem do ciclo caro da fundação.
#
# RUÍDO DE BASELINE ESPERADO: alguns controls do FSBP nascem FAILED nos
# espécimes mesmo sem ataque (ex.: S3.5 quer bucket policy TLS-only, S3.14 quer
# versionamento, EC2.2 pega o default SG deste VPC, Config.1 vê o recorder de
# escopo restrito). É de propósito — "ver o score cru + o ruído é instrutivo"
# (ADR-029). A curadoria é o passo do lab via var.fsbp_disabled_controls; não
# se blinda o espécime para passar em tudo.

resource "aws_vpc" "specimen" {
  cidr_block = "10.4.0.0/28"

  tags = {
    Name = "awssec-lab04-vpc-specimen"
  }
}

# SG-espécime: SEM regras no baseline. O ataque (ADR-028, passo 1) adiciona
# ingress 0.0.0.0/0:22 -> EC2.13 FAILED. NÃO anexar a nenhuma ENI/instância.
resource "aws_security_group" "specimen" {
  name        = "awssec-lab04-sg-specimen"
  description = "Especime Lab 04 para avaliacao de postura (EC2.13). Nao anexar a nada."
  vpc_id      = aws_vpc.specimen.id

  tags = {
    Name = "awssec-lab04-sg-specimen"
  }
}

# Bucket-espécime: hygiene padrão dos Labs 01/02 no baseline (BPA on + SSE-S3).
# O ataque (ADR-028, passo 2) desliga o BPA e aplica policy com Principal:"*"
# -> S3.1 / S3.8 FAILED + finding GuardDuty Policy:S3/BucketAnonymousAccessGranted
# (pipeline de CloudTrail management events — mecânica do Lab 03), tudo agregado.
resource "aws_s3_bucket" "specimen" {
  bucket        = "awssec-lab04-s3-specimen-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "awssec-lab04-s3-specimen"
  }
}

resource "aws_s3_bucket_public_access_block" "specimen" {
  bucket = aws_s3_bucket.specimen.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "specimen" {
  bucket = aws_s3_bucket.specimen.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
