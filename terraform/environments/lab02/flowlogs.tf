resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc-flow-logs/awssec-lab02"
  retention_in_days = 180

  tags = {
    Name = "awssec-lab02-loggroup-vpc-flow-logs"
  }
}

data "aws_iam_policy_document" "flow_logs_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs_cloudwatch" {
  name               = "awssec-lab02-role-flowlogs-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume_role.json
}

data "aws_iam_policy_document" "flow_logs_cloudwatch_write" {
  statement {
    sid    = "WriteToLogGroup"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs_cloudwatch_write" {
  name   = "awssec-lab02-policy-flowlogs-cloudwatch-write"
  role   = aws_iam_role.flow_logs_cloudwatch.id
  policy = data.aws_iam_policy_document.flow_logs_cloudwatch_write.json
}

# Tráfego ALL (não só REJECT) + dual delivery — ver ADR-012. VPC lida via SSM
# (data.tf), não via terraform_remote_state do Lab 01.
resource "aws_flow_log" "vpc_to_cloudwatch" {
  vpc_id               = data.aws_ssm_parameter.lab01_vpc_id.value
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs_cloudwatch.arn

  tags = {
    Name = "awssec-lab02-flowlog-cloudwatch"
  }
}

resource "aws_flow_log" "vpc_to_s3" {
  vpc_id               = data.aws_ssm_parameter.lab01_vpc_id.value
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = data.aws_s3_bucket.log.arn

  tags = {
    Name = "awssec-lab02-flowlog-s3"
  }
}
