output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}

output "guardduty_findings_sns_topic_arn" {
  value = aws_sns_topic.guardduty_findings.arn
}

output "guardduty_findings_eventbridge_rule_name" {
  value = aws_cloudwatch_event_rule.guardduty_findings.name
}

output "s3_protection_status" {
  value = aws_guardduty_detector_feature.s3_data_events.status
}

output "ebs_malware_protection_status" {
  value = aws_guardduty_detector_feature.ebs_malware_protection.status
}
