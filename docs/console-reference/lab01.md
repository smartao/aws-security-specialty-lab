# Console Reference — Lab 01 (Secure AWS Foundation)

**Lab:** 01
**Relacionado:** `terraform/environments/lab01/`, [ADR-001 a ADR-007](../decisions.md), [cli-reference/lab01.md](../cli-reference/lab01.md), [labs/00-foundation/01-secure-aws-foundation/README.md](../../labs/00-foundation/01-secure-aws-foundation/README.md)

> ⚠️ **Status: referência não executada.** Este documento **não** foi clicado tela a tela nem validado campo a campo (diferente dos `setup-*.md`, que carregam esse selo). É a tradução manual, feita em 2026-08-31, do que o Terraform do Lab 01 já gerencia — versão "console web" do [cli-reference/lab01.md](../cli-reference/lab01.md), útil como material de estudo para o exame SCS-C03 (saber **onde no console** mora cada recurso e o que o exame cobra de cada tela), mas **não é fonte da verdade**. Pode divergir do Terraform real a qualquer momento que `terraform/environments/lab01/*.tf` mudar, sem nenhum aviso automático (não há `plan`/`state` cobrindo este arquivo). Se for reproduzir de verdade, confira contra os `.tf` atuais antes de clicar.

## Objetivo

Mostrar, tela a tela, como recriar pelo **AWS Management Console** os recursos que o Terraform do Lab 01 cria hoje: VPC com 6 subnets (public/private/isolated × 2 AZs), NAT Gateway de uma AZ só, VPC Endpoint Gateway para S3, bucket de dados, security group sem ingress, role/instance profile de EC2 com acesso S3 escopado e a instância em si. Nível "orientado a telas": nomeia o serviço, a tela e os campos que importam, assumindo familiaridade básica com o console — não é um runbook clique a clique.

⚠️ **Custo:** o NAT Gateway cobra por hora **enquanto existir**, independente de tráfego (~US$ 32/mês se deixado ligado) — é exatamente por isso que o hábito do projeto é `terraform destroy` no fim de cada sessão (ver [[project_budget_constraint]]). Se montar isso manualmente por estudo, siga a seção **Desmontar** no fim deste arquivo antes de fechar o console.

## Contexto — vale para todas as telas

| Item | Valor | Onde no console |
|---|---|---|
| Região | **N. Virginia — us-east-1** | seletor no canto superior direito. **Confira antes de criar cada recurso** — VPC, EC2 e endpoints são regionais; criar na região errada não dá erro, só cria no lugar errado. |
| Account ID | `230650392331` | canto superior direito → menu da conta |
| Tags em todo recurso | `Project=aws-security-specialty-lab`, `Lab=lab01`, `Environment=study`, `ManagedBy=terraform` | painel **Tags** de cada tela de criação |
| Tag `Name` | `awssec-lab01-<tipo>[-<az>]` (convenção ADR-005) | idem |

> `ManagedBy=terraform` acima é só para espelhar fielmente o que o Terraform aplica (via `default_tags` no provider). Se você criar esses recursos **de verdade** pelo console, fora do Terraform, o padrão do próprio projeto (ver `docs/setup/setup-log-bucket-bootstrap.md`) manda usar `ManagedBy=manual`. O console **não** tem "default tags" — cada tela precisa das 5 tags repetidas na mão (ou use **Tag Editor** / **Resource Groups** depois para aplicar em lote).

---

## 1. VPC

**Console:** VPC → **Your VPCs** → **Create VPC**

- **Resources to create:** escolha **VPC only**. **Não** use *VPC and more* — aquele wizard cria IGW, subnets, route tables e (opcionalmente) NAT + endpoint S3 de uma vez, com naming próprio (`project-vpc`, `project-subnet-public1-us-east-1a`…), o que quebra a convenção ADR-005 e some com o valor didático de montar peça por peça. (O wizard existe e é a resposta de exame para "forma mais rápida" — ver Notas.)
- **Name tag — auto-generation:** `awssec-lab01-vpc`
- **IPv4 CIDR:** *IPv4 CIDR manual input* → `10.0.0.0/16`
- **IPv6 CIDR:** *No IPv6 CIDR block*
- **Tenancy:** *Default*
- **Create VPC**

