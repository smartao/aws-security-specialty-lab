# =============================================================================
# AWS Security Hub CSPM (clássico — ASFF, APIs v1) — ADR-022 / ADR-029
# =============================================================================
# NÃO é o Hub unificado novo (GA 2-dez-2025, OCSF, APIs v2): esse não tem
# suporte estável no provider AWS (issue hashicorp/terraform-provider-aws#46352)
# e a mecânica dele (OCSF / exposure findings) é mais nova que o guia do
# SCS-C03 v1.0. O Hub novo é seção conceitual no README + toggle CLI opcional;
# implementação real (central configuration multi-conta) -> Lab 19.

locals {
  fsbp_standard_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_securityhub_account" "main" {
  # Consolidated control findings: um finding por control, não um por
  # (control x standard). ADR-029.
  control_finding_generator = "SECURITY_CONTROL"

  # Controls recém-lançados em standards habilitados entram automaticamente.
  auto_enable_controls = true

  # NÃO habilita FSBP + CIS por default — só o que declaramos abaixo (só FSBP;
  # CIS fica para comparação posterior, ADR-029).
  enable_default_standards = false
}

# Único standard do Lab 04: AWS Foundational Security Best Practices, INTEIRO.
# Ver o score cru + o ruído é instrutivo (ADR-029); a curadoria vem depois, via
# var.fsbp_disabled_controls.
#
# timeouts.create = 30m: a habilitação INICIAL do FSBP provisiona centenas de
# controls + as Config managed rules que os lastreiam; o default do provider
# (3 min) estoura antes de a subscription sair de PENDING para READY/INCOMPLETE.
# Não é erro de config — só lentidão de primeira habilitação.
resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = local.fsbp_standard_arn

  timeouts {
    create = "30m"
  }

  depends_on = [aws_securityhub_account.main]
}

# Finding aggregation: define home region + linking mode. Custo zero (só se paga
# checks nas regiões onde o Hub está habilitado, e só habilitamos us-east-1),
# mas muda comportamento de fato — é o que se configura no dia 1 de um
# deployment real (ADR-026). Multi-account / central configuration -> Lab 19.
resource "aws_securityhub_finding_aggregator" "main" {
  linking_mode = "ALL_REGIONS"

  depends_on = [aws_securityhub_account.main]
}

# Disable-list curada como PASSO DO LAB (ADR-029): mapa vazio por padrão, então
# o primeiro apply deixa o FSBP inteiro ligado. Preencher
# var.fsbp_disabled_controls e re-aplicar É o exercício de curadoria de postura.
resource "aws_securityhub_standards_control_association" "fsbp_disabled" {
  for_each = var.fsbp_disabled_controls

  standards_arn       = local.fsbp_standard_arn
  security_control_id = each.key
  association_status  = "DISABLED"
  updated_reason      = each.value

  depends_on = [aws_securityhub_standards_subscription.fsbp]
}
