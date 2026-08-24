# force_destroy = true: bucket de laboratório, recriado a cada sessão de
# estudo (ADR-007) - não deve travar o destroy por causa de objetos de teste.
resource "aws_s3_bucket" "data" {
  bucket        = "awssec-lab01-s3-data-230650392331"
  force_destroy = true

  tags = {
    Name = "awssec-lab01-s3-data"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
