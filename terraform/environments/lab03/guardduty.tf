# =============================================================================
# GuardDuty — detector + protection plans
# =============================================================================
# Detector persistente, fora do ciclo de destroy/recreate por sessão (ADR-015).
# O Lab 03 inteiro é persistente (ADR-016): nenhuma peça abaixo cobra por ficar
# ligada com a EC2 do Lab 01 parada, então o gatilho de custo do ADR-007 não se
# aplica. "terraform destroy" só na hora de encerrar os estudos.

resource "aws_guardduty_detector" "main" {
  enable = true

  # Primeira ocorrência de um finding vai para o EventBridge em ~5 min sempre.
  # Este parâmetro controla a latência das REOCORRÊNCIAS do mesmo finding.
  # Default da AWS = SIX_HOURS; num lab de estudo isso faz um re-teste na mesma
  # sessão parecer que "não gerou nada". FIFTEEN_MINUTES é o mínimo (ADR-018,
  # gancho do troubleshooting D no README).
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Name = "awssec-lab03-guardduty-detector"
  }
}

# --- S3 Protection (ADR-017) --------------------------------------------------
# Analisa S3 data events em busca de ameaça (Policy:S3/BucketAnonymousAccessGranted,
# Discovery:S3/AnomalousBehavior, Exfiltration:S3/*). Pipeline próprio — NÃO
# depende do advanced_event_selector de S3 configurado no CloudTrail do Lab 02.
# Custo: ~US$0,80 / milhão de eventos → centavos no volume de estudo.
resource "aws_guardduty_detector_feature" "s3_data_events" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

# --- Malware Protection for EC2 (ADR-017) ------------------------------------
# Agentless: em um finding suspeito de EC2, o GuardDuty tira um snapshot do EBS,
# replica na conta do serviço e escaneia. Custo: US$0 enquanto nenhum scan for
# acionado; ~US$0,05/GB escaneado quando for (~US$0,40 para um volume de 8 GB).
resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

# --- Planos que a AWS liga por DEFAULT num detector novo e que revertemos a
#     DISABLED de propósito (ADR-017, atualização de 2026-08-27) ----------------
# Descoberto na validação pós-apply: um detector novo NÃO nasce "só com a base" —
# a AWS habilita quase todos os protection plans. Sem EKS/RDS/Lambda no projeto
# ainda, o custo é US$0, mas a decisão é habilitar cada plano no lab que o estuda
# (não "tudo de uma vez"), e evitar cobrança silenciosa quando o Lab 09 (Lambda)
# e o Lab 18 (RDS) criarem esses recursos.
resource "aws_guardduty_detector_feature" "eks_audit_logs" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EKS_AUDIT_LOGS"
  status      = "DISABLED"
}

resource "aws_guardduty_detector_feature" "rds_login_events" {
  detector_id = aws_guardduty_detector.main.id
  name        = "RDS_LOGIN_EVENTS"
  status      = "DISABLED"
}

resource "aws_guardduty_detector_feature" "lambda_network_logs" {
  detector_id = aws_guardduty_detector.main.id
  name        = "LAMBDA_NETWORK_LOGS"
  status      = "DISABLED"
}

resource "aws_guardduty_detector_feature" "runtime_monitoring" {
  detector_id = aws_guardduty_detector.main.id
  name        = "RUNTIME_MONITORING"
  status      = "DISABLED" # -> habilitar no Lab 13 (Secure Compute)
}

# EKS_RUNTIME_MONITORING e AI_PROTECTION / AI_ANALYST já vêm DISABLED por default
# e não estão no escopo de nenhuma decisão ainda — não gerenciados aqui.
