resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  # Exigido pelo agente SSM (resolução de ssm.<region>.amazonaws.com) e por
  # qualquer VPC Interface Endpoint que labs futuros venham a adicionar.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "awssec-lab01-vpc"
  }
}