**Depois de criar:** selecione a VPC → **Actions → Edit VPC settings** → marque **Enable DNS resolution** *e* **Enable DNS hostnames** (os dois). Exigido pelo agente SSM (resolver `ssm.us-east-1.amazonaws.com`) e por qualquer VPC Interface Endpoint que labs futuros venham a adicionar. Corresponde a `enable_dns_support = true` + `enable_dns_hostnames = true` no `main.tf`.

---

## 2. Internet Gateway

**Console:** VPC → **Internet gateways** → **Create internet gateway**

- **Name tag:** `awssec-lab01-igw` → **Create internet gateway**
- Um IGW nasce **detached**. Selecione-o → **Actions → Attach to VPC** → escolha `awssec-lab01-vpc` → **Attach internet gateway**.

**Gotcha de exame:** *criar* ≠ *anexar*. Um IGW não-anexado não roteia nada, e uma VPC só pode ter um IGW anexado por vez.

---

## 3. Subnets (6 — public/private/isolated × 2 AZs)

**Console:** VPC → **Subnets** → **Create subnet**

- **VPC ID:** `awssec-lab01-vpc`
- A tela permite adicionar as 6 de uma vez (**Add new subnet** repetido). Para cada uma, preencha *Subnet name*, *Availability Zone* e *IPv4 subnet CIDR block*:

| Subnet name | AZ | CIDR |
|---|---|---|
| `awssec-lab01-subnet-public-a`   | us-east-1a | `10.0.1.0/24`  |
| `awssec-lab01-subnet-public-b`   | us-east-1b | `10.0.2.0/24`  |
| `awssec-lab01-subnet-private-a`  | us-east-1a | `10.0.11.0/24` |
| `awssec-lab01-subnet-private-b`  | us-east-1b | `10.0.12.0/24` |
| `awssec-lab01-subnet-isolated-a` | us-east-1a | `10.0.21.0/24` |
| `awssec-lab01-subnet-isolated-b` | us-east-1b | `10.0.22.0/24` |

- **Create subnet**

**Depois de criar — só nas duas `public-*`:** selecione a subnet → **Actions → Edit subnet settings** → marque **Enable auto-assign public IPv4 address**. As `private-*` e `isolated-*` ficam com essa opção **desmarcada** (corresponde a `map_public_ip_on_launch = true` só nas `public_*` do `network.tf`).

---

## 4. Elastic IP + NAT Gateway (uma AZ só)

**Elastic IP —** Console: VPC → **Elastic IPs** → **Allocate Elastic IP address**

- **Network border group:** `us-east-1`
- **Allocate**, depois selecione o EIP → **Actions → Add tags** → `Name = awssec-lab01-eip-natgw-a` + as 5 tags padrão.

**NAT Gateway —** Console: VPC → **NAT gateways** → **Create NAT gateway**

- **Name:** `awssec-lab01-natgw-a`
- **Subnet:** `awssec-lab01-subnet-public-a` — **tem que ser uma subnet pública** (a que tem rota para o IGW). NAT em subnet privada é erro clássico.
- **Connectivity type:** *Public*
- **Elastic IP allocation ID:** o `awssec-lab01-eip-natgw-a` alocado acima
- **Create NAT gateway**

Aguarde a coluna **State** virar **Available** (1–2 min) antes de criar a rota do passo 5. O console deixa você criar a rota apontando para um NAT em `Pending`, mas o tráfego só flui quando ele fica `Available` — no Terraform isso é o `depends_on = [aws_internet_gateway.main]` + grafo; no console é você olhando a coluna de status.

⚠️ **A partir daqui o NAT Gateway já está custando.** ~US$ 0,045/h só de existir.

---

## 5. Route tables + associações

**Console:** VPC → **Route tables** → **Create route table** (3×)

Toda route table nova já vem com a rota `local` para `10.0.0.0/16` — você **não** adiciona nem remove essa. Ela é o mínimo que garante comunicação intra-VPC.

### `awssec-lab01-rtb-public`
- Após criar: aba **Routes** → **Edit routes** → **Add route**: Destination `0.0.0.0/0`, Target **Internet Gateway** → `awssec-lab01-igw`.
- Aba **Subnet associations** → **Edit subnet associations** → marque `awssec-lab01-subnet-public-a` e `-public-b`.

