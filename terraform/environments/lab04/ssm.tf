# Publica os outputs do Lab 04 no SSM Parameter Store (ADR-004 / ADR-027).
# O Lab 09 (Automated Incident Response) lê o tópico SNS, a regra do EventBridge
# do cano agregado e o custom action ARN daqui — MAIS a regra direta do Lab 03
# (/lab03/eventbridge_rule_name), que vira o gatilho latência-crítico.
locals {
  ssm_prefix = "/lab04"
}

resource "aws_ssm_parameter" "securityhub_hub_arn" {
  name  = "${local.ssm_prefix}/securityhub_hub_arn"
  type  = "String"
  value = aws_securityhub_account.main.arn
}

resource "aws_ssm_parameter" "config_recorder_name" {
  name  = "${local.ssm_prefix}/config_recorder_name"
  type  = "String"
  value = aws_config_configuration_recorder.main.name
}

resource "aws_ssm_parameter" "finding_aggregator_arn" {
  name  = "${local.ssm_prefix}/finding_aggregator_arn"
  type  = "String"
  value = aws_securityhub_finding_aggregator.main.id
}

resource "aws_ssm_parameter" "securityhub_sns_topic_arn" {
  name  = "${local.ssm_prefix}/securityhub_sns_topic_arn"
  type  = "String"
  value = aws_sns_topic.securityhub_findings.arn
}

resource "aws_ssm_parameter" "securityhub_eventbridge_rule_name" {
  name  = "${local.ssm_prefix}/securityhub_eventbridge_rule_name"
  type  = "String"
  value = aws_cloudwatch_event_rule.securityhub_findings.name
}

resource "aws_ssm_parameter" "custom_action_arn" {
  name  = "${local.ssm_prefix}/custom_action_arn"
  type  = "String"
  value = aws_securityhub_action_target.escalate.arn
}
