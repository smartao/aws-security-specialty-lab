# =============================================================================
# Amazon Inspector — scan de EC2 apenas (ADR-025)
# =============================================================================
# Terceira forma de finding no lab: vulnerabilidade (CVE). Pega carona na EC2 da
# fundação (Lab 01), que já é managed instance no SSM desde o Lab 03. Custo
# ~US$0 sem EC2; ~US$0,002/instância/hora quando a fundação está no ar. Os
# findings de vulnerabilidade fluem automaticamente para o Security Hub
# (integração nativa, sem product_subscription).
#
# Só EC2. ECR / Lambda / o loop assess->harden->patch -> Lab 13. O enabler é
# declarativo para os resource_types listados; ECR e LAMBDA permanecem
# DISABLED (o Inspector nasce todo-desabilitado — sem o efeito "liga tudo por
# default" que o GuardDuty teve na ADR-017, mas a checagem vale como hábito).
resource "aws_inspector2_enabler" "ec2" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2"]
}
