variable "aws_region" {
  description = "Região AWS onde o Lab 02 é implantado."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile AWS CLI (IAM Identity Center) usado pelo Terraform."
  type        = string
  default     = "sergei-upstart"
}

variable "alarm_notification_email" {
  description = "E-mail para assinatura do tópico SNS de alarmes de segurança (root account usage). Vazio = sem assinatura automática — a assinatura por e-mail exige confirmação manual no link enviado pela AWS após o apply."
  type        = string
  default     = ""
}
