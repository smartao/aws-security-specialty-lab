# Lab 01 — Secure AWS Foundation

**Status:** 📝 Planejamento concluído — implementação pendente

## SCS-C03
- Domínio/Fase: Fase 0 — Foundation
- Habilidades tocadas neste lab (fundação, não é lab de domínio pontuado diretamente):
  - **3.2.2** — Perfis de instância/serviço/execução (IAM Role + Instance Profile na EC2)
  - **3.3.1** — Controles de rede (Security Groups, NACL)
  - **3.3.4** — Segmentação de rede (subnet isolada, tráfego norte/sul)
  - **4.1.2** — Credenciais temporárias (STS via IAM Identity Center, zero access keys estáticas)
  - **5.1.2** — Acesso privado a recursos (VPC Gateway Endpoint para S3)
  - **6.2.1** — IaC consistente e seguro (Terraform: backend, naming, tags)

## Objetivo
Construir o ambiente de rede e identidade que serve de base para todos os demais laboratórios: uma VPC segmentada em 3 camadas, sem credenciais estáticas em nenhum ponto (nem para workloads, nem para o operador humano), e pronta para receber a camada de observabilidade no Lab 02.

## Cenário
Estamos montando uma pequena plataforma AWS corporativa segura. Antes de existir qualquer carga de trabalho, dado sensível ou controle de detecção, precisamos da fundação de rede e identidade — o "terreno" sobre o qual os próximos 19 labs e 2 capstones vão ser construídos.

**Limitação conhecida e aceita deste lab:** ao final do Lab 01, a conta ainda não tem rastreabilidade de API (CloudTrail) nem coleta de métricas/logs (CloudWatch) — isso é escopo formal do **Lab 02 — Centralized Logging Foundation**, não deste lab. É uma lacuna deliberada, não um esquecimento.

## Requisitos de segurança
- **3 camadas de subnet** (pública / privada / isolada) em 2 AZs — a camada isolada não tem rota para a internet, nem mesmo via NAT (reservada para dados, ex: RDS, em labs futuros).
- **Security Groups como controle primário de host**, escopados por camada.
- **Zero credenciais estáticas em qualquer ponto**:
  - EC2 → S3/RDS: via **IAM Role + Instance Profile** (nunca access key hardcoded).
  - Operador humano (eu) → AWS CLI/Terraform: via **IAM Identity Center (SSO)**, gerando credenciais STS temporárias (nunca um IAM user com access key de longa duração).
- **Acesso administrativo à EC2 sem porta exposta**: AWS Systems Manager Session Manager (agente já embutido na AMI Ubuntu oficial + policy `AmazonSSMManagedInstanceCore` no Role), sem SSH exposto à internet e sem bastion host.

## Arquitetura

```text
                         Internet
                            │
                       Internet Gateway
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
         AZ-a: Public                AZ-b: Public
        10.0.1.0/24                 10.0.2.0/24
         [NAT Gateway]
              │                           │
              └─────────────┬─────────────┘
                    (rota compartilhada)
              ┌─────────────┴─────────────┐
              ▼                           ▼
        AZ-a: Private                AZ-b: Private
       10.0.11.0/24                 10.0.12.0/24
         [EC2 + SSM]         ──VPC Gateway Endpoint──▶ S3
              │                           │
              └─────────────┬─────────────┘
              ▼                           ▼
        AZ-a: Isolated               AZ-b: Isolated
       10.0.21.0/24                 10.0.22.0/24
      (sem rota externa — reservada para dados futuros)
```

**Trade-off aceito e documentado:** um único NAT Gateway compartilhado (em AZ-a) em vez de um por AZ. Se AZ-a cair, as instâncias da AZ-b continuam operando entre si (SG, rotas internas, RDS futuro) — perdem apenas o *egress* para a internet. Decisão de custo consciente para um ambiente de laboratório, não uma perda real de HA da aplicação. Ver `docs/decisions.md`.

