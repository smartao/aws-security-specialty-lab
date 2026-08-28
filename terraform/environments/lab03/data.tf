# O Lab 03 não tem nenhuma dependência cross-lab: o GuardDuty tem pipeline de
# dados próprio para CloudTrail management events, VPC Flow Logs e DNS query logs
# — não consome os destinos de log configurados no Lab 02 (S3 / CloudWatch Logs).
# Não há nenhum "data aws_ssm_parameter" aqui de propósito. Só o exercício de
# ataque proposital (ver README) precisa da EC2 do Lab 01 no ar.
data "aws_caller_identity" "current" {}
