# =============================================================================
# Roteamento de findings — EventBridge -> SNS -> e-mail (ADR-018)
# =============================================================================
# Escopo do Lab 03: NOTIFICAR um humano (mesmo padrão do alarme de root usage do
# Lab 02). A automação de resposta (Lambda isola SG, tira snapshot, taggeia)
# é o Lab 09 — que vai se acoplar ao tópico SNS e à regra publicados no SSM.

resource "aws_sns_topic" "guardduty_findings" {
  name = "awssec-lab03-sns-guardduty-findings"

  tags = {
    Name = "awssec-lab03-sns-guardduty-findings"
  }
}

# Permite que o EventBridge publique no tópico.
data "aws_iam_policy_document" "guardduty_findings_topic" {
  statement {
    sid       = "AllowEventBridgePublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.guardduty_findings.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "guardduty_findings" {
  arn    = aws_sns_topic.guardduty_findings.arn
  policy = data.aws_iam_policy_document.guardduty_findings_topic.json
}

resource "aws_sns_topic_subscription" "guardduty_findings_email" {
  count     = var.finding_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.guardduty_findings.arn
  protocol  = "email"
  endpoint  = var.finding_notification_email
}

# Regra: todo finding do GuardDuty com severidade >= threshold (default 4 = MEDIUM+).
# Findings de sample (create-sample-findings) passam por aqui igual aos reais —
# de propósito, para testar o encanamento. A primeira ocorrência chega em ~5 min;
# reocorrências seguem finding_publishing_frequency (15 min, ver guardduty.tf).
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "awssec-lab03-eventbridge-guardduty-findings"
  description = "GuardDuty findings com severidade >= ${var.finding_severity_threshold} -> SNS -> e-mail"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", var.finding_severity_threshold] }]
    }
  })

  tags = {
    Name = "awssec-lab03-eventbridge-guardduty-findings"
  }
}

# Input transformer: e-mail legível em vez do JSON cru do finding.
resource "aws_cloudwatch_event_target" "guardduty_findings_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "sns-guardduty-findings"
  arn       = aws_sns_topic.guardduty_findings.arn

  input_transformer {
    input_paths = {
      id       = "$.detail.id"
      account  = "$.account"
      region   = "$.region"
      type     = "$.detail.type"
      severity = "$.detail.severity"
      title    = "$.detail.title"
      desc     = "$.detail.description"
      resource = "$.detail.resource.resourceType"
      time     = "$.time"
    }

    input_template = <<-EOT
      "GuardDuty finding (Lab 03)"
      ""
      "Titulo    : <title>"
      "Tipo      : <type>"
      "Severidade: <severity>"
      "Recurso   : <resource>"
      "Conta     : <account>   Regiao: <region>"
      "Quando    : <time>"
      "Finding ID: <id>"
      ""
      "Descricao : <desc>"
      ""
      "Console: https://console.aws.amazon.com/guardduty/home?region=<region>#/findings"
    EOT
  }
}
