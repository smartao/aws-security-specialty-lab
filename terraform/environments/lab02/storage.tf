# Bucket de resultados do Athena (Lab 06) — ephemeral, dentro do state normal
# do Lab 02 (ADR-014), ao contrário do log bucket (persistente, fora do
# state). force_destroy = true: mesmo padrão do bucket de dados do Lab 01,
# não deve travar o destroy por causa de resultados de query antigos.
resource "aws_s3_bucket" "athena_results" {
  bucket        = "awssec-lab02-s3-athena-results-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "awssec-lab02-s3-athena-results"
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
