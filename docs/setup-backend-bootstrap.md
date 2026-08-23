# Setup — Backend Terraform (bucket S3 para remote state)

**Lab:** 01 — mas a decisão vale para todo o projeto (bucket não pertence a nenhum lab específico)
**Relacionado:** [ADR-004](decisions.md#adr-004--terraform-backend-s3-com-lock-nativo--ssm-parameter-store-entre-labs)
**Status:** ✅ Executado e validado — bucket criado e todos os controles confirmados via CLI campo a campo (ver seção "Validação").

## Objetivo

Criar, uma única vez e via console (fora de qualquer ciclo de vida de lab), o bucket S3 que vai guardar o remote state de todo o projeto. Esse bucket precisa existir *antes* do primeiro `terraform init` do Lab 01, e por isso não é gerenciado pelo próprio Terraform — decisão da ADR-004, para evitar o problema de "o backend gerenciar a si mesmo".

## Pré-requisitos

- Sessão autenticada via IAM Identity Center (`aws sso login --profile sergei-upstart`) — ver [setup-identity-center.md](setup-identity-center.md).
- Permissão de administrador na conta (já garantida pelo permission set `AdministratorAccess`).

## Nota de nomenclatura

Esse bucket **não** segue o padrão `{projeto}-{lab}-{tipo-recurso}-{detalhe}` da ADR-005, porque ele não pertence a nenhum lab — é infraestrutura de bootstrap, criada antes do Lab 01 e reutilizada por todos os labs seguintes.

Nome de bucket S3 é único **globalmente** (entre todas as contas AWS do mundo, não só a sua). Padrão usado, para garantir unicidade sem depender de sorte — prefixo do projeto + ID da conta:

```text
awssec-tfstate-230650392331
```

## Passo a passo (console)

### 1. Nome e região

Console → **S3** → **Create bucket**.

| Campo | Valor |
|---|---|
| Bucket name | `awssec-tfstate-230650392331` |
| AWS Region | `us-east-1` (mesma região do Lab 01) |

### 2. Object Ownership

Manter o padrão **Bucket owner enforced** (ACLs desativadas). É o default em bucket novo desde 2023 — controle de acesso fica 100% em bucket policy / IAM, não em ACL.

### 3. Block Public Access

Manter os 4 checkboxes marcados (default). Nenhum motivo, neste projeto, para expor o state publicamente.

### 4. Bucket Versioning

**Ativar manualmente** — ⚠️ ao contrário de Object Ownership e Block Public Access, versionamento **não vem ligado por padrão** em bucket novo. É o que garante histórico/recuperação do `terraform.tfstate` em caso de apply problemático.

### 5. Default encryption

Confirmar **Server-side encryption with Amazon S3 managed keys (SSE-S3)** — também já vem marcado por padrão desde 2023, mas vale conferir em vez de assumir.

Bucket Key: manter habilitado (default, reduz custo de chamadas KMS — irrelevante aqui já que é SSE-S3, mas não atrapalha).

### 6. Tags

| Tag | Valor |
|---|---|
| `Project` | `aws-security-specialty-lab` |
| `Purpose` | `terraform-backend-bootstrap` |
| `ManagedBy` | `manual` |

⚠️ Note que `ManagedBy` aqui é `manual`, **não** `terraform` — diferente do padrão usado nos recursos dos labs (ver ADR-005). Esse bucket nunca vai estar dentro de um state Terraform, então marcar `ManagedBy = terraform` seria incorreto/enganoso.

### 7. Criar

**Create bucket**. Confirmar que o nome escolhido não colidiu (bucket name já em uso por outra conta é o erro mais comum aqui).

## Depois de criar: bucket policy TLS-only

Esse controle **não** vem por padrão e precisa ser adicionado manualmente. Console → bucket → **Permissions → Bucket policy → Edit**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::awssec-tfstate-230650392331",
        "arn:aws:s3:::awssec-tfstate-230650392331/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

## Validação (CLI)

Depois de criar, confirmar campo a campo (não só que os comandos rodaram):

```bash
aws s3api get-bucket-versioning --bucket awssec-tfstate-230650392331 --profile sergei-upstart
aws s3api get-bucket-encryption --bucket awssec-tfstate-230650392331 --profile sergei-upstart
aws s3api get-public-access-block --bucket awssec-tfstate-230650392331 --profile sergei-upstart
aws s3api get-bucket-policy --bucket awssec-tfstate-230650392331 --profile sergei-upstart
```

Esperado: `Status: Enabled` no versionamento, `SSEAlgorithm: AES256` na criptografia, os 4 campos de `PublicAccessBlockConfiguration` como `true`, e a policy TLS-only refletida no último comando.

**Confirmado em 2026-08-23:** todos os campos bateram com o esperado, incluindo `ObjectOwnership: BucketOwnerEnforced` e as tags (`Project`, `Purpose`, `ManagedBy=manual`). Nota: `get-bucket-location` retorna `LocationConstraint: null` para bucket em `us-east-1` — comportamento esperado da API, não é erro nem ausência de região.

## Referência futura — bloco backend no Terraform

Só para consulta ao montar `terraform/environments/lab01/` (implementação vem depois, neste passo é só documentação):

```hcl
terraform {
  backend "s3" {
    bucket       = "awssec-tfstate-230650392331"
    key          = "lab01/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

`use_lockfile = true` é o locking nativo via conditional writes (Terraform 1.10+, ver ADR-004) — não depende de nenhuma configuração adicional no bucket, é resolvido inteiramente pelo backend do Terraform.

## Regras de convivência com este bucket

- **Nunca** roda `terraform destroy` que alcance este bucket — ele está fora de qualquer state de lab, então isso só aconteceria por engano de configuração de backend.
- Cada lab usa uma `key` diferente dentro do mesmo bucket (`lab01/terraform.tfstate`, `lab02/terraform.tfstate`, ...) — um bucket, states isolados por prefixo.
- Criado uma vez, nunca recriado nem destruído junto com o Lab 01 (ADR-004).
