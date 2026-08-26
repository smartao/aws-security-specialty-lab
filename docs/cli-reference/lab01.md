# CLI Reference — Lab 01 (Secure AWS Foundation)

**Lab:** 01
**Relacionado:** `terraform/environments/lab01/`, [ADR-001 a ADR-007](../decisions.md)

> ⚠️ **Status: referência não executada.** Este documento **não** foi rodado nem validado campo a campo (diferente dos `setup-*.md`, que carregam esse selo). É uma tradução manual, feita em 2026-08-26, do que o Terraform do Lab 01 já gerencia — útil como material de estudo para o exame SCS-C03 (entender o equivalente em AWS CLI de cada recurso), mas **não é fonte da verdade**. Pode divergir do Terraform real a qualquer momento que `terraform/environments/lab01/*.tf` mudar, sem nenhum aviso automático (não há `plan`/`state` cobrindo este arquivo). Se for usar de verdade, confira contra os `.tf` atuais antes de rodar.

## Objetivo

Mostrar, comando a comando, como recriar via AWS CLI os recursos que o Terraform do Lab 01 cria hoje: VPC com 6 subnets (public/private/isolated × 2 AZs), NAT Gateway de uma AZ só, VPC Endpoint Gateway para S3, bucket de dados, security group sem ingress, role/instance profile de EC2 com acesso S3 escopado e a instância em si.

⚠️ **Custo:** o NAT Gateway cobra por hora **enquanto existir**, independente de tráfego (~US$ 32/mês se deixado ligado) — é exatamente por isso que o hábito do projeto é `terraform destroy` no fim de cada sessão (ver [[project_budget_constraint]]). Se for rodar isso manualmente por estudo, não esqueça de desmontar no final (`delete-nat-gateway`, `release-address`, etc. — na ordem inversa da criação).

## Variáveis usadas em todos os comandos

```bash
export AWS_PROFILE=sergei-upstart
export AWS_REGION=us-east-1
ACCOUNT_ID=230650392331
```

## 1. VPC

```bash
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=awssec-lab01-vpc},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]' \
  --query 'Vpc.VpcId' --output text)

# Exigido pelo agente SSM (resolução de ssm.<region>.amazonaws.com) e por
# qualquer VPC Interface Endpoint que labs futuros venham a adicionar.
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support '{"Value":true}'
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames '{"Value":true}'
```

## 2. Internet Gateway

```bash
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=awssec-lab01-igw},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
```

## 3. Subnets (6 — public/private/isolated × 2 AZs)

```bash
tag() { echo "ResourceType=subnet,Tags=[{Key=Name,Value=$1},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]"; }

SUBNET_PUBLIC_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications "$(tag awssec-lab01-subnet-public-a)" --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_PUBLIC_A" --map-public-ip-on-launch

SUBNET_PUBLIC_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --tag-specifications "$(tag awssec-lab01-subnet-public-b)" --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_PUBLIC_B" --map-public-ip-on-launch

SUBNET_PRIVATE_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.11.0/24 --availability-zone us-east-1a --tag-specifications "$(tag awssec-lab01-subnet-private-a)" --query 'Subnet.SubnetId' --output text)
SUBNET_PRIVATE_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.12.0/24 --availability-zone us-east-1b --tag-specifications "$(tag awssec-lab01-subnet-private-b)" --query 'Subnet.SubnetId' --output text)

SUBNET_ISOLATED_A=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.21.0/24 --availability-zone us-east-1a --tag-specifications "$(tag awssec-lab01-subnet-isolated-a)" --query 'Subnet.SubnetId' --output text)
SUBNET_ISOLATED_B=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.22.0/24 --availability-zone us-east-1b --tag-specifications "$(tag awssec-lab01-subnet-isolated-b)" --query 'Subnet.SubnetId' --output text)
```

`private_a`/`private_b`/`isolated_a`/`isolated_b` **não** levam `map-public-ip-on-launch` — só as `public_*` recebem IP público automático.

## 4. Elastic IP + NAT Gateway (uma AZ só)

