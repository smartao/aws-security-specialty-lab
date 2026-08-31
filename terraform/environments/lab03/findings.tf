# =============================================================================
# Roteamento de findings — cano DIRETO GuardDuty -> EventBridge (ADR-018 / ADR-027)
# =============================================================================
# A partir da ADR-027, a NOTIFICAÇÃO A HUMANO migra para o Lab 04 (Security Hub
# agrega GuardDuty + Inspector + CSPM num só e-mail). Este cano fica com uma
# função só: ser o gatilho de automação LATÊNCIA-CRÍTICA do Lab 09 (alvo =
# Lambda de contenção), porque rotear pelo Security Hub adiciona ~minutos de
# ingestão — inaceitável para "isolar o SG em segundos".
#
# `var.direct_guardduty_notification_enabled` (default false) controla o alvo de
# e-mail: com `false`, a regra EventBridge e o tópico SNS continuam de pé e
# publicados no SSM (o Lab 09 pendura a automação aqui), mas SEM alvo SNS e SEM
# assinatura de e-mail. Voltar a `true` restaura o comportamento do Lab 03
# original (ADR-018).

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

# Assinatura de e-mail só existe quando o cano direto notifica humano (ADR-027)
# E um e-mail foi informado. Com o default (`direct_guardduty_notification_enabled
# = false`), esta assinatura não é criada — a notificação a humano é do Lab 04.
resource "aws_sns_topic_subscription" "guardduty_findings_email" {
  count     = var.direct_guardduty_notification_enabled && var.finding_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.guardduty_findings.arn
  protocol  = "email"
  endpoint  = var.finding_notification_email
}

# Regra: todo finding do GuardDuty com severidade >= threshold (default 4 = MEDIUM+).
# Findings de sample (create-sample-findings) passam por aqui igual aos reais —
# de propósito, para testar o encanamento. A primeira ocorrência chega em ~5 min;
# reocorrências seguem finding_publishing_frequency (15 min, ver guardduty.tf).
# A regra existe SEMPRE (o Lab 09 se acopla a ela); o alvo é que é condicional.
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "awssec-lab03-eventbridge-guardduty-findings"
  description = "GuardDuty findings com severidade >= ${var.finding_severity_threshold} (cano direto). Alvo de e-mail só com direct_guardduty_notification_enabled = true; senão a regra fica para o Lab 09 (automacao)."

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

# Alvo SNS + input transformer (e-mail legível). Condicional (ADR-027): só
# existe quando `direct_guardduty_notification_enabled = true`. Com o default,
# a regra acima fica sem alvo — pronta para o Lab 09 anexar o Lambda de contenção.
resource "aws_cloudwatch_event_target" "guardduty_findings_sns" {
  count     = var.direct_guardduty_notification_enabled ? 1 : 0
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
