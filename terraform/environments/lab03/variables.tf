variable "aws_region" {
  description = "Região AWS onde o Lab 03 é implantado. Precisa ser a mesma região onde a EC2 do Lab 01 roda — o GuardDuty é regional e um finding só aparece na região onde a atividade ocorreu (ver Fork 7 / TS de região errada)."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile AWS CLI (IAM Identity Center) usado pelo Terraform."
  type        = string
  default     = "sergei-upstart"
}

variable "finding_notification_email" {
  description = "E-mail para assinatura do tópico SNS de findings do GuardDuty (severidade MEDIUM+). Vazio = sem assinatura automática. A assinatura por e-mail exige confirmação manual no link enviado pela AWS após o apply — como o Lab 03 é persistente (ADR-016) e nunca sofre destroy/recreate, essa confirmação só precisa ser feita uma vez (não recai no TS-005 do Lab 02)."
  type        = string
  default     = ""
}

variable "finding_severity_threshold" {
  description = "Severidade mínima de finding do GuardDuty que dispara notificação por e-mail. GuardDuty: 1.0-3.9 LOW, 4.0-6.9 MEDIUM, 7.0-8.9 HIGH, 9.0-10 CRITICAL. Default 4 = MEDIUM+ (ADR-018)."
  type        = number
  default     = 4
}