```bash
EIP_ALLOC_ID=$(aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=awssec-lab01-eip-natgw-a},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]' \
  --query 'AllocationId' --output text)

NATGW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id "$SUBNET_PUBLIC_A" \
  --allocation-id "$EIP_ALLOC_ID" \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=awssec-lab01-natgw-a},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]' \
  --query 'NatGateway.NatGatewayId' --output text)

# o Terraform espera implicitamente via grafo de dependência; no CLI isso é explícito
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NATGW_ID"
```

## 5. Route tables + associações

```bash
RTB_PUBLIC=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=awssec-lab01-rtb-public},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]' --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RTB_PUBLIC" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"

RTB_PRIVATE=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=awssec-lab01-rtb-private},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]' --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$RTB_PRIVATE" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NATGW_ID"

# Sem nenhuma rota de saída — subnet isolada por desenho (ADR-001), reservada
# para dados em labs futuros (ex.: RDS).
RTB_ISOLATED=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=awssec-lab01-rtb-isolated},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]' --query 'RouteTable.RouteTableId' --output text)

aws ec2 associate-route-table --route-table-id "$RTB_PUBLIC"   --subnet-id "$SUBNET_PUBLIC_A"
aws ec2 associate-route-table --route-table-id "$RTB_PUBLIC"   --subnet-id "$SUBNET_PUBLIC_B"
aws ec2 associate-route-table --route-table-id "$RTB_PRIVATE"  --subnet-id "$SUBNET_PRIVATE_A"
aws ec2 associate-route-table --route-table-id "$RTB_PRIVATE"  --subnet-id "$SUBNET_PRIVATE_B"
aws ec2 associate-route-table --route-table-id "$RTB_ISOLATED" --subnet-id "$SUBNET_ISOLATED_A"
aws ec2 associate-route-table --route-table-id "$RTB_ISOLATED" --subnet-id "$SUBNET_ISOLATED_B"
```

## 6. Bucket S3 de dados

Criado **antes** do VPC Endpoint porque a policy do endpoint referencia o ARN deste bucket — ordem real de dependência, diferente da ordem dos arquivos `.tf` (`storage.tf` vem depois de `network.tf` no repo, mas o Terraform resolve isso pelo grafo, não pelo nome do arquivo).

```bash
BUCKET=awssec-lab01-s3-data-${ACCOUNT_ID}

aws s3api create-bucket --bucket "$BUCKET" --region "$AWS_REGION"

aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-bucket-tagging \
  --bucket "$BUCKET" \
  --tagging 'TagSet=[{Key=Name,Value=awssec-lab01-s3-data},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]'
```

## 7. VPC Endpoint Gateway — S3 (policy restrita ao bucket do lab)

```bash
cat > /tmp/vpce-s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowLabBucketOnly",
    "Effect": "Allow",
    "Principal": "*",
    "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::${BUCKET}",
      "arn:aws:s3:::${BUCKET}/*"
    ]
  }]
}
EOF

aws ec2 create-vpc-endpoint \
  --vpc-id "$VPC_ID" \
  --service-name "com.amazonaws.${AWS_REGION}.s3" \
  --vpc-endpoint-type Gateway \
  --route-table-ids "$RTB_PRIVATE" \
  --policy-document file:///tmp/vpce-s3-policy.json \
  --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=awssec-lab01-vpce-s3},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]'
```

Tráfego EC2 → S3 sai pelo endpoint, não pelo NAT nem pela internet pública (ADR-003).

## 8. Security Group — sem regra de entrada

```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name awssec-lab01-sg-ec2-app \
  --description "EC2 da camada de aplicacao - sem regra de entrada, acesso via SSM Session Manager" \
  --vpc-id "$VPC_ID" \
  --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=awssec-lab01-sg-ec2-app},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]' \
  --query 'GroupId' --output text)
```

Sem `authorize-security-group-ingress` (nenhuma regra de entrada — acesso é via SSM Session Manager, não SSH). O egress "tudo liberado para `0.0.0.0/0`" que o Terraform declara explicitamente já é o *default* de todo SG novo — nenhum comando adicional necessário para replicá-lo.

## 9. IAM role + instance profile do EC2

