output "vpc_id" {
  value = aws_vpc.main.id
}

output "ec2_instance_id" {
  value = aws_instance.app_a.id
}

output "s3_data_bucket_name" {
  value = aws_s3_bucket.data.bucket
}
