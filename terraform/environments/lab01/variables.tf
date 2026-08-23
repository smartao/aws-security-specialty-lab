variable "aws_region" {
  description = "Região AWS onde o Lab 01 é implantado."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile AWS CLI (IAM Identity Center) usado pelo Terraform."
  type        = string
  default     = "sergei-upstart"
}
