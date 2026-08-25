# Publica os outputs do Lab 02 no SSM Parameter Store (ADR-004) — labs
# downstream (06, 10, 12) leem por aqui, não via terraform_remote_state.
locals {
  ssm_prefix = "/lab02"
}

resource "aws_ssm_parameter" "cloudtrail_name" {
  name  = "${local.ssm_prefix}/cloudtrail_name"
  type  = "String"
  value = aws_cloudtrail.main.name
}

resource "aws_ssm_parameter" "cloudtrail_log_group_name" {
  name  = "${local.ssm_prefix}/cloudtrail_log_group_name"
  type  = "String"
  value = aws_cloudwatch_log_group.cloudtrail.name
}

resource "aws_ssm_parameter" "vpc_flow_logs_log_group_name" {
  name  = "${local.ssm_prefix}/vpc_flow_logs_log_group_name"
  type  = "String"
  value = aws_cloudwatch_log_group.vpc_flow_logs.name
}

resource "aws_ssm_parameter" "log_bucket_name" {
  name  = "${local.ssm_prefix}/log_bucket_name"
  type  = "String"
  value = data.aws_s3_bucket.log.bucket
}

resource "aws_ssm_parameter" "athena_results_bucket_name" {
  name  = "${local.ssm_prefix}/athena_results_bucket_name"
  type  = "String"
  value = aws_s3_bucket.athena_results.bucket
}

resource "aws_ssm_parameter" "security_alarms_sns_topic_arn" {
  name  = "${local.ssm_prefix}/security_alarms_sns_topic_arn"
  type  = "String"
  value = aws_sns_topic.security_alarms.arn
}
