output "securityhub_hub_arn" {
  value = aws_securityhub_account.main.arn
}

output "fsbp_standard_arn" {
  value = aws_securityhub_standards_subscription.fsbp.standards_arn
}

output "finding_aggregator_arn" {
  value = aws_securityhub_finding_aggregator.main.id
}

output "config_recorder_name" {
  value = aws_config_configuration_recorder.main.name
}

output "config_delivery_bucket" {
  value = aws_config_delivery_channel.main.s3_bucket_name
}

output "inspector_resource_types" {
  value = aws_inspector2_enabler.ec2.resource_types
}

output "securityhub_findings_sns_topic_arn" {
  value = aws_sns_topic.securityhub_findings.arn
}

output "securityhub_findings_eventbridge_rule_name" {
  value = aws_cloudwatch_event_rule.securityhub_findings.name
}

output "custom_action_escalate_arn" {
  value = aws_securityhub_action_target.escalate.arn
}

output "specimen_vpc_id" {
  value = aws_vpc.specimen.id
}

output "specimen_security_group_id" {
  value = aws_security_group.specimen.id
}

output "specimen_s3_bucket" {
  value = aws_s3_bucket.specimen.bucket
}
