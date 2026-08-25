resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/awssec-lab02-trail"
  retention_in_days = 180

  tags = {
    Name = "awssec-lab02-loggroup-cloudtrail"
  }
}

data "aws_iam_policy_document" "cloudtrail_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name               = "awssec-lab02-role-cloudtrail-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role.json
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch_write" {
  statement {
    sid       = "WriteToLogGroup"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch_write" {
  name   = "awssec-lab02-policy-cloudtrail-cloudwatch-write"
  role   = aws_iam_role.cloudtrail_cloudwatch.id
  policy = data.aws_iam_policy_document.cloudtrail_cloudwatch_write.json
}

# Multi-region + data events de S3 (todos os buckets, exceto o próprio log
# bucket) + entrega dupla S3/CloudWatch — ver ADR-010. O nome do trail precisa
# bater exatamente com o esperado pela bucket policy do log bucket
# (docs/setup-log-bucket-bootstrap.md), já que o bucket não é gerenciado aqui.
resource "aws_cloudtrail" "main" {
  name           = "awssec-lab02-trail"
  s3_bucket_name = data.aws_s3_bucket.log.bucket

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  advanced_event_selector {
    name = "Management events (todos)"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "S3 data events, todos os buckets, exceto o log bucket"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }

    field_selector {
      field           = "resources.ARN"
      not_starts_with = ["${data.aws_s3_bucket.log.arn}/"]
    }
  }

  tags = {
    Name = "awssec-lab02-trail"
  }
}

# Metric filter + alarme de uso da conta root — escopo do Lab 02 desde já
# (ADR-010), não adiado para o Lab 03/GuardDuty.
resource "aws_cloudwatch_log_metric_filter" "root_account_usage" {
  name           = "awssec-lab02-metricfilter-root-usage"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.userIdentity.type = \"Root\") && ($.userIdentity.invokedBy NOT EXISTS) && ($.eventType != \"AwsServiceEvent\") }"

  metric_transformation {
    name          = "RootAccountUsageCount"
    namespace     = "awssec/lab02"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_sns_topic" "security_alarms" {
  name = "awssec-lab02-sns-security-alarms"

  tags = {
    Name = "awssec-lab02-sns-security-alarms"
  }
}

resource "aws_sns_topic_subscription" "security_alarms_email" {
  count     = var.alarm_notification_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.security_alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

resource "aws_cloudwatch_metric_alarm" "root_account_usage" {
  alarm_name          = "awssec-lab02-alarm-root-usage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = aws_cloudwatch_log_metric_filter.root_account_usage.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.root_account_usage.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "Disparado quando a conta root da AWS é usada diretamente (fora de eventos automáticos de serviço)."
  alarm_actions       = [aws_sns_topic.security_alarms.arn]

  tags = {
    Name = "awssec-lab02-alarm-root-usage"
  }
}