```bash
cat > /tmp/ec2-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name awssec-lab01-role-ec2-app \
  --assume-role-policy-document file:///tmp/ec2-trust-policy.json \
  --tags Key=Project,Value=aws-security-specialty-lab Key=Lab,Value=lab01 Key=Environment,Value=study Key=ManagedBy,Value=terraform

aws iam attach-role-policy \
  --role-name awssec-lab01-role-ec2-app \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

cat > /tmp/ec2-s3-scoped-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::${BUCKET}"
    },
    {
      "Sid": "ReadWriteObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::${BUCKET}/*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name awssec-lab01-role-ec2-app \
  --policy-name awssec-lab01-policy-ec2-s3-scoped \
  --policy-document file:///tmp/ec2-s3-scoped-policy.json

aws iam create-instance-profile --instance-profile-name awssec-lab01-profile-ec2-app
aws iam add-role-to-instance-profile \
  --instance-profile-name awssec-lab01-profile-ec2-app \
  --role-name awssec-lab01-role-ec2-app
```

> Mesmo gotcha do Lab 02: um instance profile recém-criado pode não estar propagado a tempo do `run-instances` do próximo passo (erro típico: `Invalid IAM Instance Profile`). Se acontecer, esperar alguns segundos e tentar de novo.

## 10. Instância EC2 (Ubuntu 24.04, subnet privada)

```bash
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" "Name=virtualization-type,Values=hvm" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --subnet-id "$SUBNET_PRIVATE_A" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name=awssec-lab01-profile-ec2-app \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=awssec-lab01-ec2-app-a},{Key=Project,Value=aws-security-specialty-lab},{Key=Lab,Value=lab01},{Key=Environment,Value=study},{Key=ManagedBy,Value=terraform}]' \
  --query 'Instances[0].InstanceId' --output text)
```

`data.aws_ami.ubuntu` no Terraform vira um `describe-images` filtrado + `sort_by` na CreationDate para pegar a AMI mais recente (o `--most-recent` do provider não tem um flag 1:1 no CLI puro).

## 11. Outputs → SSM Parameter Store

```bash
aws ssm put-parameter --name /lab01/vpc_id                --type String --overwrite --value "$VPC_ID"
aws ssm put-parameter --name /lab01/subnet_public_a_id    --type String --overwrite --value "$SUBNET_PUBLIC_A"
aws ssm put-parameter --name /lab01/subnet_public_b_id    --type String --overwrite --value "$SUBNET_PUBLIC_B"
aws ssm put-parameter --name /lab01/subnet_private_a_id   --type String --overwrite --value "$SUBNET_PRIVATE_A"
aws ssm put-parameter --name /lab01/subnet_private_b_id   --type String --overwrite --value "$SUBNET_PRIVATE_B"
aws ssm put-parameter --name /lab01/subnet_isolated_a_id  --type String --overwrite --value "$SUBNET_ISOLATED_A"
aws ssm put-parameter --name /lab01/subnet_isolated_b_id  --type String --overwrite --value "$SUBNET_ISOLATED_B"
aws ssm put-parameter --name /lab01/sg_ec2_app_id         --type String --overwrite --value "$SG_ID"
aws ssm put-parameter --name /lab01/s3_data_bucket_name   --type String --overwrite --value "$BUCKET"
```

## Notas para a prova (SCS-C03)

- **Ordem de dependência real ≠ ordem dos arquivos `.tf`.** O Terraform resolve pelo grafo de referências (`aws_s3_bucket.data.arn` usado na policy do endpoint), não pela ordem em que os arquivos aparecem no diretório — por isso o bucket S3 (passo 6) vem antes do VPC Endpoint (passo 7) aqui, mesmo `storage.tf` estando depois de `network.tf` no repo.
- **NAT Gateway não fica disponível instantaneamente** — o Terraform espera implicitamente antes de criar a rota que aponta pra ele; no CLI isso precisa de `aws ec2 wait nat-gateway-available` explícito, senão o `create-route` pode falhar.
- **Security Group novo já nasce com egress "tudo liberado"** — só regras de ingress e regras de egress restritivas exigem `authorize-security-group-*`/`revoke-security-group-*` explícitos.
- **`--most-recent` do data source `aws_ami`** não tem equivalente direto no CLI — a forma usual é `describe-images` com filtros + `sort_by(Images, &CreationDate)[-1]` no lado do `--query`.