## CIDR e Subnets

VPC: `10.0.0.0/16` (dentro do bloco `10.0.0.0/8`, reservando os demais `/16` para VPCs de labs futuros que precisarem de rede própria, ex: Lab 14 e Lab 19 — sem risco de sobreposição).

| Subnet | CIDR | AZ | Rota externa |
|---|---|---|---|
| Public-A | 10.0.1.0/24 | a | Internet Gateway |
| Public-B | 10.0.2.0/24 | b | Internet Gateway |
| Private-A | 10.0.11.0/24 | a | NAT Gateway (AZ-a) |
| Private-B | 10.0.12.0/24 | b | NAT Gateway (AZ-a, compartilhado) |
| Isolated-A | 10.0.21.0/24 | a | nenhuma |
| Isolated-B | 10.0.22.0/24 | b | nenhuma |

Esquema de numeração (dezena por camada: 1-2 pública, 11-12 privada, 21-22 isolada) deixa espaço para uma futura AZ-C sem renumerar nada existente.

## Componentes

```
VPC (10.0.0.0/16)
├── Internet Gateway
├── 6 Subnets (public/private/isolated × AZ-a/AZ-b)
├── NAT Gateway (único, em Public-A) + Elastic IP
├── Route Tables (3, não 6 — pública, privada e isolada são compartilhadas entre as 2 AZs)
├── VPC Gateway Endpoint → S3 (gratuito, tráfego não sai da rede AWS nem passa pelo NAT)
├── Security Group (por camada, começando por sg-ec2-app)
├── IAM Role + Instance Profile (S3/RDS scoped + AmazonSSMManagedInstanceCore)
├── EC2 (Ubuntu, subnet privada, sem IP público)
└── S3 bucket (force_destroy = true, para não travar o destroy com objetos de teste)
```

## Naming convention

Padrão: `{projeto}-{lab}-{tipo-recurso}-{detalhe}[-{az}]`, com `awssec` como abreviação de `aws-security-specialty-lab`. Ambiente **não** entra no nome (tudo aqui é o mesmo ambiente de estudo) — vive só como tag.

| Recurso | Nome |
|---|---|
| VPC | `awssec-lab01-vpc` |
| Internet Gateway | `awssec-lab01-igw` |
| Subnets | `awssec-lab01-subnet-public-a/b`, `-private-a/b`, `-isolated-a/b` |
| NAT Gateway / EIP | `awssec-lab01-natgw-a` / `awssec-lab01-eip-natgw-a` |
| Route Tables | `awssec-lab01-rtb-public`, `-rtb-private`, `-rtb-isolated` |
| VPC Endpoint (S3) | `awssec-lab01-vpce-s3` |
| Security Group | `awssec-lab01-sg-ec2-app` |
| IAM Role / Profile | `awssec-lab01-role-ec2-app` / `awssec-lab01-profile-ec2-app` |
| EC2 | `awssec-lab01-ec2-app-a` |

**Tags padrão em todo recurso:**

| Tag | Valor |
|---|---|
| `Project` | `aws-security-specialty-lab` |
| `Lab` | `lab01` |
| `Environment` | `study` |
| `ManagedBy` | `terraform` |

## Serviços AWS envolvidos
- VPC (Public/Private/Isolated Subnets, Route Tables, IGW, NAT Gateway, VPC Gateway Endpoint)
- Security Groups / NACL
- EC2
- IAM (Roles, Instance Profiles)
- IAM Identity Center (SSO) — autenticação humana
- AWS Systems Manager (Session Manager) — acesso administrativo
- S3

## Implementação

