# =============================================================================
# Roteamento agregado — Security Hub -> EventBridge -> SNS -> e-mail (ADR-027)
# =============================================================================
# Cano AGREGADO: o caminho de notificação a humano para TODAS as fontes
# (GuardDuty + Inspector + CSPM), agora que o Security Hub normaliza tudo em
# ASFF. A notificação a humano MIGRA do Lab 03 para cá — a regra direta do
# Lab 03 (var.direct_guardduty_notification_enabled = false) deixa de mandar
# e-mail e passa a ser só o gatilho de automação latência-crítica do Lab 09.

resource "aws_sns_topic" "securityhub_findings" {
  name = "awssec-lab04-sns-securityhub-findings"

  tags = {
    Name = "awssec-lab04-sns-securityhub-findings"
  }
}

# Só o EventBridge publica, e só a partir das duas regras deste lab.
data "aws_iam_policy_document" "securityhub_findings_topic" {
  statement {
    sid       = "AllowEventBridgePublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.securityhub_findings.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        aws_cloudwatch_event_rule.securityhub_findings.arn,
        aws_cloudwatch_event_rule.securityhub_custom_action.arn,
      ]
    }
  }
}

resource "aws_sns_topic_policy" "securityhub_findings" {
  arn    = aws_sns_topic.securityhub_findings.arn
  policy = data.aws_iam_policy_document.securityhub_findings_topic.json
}

resource "aws_sns_topic_subscription" "securityhub_findings_email" {
  count     = var.finding_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.securityhub_findings.arn
  protocol  = "email"
  endpoint  = var.finding_notification_email
}

# --- Cano 1: findings importados, filtrados ---------------------------------
# Severity.Label MEDIUM+ E Workflow.Status = NEW E RecordState = ACTIVE.
# O filtro Workflow.Status = NEW é o que fecha o laço com o TS-010: um finding
# movido para SUPPRESSED por automation rule não casa este pattern -> não gera
# e-mail (esperado, não bug — mesma lógica do TS-008 do Lab 03).
resource "aws_cloudwatch_event_rule" "securityhub_findings" {
  name        = "awssec-lab04-eventbridge-securityhub-findings"
  description = "Security Hub findings importados: Severity.Label em ${join("/", var.finding_severity_labels)}, Workflow.Status=NEW, RecordState=ACTIVE -> SNS"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = var.finding_severity_labels
        }
        Workflow = {
          Status = ["NEW"]
        }
        RecordState = ["ACTIVE"]
      }
    }
  })

  tags = {
    Name = "awssec-lab04-eventbridge-securityhub-findings"
  }
}

# Input transformer: e-mail legível em vez do JSON ASFF cru. Os findings vêm
# num array (detail.findings[]); o transformer lê o primeiro elemento.
resource "aws_cloudwatch_event_target" "securityhub_findings_sns" {
  rule      = aws_cloudwatch_event_rule.securityhub_findings.name
  target_id = "sns-securityhub-findings"
  arn       = aws_sns_topic.securityhub_findings.arn

  input_transformer {
    input_paths = {
      title      = "$.detail.findings[0].Title"
      type       = "$.detail.findings[0].Types[0]"
      severity   = "$.detail.findings[0].Severity.Label"
      product    = "$.detail.findings[0].ProductName"
      resource   = "$.detail.findings[0].Resources[0].Id"
      compliance = "$.detail.findings[0].Compliance.Status"
      workflow   = "$.detail.findings[0].Workflow.Status"
      account    = "$.detail.findings[0].AwsAccountId"
      region     = "$.detail.findings[0].Region"
      updated    = "$.detail.findings[0].UpdatedAt"
      id         = "$.detail.findings[0].Id"
    }

    input_template = <<-EOT
      "Security Hub finding (Lab 04) - cano agregado"
      ""
      "Titulo     : <title>"
      "Tipo       : <type>"
      "Severidade : <severity>"
      "Produto    : <product>"
      "Recurso    : <resource>"
      "Compliance : <compliance>"
      "Workflow   : <workflow>"
      "Conta      : <account>   Regiao: <region>"
      "Atualizado : <updated>"
      "Finding ID : <id>"
      ""
      "Console: https://console.aws.amazon.com/securityhub/home?region=<region>#/findings"
    EOT
  }
}

# --- Cano 2: custom action "Escalar" (triagem manual do console) -----------
resource "aws_securityhub_action_target" "escalate" {
  name        = "Escalar"
  identifier  = "Escalar"
  description = "Escalar o finding para triagem manual (dispara e-mail pelo mesmo topico)"

  depends_on = [aws_securityhub_account.main]
}

resource "aws_cloudwatch_event_rule" "securityhub_custom_action" {
  name        = "awssec-lab04-eventbridge-securityhub-escalate"
  description = "Security Hub custom action 'Escalar' -> SNS (triagem manual)"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Custom Action"]
    resources   = [aws_securityhub_action_target.escalate.arn]
  })

  tags = {
    Name = "awssec-lab04-eventbridge-securityhub-escalate"
  }
}

resource "aws_cloudwatch_event_target" "securityhub_custom_action_sns" {
  rule      = aws_cloudwatch_event_rule.securityhub_custom_action.name
  target_id = "sns-securityhub-escalate"
  arn       = aws_sns_topic.securityhub_findings.arn

  input_transformer {
    input_paths = {
      action   = "$.detail.actionName"
      title    = "$.detail.findings[0].Title"
      severity = "$.detail.findings[0].Severity.Label"
      product  = "$.detail.findings[0].ProductName"
      resource = "$.detail.findings[0].Resources[0].Id"
      workflow = "$.detail.findings[0].Workflow.Status"
      account  = "$.detail.findings[0].AwsAccountId"
      region   = "$.detail.findings[0].Region"
      id       = "$.detail.findings[0].Id"
    }

    input_template = <<-EOT
      "Security Hub - acao personalizada '<action>' (Lab 04)"
      ""
      "Titulo     : <title>"
      "Severidade : <severity>"
      "Produto    : <product>"
      "Recurso    : <resource>"
      "Workflow   : <workflow>"
      "Conta      : <account>   Regiao: <region>"
      "Finding ID : <id>"
      ""
      "Console: https://console.aws.amazon.com/securityhub/home?region=<region>#/findings"
    EOT
  }
}
