# TS-006 — Investigação: CloudTrail para de entregar no S3

## 1. Comando para verificar o trail

Ver o status do trail:

```bash
aws cloudtrail get-trail-status \
  --name awssec-lab02-trail \
  --region us-east-1
```

Saída:

```json
{
    "IsLogging": true,
    "LatestDeliveryError": "AccessDenied",
    "LatestDeliveryTime": "2026-08-27T06:32:50.527000-03:00",
    "StartLoggingTime": "2026-08-27T05:55:46.869000-03:00",
    "LatestCloudWatchLogsDeliveryTime": "2026-08-27T06:39:54.393000-03:00",
    "LatestDigestDeliveryTime": "2026-08-27T05:57:54.399000-03:00",
    "LatestDeliveryAttemptTime": "2026-08-27T09:39:19Z",
    "LatestNotificationAttemptTime": "",
    "LatestNotificationAttemptSucceeded": "",
    "LatestDeliveryAttemptSucceeded": "2026-08-27T09:32:50Z",
    "TimeLoggingStarted": "2026-08-27T08:55:46Z",
    "TimeLoggingStopped": ""
}
```

**Informação relevante:**

```json
"LatestDeliveryError": "AccessDenied",
```

## 2. Ver o bucket usado pelo trail

```bash
aws cloudtrail describe-trails \
  --trail-name-list awssec-lab02-trail \
  --region us-east-1
```

Saída:

```json
{
    "trailList": [
        {
            "Name": "awssec-lab02-trail",
            "S3BucketName": "awssec-logs-230650392331",
            "IncludeGlobalServiceEvents": true,
            "IsMultiRegionTrail": true,
            "HomeRegion": "us-east-1",
            "TrailARN": "arn:aws:cloudtrail:us-east-1:230650392331:trail/awssec-lab02-trail",
            "LogFileValidationEnabled": true,
            "CloudWatchLogsLogGroupArn": "arn:aws:logs:us-east-1:230650392331:log-group:/aws/cloudtrail/awssec-lab02-trail:*",
            "CloudWatchLogsRoleArn": "arn:aws:iam::230650392331:role/awssec-lab02-role-cloudtrail-cloudwatch",
            "HasCustomEventSelectors": true,
            "HasInsightSelectors": false,
            "IsOrganizationTrail": false
        }
    ]
}
```

**Informação relevante:**

```json
"S3BucketName": "awssec-logs-230650392331",
```

## 3. Verificar a policy do bucket

```bash
aws s3api get-bucket-policy \
  --bucket "awssec-logs-230650392331" \
  --query Policy \
  --output text | jq .
```

Saída:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::awssec-logs-230650392331",
      "Condition": {
        "StringEquals": {
          "aws:SourceArn": "arn:aws:cloudtrail:us-east-1:230650392331:trail/awssec-lab02-trail-old"
        }
      }
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::awssec-logs-230650392331/AWSLogs/230650392331/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control",
          "aws:SourceArn": "arn:aws:cloudtrail:us-east-1:230650392331:trail/awssec-lab02-trail-old"
        }
      }
    },
    {
      "Sid": "AWSFlowLogsAclCheck",
      "Effect": "Allow",
      "Principal": {
        "Service": "delivery.logs.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::awssec-logs-230650392331",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "230650392331"
        }
      }
    },
    {
      "Sid": "AWSFlowLogsWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "delivery.logs.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::awssec-logs-230650392331/AWSLogs/230650392331/*",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "230650392331",
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::awssec-logs-230650392331",
        "arn:aws:s3:::awssec-logs-230650392331/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

**Informação relevante:**

```json
"Action": "s3:GetBucketAcl",
"Resource": "arn:aws:s3:::awssec-logs-230650392331",
"Condition": {
  "StringEquals": {
    "aws:SourceArn": "arn:aws:cloudtrail:us-east-1:230650392331:trail/awssec-lab02-trail-old"
  }
}
```

## Origem do problema

ARN do trail está errado — a condição `aws:SourceArn` das statements `AWSCloudTrailAclCheck` e `AWSCloudTrailWrite` aponta para `arn:aws:cloudtrail:us-east-1:230650392331:trail/awssec-lab02-trail-old`, um trail que não existe. O trail real se chama `awssec-lab02-trail` (confirmado no passo 2, `TrailARN`). Como a condição nunca bate, a permissão nunca se aplica, e o CloudTrail recebe `AccessDenied` ao tentar gravar no bucket.