### Terraform
- **Layout:** `terraform/modules/` (módulos reutilizáveis: vpc, iam-role-ec2, security-group...) compostos em `terraform/environments/lab01/` (root module com state próprio).
- **Backend:** S3 com locking nativo (`use_lockfile = true`, Terraform 1.10+), sem DynamoDB. O bucket do backend é criado uma única vez fora do ciclo de vida do lab (bootstrap) e nunca é destruído junto com o Lab 01.
- **Referência entre labs:** Lab 01 publica seus outputs (VPC ID, subnet IDs, etc.) no **SSM Parameter Store** (`/awssec/lab01/...`). Os demais labs leem por lá — não via `terraform_remote_state` — para não expor o state inteiro do Lab 01 a labs downstream (princípio de exposição mínima).
- Código Terraform em si: _(a definir na implementação)_

### AWS CLI
- Explorar via CLI antes de codar cada componente novo, pra entender a API antes de abstrair em Terraform.
- Validar via CLI após todo `apply` — e **interpretar a saída campo a campo** quando for JSON relevante (finding, evento, policy), não só confirmar que rodou.
- Todo troubleshooting proposital é feito só via CLI, sem Terraform.
- Autenticação humana via IAM Identity Center: `aws configure sso` (uma vez) + `aws sso login --profile <profile>` (a cada sessão de estudo) — validado e funcionando (ver `docs/decisions.md`).
- Comandos relevantes documentados em `awscli/` dentro da pasta do lab.

## Testes
_(a definir — após implementação)_

## Falha ou ataque proposital
_(a definir — candidato já identificado no planejamento: EC2 numa subnet isolada tentando se registrar no SSM sem VPC Interface Endpoints — falha de rede proposital para praticar troubleshooting)_

## Detecção e investigação
_(a definir — este lab ainda não tem CloudTrail/CloudWatch; capacidade de detecção começa no Lab 02)_

## Troubleshooting
_(a definir — após implementação)_

## Remediação
_(a definir — após implementação)_

## Evidências
_(a definir — após implementação)_

## Custos e cleanup

**Restrição do projeto:** teto de **US$ 100 / 6 meses** (não é mensal — é absoluto para todo o projeto).

**Componente de custo relevante neste lab:** NAT Gateway (~US$ 0,045/h de existência + processamento por GB), rodando 24/7 enquanto a VPC existir.

**Decisão:** destruir a fundação ao final de **toda** sessão de estudo (`terraform destroy`), e reaplicar no início da próxima. Viável sem dor porque os demais labs consomem os outputs via SSM Parameter Store (item acima) — ao recriar o Lab 01, os valores são republicados automaticamente.

**Rede de segurança recomendada:** configurar **AWS Budget** de US$ 100 com alertas em 50/80/100%.

**Checklist de cleanup:**
```
terraform destroy (environments/lab01/)
   ├── destrói: VPC, subnets, NAT+EIP, IGW, route tables,
   │            VPC endpoint S3, SG, IAM role/profile, EC2,
   │            bucket S3 (force_destroy=true)
   └── NÃO destrói: bucket S3 do backend/state (fora do
                     ciclo de vida do lab, é permanente)
```
Após todo `destroy`: conferir `aws ec2 describe-addresses` para garantir que nenhum Elastic IP ficou órfão (EIP não associado também cobra).

## Relação com SCS-C03

```
SCS-C03
├── Domínio 3 — Segurança de Infraestrutura
│   ├── Habilidade 3.2.2 — perfis de instância/serviço (IAM Role + Instance Profile)
│   ├── Habilidade 3.3.1 — controles de rede (SG, NACL)
│   └── Habilidade 3.3.4 — segmentação de rede (subnet isolada)
├── Domínio 4 — Gerenciamento de Identidade e Acesso
│   └── Habilidade 4.1.2 — credenciais temporárias (IAM Identity Center / STS)
├── Domínio 5 — Proteção de Dados
│   └── Habilidade 5.1.2 — acesso privado a recursos (VPC Gateway Endpoint)
└── Domínio 6 — Governança e Fundamentos de Segurança
    └── Habilidade 6.2.1 — IaC consistente e seguro
```
