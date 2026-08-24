resource "aws_security_group" "ec2_app" {
  name        = "awssec-lab01-sg-ec2-app"
  description = "EC2 da camada de aplicacao - sem regra de entrada, acesso via SSM Session Manager"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Saida irrestrita (NAT/VPC endpoint para SSM, S3, atualizacoes de pacote)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "awssec-lab01-sg-ec2-app"
  }
}