### `awssec-lab01-rtb-private`
- **Edit routes** → **Add route**: Destination `0.0.0.0/0`, Target **NAT Gateway** → `awssec-lab01-natgw-a`.
- **Subnet associations** → `awssec-lab01-subnet-private-a` e `-private-b`.

### `awssec-lab01-rtb-isolated`
- **Nenhuma rota além da `local`.** É esse o desenho (ADR-001): sem caminho para a internet, nem via IGW nem via NAT — controle **estrutural** (rede), não uma policy que pode ser mal configurada.
- **Subnet associations** → `awssec-lab01-subnet-isolated-a` e `-isolated-b`.

**Gotcha de exame:** subnet sem associação explícita cai na **main route table** da VPC. Por isso as 6 são associadas na mão — não dá para confiar no default. Se a main route table tivesse uma rota para o IGW, uma subnet "esquecida" viraria pública sem ninguém perceber.

---

## 6. Bucket S3 de dados

**Console:** S3 → **Buckets** → **Create bucket**

- **Bucket name:** `awssec-lab01-s3-data-230650392331` — nome é global; o sufixo com o Account ID é o truque de unicidade.
- **AWS Region:** `us-east-1`
- **Object Ownership:** *ACLs disabled (recommended)*
- **Block Public Access:** deixe **as 4 caixas marcadas** (default). Corresponde ao `aws_s3_bucket_public_access_block` com os 4 `true` no `storage.tf`.
- **Bucket Versioning:** *Disable* — o Terraform não configura versioning neste bucket, então deixe desligado para bater com o `.tf`. (O exame empurra versioning como boa prática; aqui está desligado **de propósito** para espelhar o estado real.)
- **Default encryption:** *Server-side encryption with Amazon S3 managed keys (SSE-S3)* / `AES256`. **Não** SSE-KMS. É o default do console hoje; o `.tf` fixa `AES256` explicitamente.
- **Tags:** as 5 padrão.
- **Create bucket**

> `force_destroy = true` no `.tf` **não tem campo na tela de criação** — é só um comportamento de exclusão (esvaziar antes de deletar). No console, um bucket com objetos exige **Empty** antes do **Delete**.

---

## 7. VPC Endpoint Gateway — S3 (policy restrita ao bucket do lab)

**Console:** VPC → **Endpoints** → **Create endpoint**

- **Name tag:** `awssec-lab01-vpce-s3`
- **Type:** *AWS services*
- **Services:** busque `s3` → selecione `com.amazonaws.us-east-1.s3` com **Type = Gateway**. **Não** pegue o de **Type = Interface** (`...s3` Interface existe, custa por hora + por GB e usa ENI/DNS privado; o Gateway é gratuito e é o que o `.tf` usa).
- **VPC:** `awssec-lab01-vpc`
- **Route tables:** marque **somente** `awssec-lab01-rtb-private`.
- **Policy:** *Custom* → cole:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowLabBucketOnly",
      "Effect": "Allow",
      "Principal": "*",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::awssec-lab01-s3-data-230650392331",
        "arn:aws:s3:::awssec-lab01-s3-data-230650392331/*"
      ]
    }
  ]
}
```

- **Create endpoint**

Ao criar, o console adiciona automaticamente uma rota na `rtb-private` para a **managed prefix list** do S3 (`pl-xxxxxxxx`) apontando para o endpoint. Essa rota é **mais específica** que o `0.0.0.0/0 → NAT`, então tráfego EC2 → S3 sai pelo endpoint, não pelo NAT nem pela internet pública (ADR-003).

---

## 8. Security Group — sem regra de entrada

**Console:** VPC → **Security groups** → **Create security group** (ou EC2 → **Security Groups**)

- **Security group name:** `awssec-lab01-sg-ec2-app`
- **Description:** `EC2 da camada de aplicacao - sem regra de entrada, acesso via SSM Session Manager`
- **VPC:** `awssec-lab01-vpc`
- **Inbound rules:** **deixe vazio.** Sem SSH, sem nada. O acesso ao shell é via SSM Session Manager (passo 10).
- **Outbound rules:** o console já pré-preenche uma regra *All traffic → 0.0.0.0/0* — **mantenha**. Isso é idêntico ao bloco `egress` do `security.tf`, que só re-declara explicitamente o default de todo SG novo.
- **Tags:** as 5 padrão.
- **Create security group**

**Gotcha de exame:** SG novo = **zero inbound** + **allow-all outbound**. Só regras de entrada e regras de saída restritivas exigem configuração explícita. SG é *stateful* (resposta de conexão permitida volta sozinha); NACL é *stateless*.

---

## 9. IAM role + instance profile do EC2

**Console:** IAM → **Roles** → **Create role**

- **Trusted entity type:** *AWS service*
- **Use case:** *EC2* → **Next**
- **Permissions policies:** busque e marque **`AmazonSSMManagedInstanceCore`** (managed pela AWS) → **Next**
- **Role name:** `awssec-lab01-role-ec2-app` → **Create role**

**Policy inline escopada ao bucket:** abra a role → **Permissions** → **Add permissions → Create inline policy** → aba **JSON** → cole:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::awssec-lab01-s3-data-230650392331"
    },
    {
      "Sid": "ReadWriteObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::awssec-lab01-s3-data-230650392331/*"
    }
  ]
}
```

