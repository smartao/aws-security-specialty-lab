output "cloudtrail_arn" {
  value = aws_cloudtrail.main.arn
}

output "cloudtrail_log_group_name" {
  value = aws_cloudwatch_log_group.cloudtrail.name
}

output "vpc_flow_logs_log_group_name" {
  value = aws_cloudwatch_log_group.vpc_flow_logs.name
}

output "athena_results_bucket_name" {
  value = aws_s3_bucket.athena_results.bucket
}

output "security_alarms_sns_topic_arn" {
  value = aws_sns_topic.security_alarms.arn
}
