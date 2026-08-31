variable "aws_region" {
  description = "Região AWS onde o Lab 04 é implantado. O Security Hub CSPM é regional; a home region da finding aggregation (ADR-026) e todos os security checks ficam aqui. Mesma região da fundação (Lab 01) e do detector do GuardDuty (Lab 03)."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile AWS CLI (IAM Identity Center) usado pelo Terraform."
  type        = string
  default     = "sergei-upstart"
}

variable "finding_notification_email" {
  description = "E-mail para assinatura do tópico SNS agregado de findings do Security Hub (ADR-027). Vazio = sem assinatura automática. A confirmação do link é manual e, como o Lab 04 é persistente (ADR-023), só precisa ser feita uma vez (não recai no TS-005 do Lab 02). Definido em terraform.tfvars (gitignored), padrão dos Labs 02/03."
  type        = string
  default     = ""
}

variable "finding_severity_labels" {
  description = "Labels de severidade ASFF que disparam notificação por e-mail no cano agregado (ADR-027). O evento do Security Hub é ASFF: filtra-se por Severity.Label, não pelo severity float 0-10 do evento nativo do GuardDuty — esse continua no cano direto do Lab 03."
  type        = list(string)
  default     = ["MEDIUM", "HIGH", "CRITICAL"]
}

variable "config_recording_resource_types" {
  description = "Tipos de recurso que o AWS Config grava (ADR-024). Escopo RESTRITO de propósito — não 'todos os tipos suportados' — para conter o custo por configuration item. Se um control do FSBP aparecer como NO_DATA porque o tipo dele não está aqui, adicioná-lo é a correção (é exatamente o TS-009). Inclui os global resource types de IAM porque esta é a única região."
  type        = list(string)
  default = [
    "AWS::S3::Bucket",
    "AWS::S3::AccountPublicAccessBlock",
    "AWS::EC2::SecurityGroup",
    "AWS::EC2::Volume",
    "AWS::EC2::Instance",
    "AWS::EC2::VPC",
    "AWS::IAM::Role",
    "AWS::IAM::User",
    "AWS::IAM::Group",
    "AWS::IAM::Policy",
    "AWS::CloudTrail::Trail",
    "AWS::GuardDuty::Detector",
  ]
}

variable "fsbp_disabled_controls" {
  description = "Controls do FSBP a desabilitar, como mapa control_id => motivo (ADR-029). O FSBP entra INTEIRO no primeiro apply — ver o score cru + o ruído é instrutivo; depois cura-se esta disable-list como PASSO DO LAB e re-aplica. Ex.: { \"IAM.6\" = \"Sem hardware MFA no ambiente de estudo\", \"Config.1\" = \"Recorder de escopo restrito por design (ADR-024)\" }."
  type        = map(string)
  default     = {}
}