- **Policy name:** `awssec-lab01-policy-ec2-s3-scoped` → **Create policy**

> **Instance profile:** ao criar a role com use case *EC2*, o console cria **automaticamente** um instance profile **com o mesmo nome da role** (`awssec-lab01-role-ec2-app`). O Terraform (`aws_iam_instance_profile`) cria um explícito chamado `awssec-lab01-profile-ec2-app` — nome diferente. Na CLI isso é `create-instance-profile` + `add-role-to-instance-profile` na mão. Ou seja: **role e instance profile são objetos separados**; o console só esconde o segundo atrás do primeiro.

---

## 10. Instância EC2 (Ubuntu 24.04, subnet privada)

**Console:** EC2 → **Instances** → **Launch instances**

- **Name:** `awssec-lab01-ec2-app-a`
- **Application and OS Images:** busque `Ubuntu` → **Ubuntu Server 24.04 LTS**, arquitetura **64-bit (x86)**. O `most_recent = true` do `data.aws_ami.ubuntu` = "a mais nova sob esse padrão de nome"; o console já te mostra a atual (owner Canonical `099720109477`).
- **Instance type:** `t3.micro`
- **Key pair:** **Proceed without a key pair (Not recommended)** — de propósito. Sem SSH.
- **Network settings → Edit:**
  - **VPC:** `awssec-lab01-vpc`
  - **Subnet:** `awssec-lab01-subnet-private-a`
  - **Auto-assign public IP:** *Disable*
  - **Firewall (security groups):** *Select existing security group* → `awssec-lab01-sg-ec2-app`
- **Advanced details → IAM instance profile:** `awssec-lab01-role-ec2-app`
- **Launch instance**

> Mesmo gotcha da CLI: instance profile recém-criado pode não ter propagado a tempo (erro `Invalid IAM Instance Profile`). Se acontecer, espere alguns segundos e **Launch** de novo.

**Conectar (sem SSH):** EC2 → selecione a instância → **Connect** → aba **Session Manager** → **Connect**. Depende da instância ter se registrado no SSM (agente + `AmazonSSMManagedInstanceCore` + caminho de rede até os endpoints `ssm`/`ssmmessages`/`ec2messages` — aqui via egress do NAT). Se a aba **Session Manager** estiver cinza, a instância ainda não apareceu no **Fleet Manager** — aguarde ~2 min após o boot.

---

## 11. Outputs → SSM Parameter Store

**Console:** Systems Manager → **Parameter Store** → **Create parameter** (9×)

Para cada um: **Tier** *Standard*, **Type** *String*, **Value** = o ID copiado da tela correspondente.

| Name | Value (de onde vem) |
|---|---|
| `/lab01/vpc_id`               | VPC → Your VPCs |
| `/lab01/subnet_public_a_id`   | VPC → Subnets |
| `/lab01/subnet_public_b_id`   | VPC → Subnets |
| `/lab01/subnet_private_a_id`  | VPC → Subnets |
| `/lab01/subnet_private_b_id`  | VPC → Subnets |
| `/lab01/subnet_isolated_a_id` | VPC → Subnets |
| `/lab01/subnet_isolated_b_id` | VPC → Subnets |
| `/lab01/sg_ec2_app_id`        | VPC → Security groups |
| `/lab01/s3_data_bucket_name`  | S3 → Buckets (o nome, não ARN) |

