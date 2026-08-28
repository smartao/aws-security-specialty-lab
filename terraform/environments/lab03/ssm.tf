# Publica os outputs do Lab 03 no SSM Parameter Store (ADR-004) — o Lab 09
# (Automated Incident Response) lê o detector, o tópico SNS e a regra do
# EventBridge por aqui para pendurar a automação de resposta; Labs 04 e 10
# leem o detector ID.
locals {
  ssm_prefix = "/lab03"
}

resource "aws_ssm_parameter" "detector_id" {
  name  = "${local.ssm_prefix}/detector_id"
  type  = "String"
  value = aws_guardduty_detector.main.id
}

resource "aws_ssm_parameter" "sns_topic_arn" {
  name  = "${local.ssm_prefix}/sns_topic_arn"
  type  = "String"
  value = aws_sns_topic.guardduty_findings.arn
}

resource "aws_ssm_parameter" "eventbridge_rule_name" {
  name  = "${local.ssm_prefix}/eventbridge_rule_name"
  type  = "String"
  value = aws_cloudwatch_event_rule.guardduty_findings.name
}
