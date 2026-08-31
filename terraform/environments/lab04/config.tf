# =============================================================================
# AWS Config — recorder + delivery channel mínimos (ADR-024)
# =============================================================================
# Os security standards do Security Hub CSPM são quase inertes sem um Config
# recorder rodando: a maioria dos controls FSBP é lastreada por Config managed
# rules que o Security Hub provisiona sozinho, mas que só avaliam se o Config
# estiver gravando aquele tipo de recurso.
#
# Fronteira (ADR-024): Lab 04 = recorder + delivery channel + status. Rules
# próprias, conformance packs, remediação SSM e aggregators = Lab 20.
#
# PRÉ-REQUISITO MANUAL: a bucket policy do log bucket precisa ganhar o statement
# para config.amazonaws.com ANTES do primeiro apply (senão o delivery channel
# falha com InsufficientDeliveryPolicyException). Ver
# docs/setup/setup-log-bucket-bootstrap.md, seção 8 (bucket é bootstrap, fora
# do state).

data "aws_iam_policy_document" "config_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  name               = "awssec-lab04-role-config"
  assume_role_policy = data.aws_iam_policy_document.config_assume_role.json
}

# Permissões de leitura/descrição sobre os recursos gravados (managed pela AWS).
resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Permissão de entrega no log bucket persistente — escopada ao prefixo do Config
# e à conta, com a ACL bucket-owner-full-control exigida.
data "aws_iam_policy_document" "config_s3_delivery" {
  statement {
    sid       = "ConfigWriteToLogBucket"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${data.aws_s3_bucket.log.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid       = "ConfigReadBucketAcl"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [data.aws_s3_bucket.log.arn]
  }
}

resource "aws_iam_role_policy" "config_s3_delivery" {
  name   = "awssec-lab04-policy-config-s3-delivery"
  role   = aws_iam_role.config.id
  policy = data.aws_iam_policy_document.config_s3_delivery.json
}

# Recorder: gravação CONTÍNUA (o default; ADR-024 — a alavanca de custo real é
# escopo + persistência + só FSBP, não contínuo-vs-diário) e escopo RESTRITO de
# tipos (var.config_recording_resource_types). Os global resource types de IAM
# entram pela lista explícita — não via include_global_resource_types, que pareia
# com all_supported = true. Nome "default": só há um recorder por região/conta,
# e console e integrações assumem esse nome (alinha com o que aparece no exame).
resource "aws_config_configuration_recorder" "main" {
  name     = "default"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported  = false
    resource_types = var.config_recording_resource_types
  }

  depends_on = [
    aws_iam_role_policy.config_s3_delivery,
    aws_iam_role_policy_attachment.config_managed,
  ]
}

resource "aws_config_delivery_channel" "main" {
  name           = "default"
  s3_bucket_name = data.aws_s3_bucket.log.bucket

  # Sem SNS: o caminho de notificação é Security Hub -> EventBridge (ADR-027),
  # não o stream de mudanças do Config.

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}