**Gotcha de exame:** o nome do parâmetro **não pode começar** com `aws` nem `ssm` (case-insensitive) — reservado pela AWS, rejeitado com `AccessDeniedException`. É por isso que o prefixo é `/lab01` e não `/awssec/lab01` (ver TS-003 em `docs/troubleshooting.md`). Esses parâmetros são o contrato entre labs (ADR-004): o Lab 02+ lê daqui, não via `terraform_remote_state`.

---

## Desmontar (ordem inversa — o console barra dependências)

O console **não** deixa deletar um recurso com dependentes. Ordem que funciona:

1. **EC2** → *Terminate instance* (aguarde `terminated`).
2. **NAT Gateway** → *Delete* (aguarde `Deleted` — 1–2 min). **Para de custar aqui.**
3. **Elastic IP** → *Release Elastic IP address*.
4. **VPC Endpoint** (`vpce-s3`) → *Delete* (remove sozinho a rota da prefix list).
5. **Route tables** → apague as 3 (o console solta as associações; a *main* não é apagável).
6. **Subnets** → apague as 6.
7. **Internet Gateway** → *Detach from VPC*, depois *Delete*.
8. **Security group** `sg-ec2-app` → *Delete*.
9. **VPC** → *Delete VPC*.
10. **S3 bucket** → *Empty*, depois *Delete*.
11. **IAM** → *Delete role* `awssec-lab01-role-ec2-app` (o console apaga o instance profile homônimo junto).
12. **Parameter Store** → apague os 9 `/lab01/*`.

---

## Notas para a prova (SCS-C03)

- **Wizard "VPC and more" vs "VPC only".** O *VPC and more* provisiona IGW + subnets + route tables + (opcional) NAT Gateway(s) + VPC endpoint S3 numa tela só, com naming automático. É a resposta para "forma mais rápida de subir uma VPC completa". Aqui usamos *VPC only* para seguir a convenção de nomes e montar peça por peça.
- **IGW: criar ≠ anexar.** Um Internet Gateway detached não roteia nada. Uma VPC tem no máximo 1 IGW.
- **Auto-assign public IP é setting da subnet**, editável em *Edit subnet settings*, **independente** da route table. Subnet pode ter IP público automático ligado e mesmo assim não ter rota para o IGW (segue sem internet) — são dois controles separados. "Pública" de verdade = auto-assign **e** rota `0.0.0.0/0 → igw`.
- **Toda route table tem a rota `local`** para o CIDR da VPC, não-removível. "Subnet isolada" = route table que só tem essa.
- **Subnet sem associação explícita → main route table da VPC.** Sempre associe as 6 na mão.
- **Gateway Endpoint vs Interface Endpoint (S3):** Gateway = entrada de route table + managed prefix list, **grátis**, só S3 e DynamoDB, tráfego não sai da rede AWS. Interface = ENI na subnet, **cobra por hora + por GB**, DNS privado, funciona para quase todo serviço. O exame adora esse contraste.
- **A rota da prefix list do Gateway Endpoint é mais específica que `0.0.0.0/0 → NAT`**, então vence no longest-prefix-match — S3 vai pelo endpoint.
- **SG novo:** 0 inbound, allow-all outbound. SG é stateful; NACL é stateless e avaliada antes do SG no fluxo de entrada.
- **IAM console cria instance profile com o nome da role** (use case EC2). CLI/Terraform tratam role e instance profile como recursos distintos — daí o nome `-profile-` diferente do `-role-` no `.tf`.
- **EC2 sem key pair + SG sem inbound + `AmazonSSMManagedInstanceCore` = shell via Session Manager**, sem porta 22, sem bastion. É a resposta para "como acessar a instância sem abrir SSH".
- **S3:** SSE-S3 (`AES256`) é a criptografia default do bucket; SSE-KMS é opt-in. Block Public Access vem ligado por padrão no bucket **e** na conta.
- **Parameter Store:** nome não pode começar com `aws`/`ssm`. Tier Standard é grátis até 10k parâmetros; SecureString precisa de KMS (não usado aqui — são só IDs, não segredo).
