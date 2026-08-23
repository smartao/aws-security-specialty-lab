# Setup — IAM Identity Center (SSO)

**Lab:** 01 — Secure AWS Foundation
**Relacionado:** [ADR-006](decisions.md#adr-006--autenticação-humana-via-iam-identity-center-sso-não-iam-user)
**Status:** ⚠️ Reconstruído a partir do ADR-006 e do `~/.aws/config` local — passos 1, 2, 6, 7 e 8 seguem o fluxo padrão validado; ajustar o que não bater com o que você realmente clicou.

## Objetivo

Configurar autenticação humana (CLI/Terraform) via IAM Identity Center, gerando credenciais STS temporárias em vez de um IAM user com access key de longa duração — requisito de "zero credenciais estáticas" definido para o projeto.

## Pré-requisitos

- Conta AWS avulsa, sem AWS Organizations previamente configurada.
- Permissão de administrador na conta para habilitar o Identity Center.

## Passo a passo (console)

### 1. Habilitar o IAM Identity Center

Console → buscar **IAM Identity Center** → **Enable**. Na tela de escolha do tipo de instância, selecionar **Account instance** (não *Organization instance*) — evita a exigência de criar/entrar em uma AWS Organization, adequado para uma conta avulsa de estudo.

### 2. Confirmar o identity source

Em **Settings → Identity source**, manter o padrão **Identity Center directory** (diretório interno do próprio Identity Center, sem integração com AD/Entra/Okta).

### 3. Criar o grupo e o usuário

**Groups → Create group** → criar o grupo `Administrators`. Em seguida, **Users → Add user** → preencher username (`sergei`), e-mail e nome, e adicionar o usuário ao grupo `Administrators` no passo de associação a grupos do próprio wizard. O Identity Center envia um e-mail de convite para definir a senha e ativar a conta.

Atribuir acesso via grupo (em vez de direto ao usuário) é a prática recomendada — o permission set é atribuído ao grupo, e qualquer membro futuro do grupo herda o acesso automaticamente.

### 4. Selecionar o permission set

Em **Multi-account permissions** (ou **Application assignments**, dependendo da versão do console) → **Permission sets** → usar o permission set gerenciado pela AWS **AdministratorAccess** (predefinido, baseado na policy `AdministratorAccess`).

### 5. Atribuir o acesso à conta

Atribuir o grupo `Administrators` + o permission set `AdministratorAccess` à conta AWS atual. Isso cria a role `AWSReservedSSO_AdministratorAccess_<hash>` na conta, assumível via SSO por qualquer membro do grupo.

### 6. Anotar a AWS access portal URL

No painel do Identity Center (**Settings → Identity source → AWS access portal URL**), a URL gerada segue o padrão:

```
https://d-xxxxxxxxxx.awsapps.com/start/
```

Essa é a `sso_start_url` usada na configuração local do CLI.

## Passo a passo (CLI local)

### 7. Configurar o profile com `aws configure sso`

```bash
aws configure sso
```

Prompts respondidos:

| Prompt | Valor |
|---|---|
| SSO session name | `awssec-lab` |
| SSO start URL | `https://d-xxxxxxxxxx.awsapps.com/start/` |
| SSO region | `us-east-1` |
| SSO registration scopes | `sso:account:access` (padrão) |
| (login no navegador) | autoriza o device code |
| AWS account | `<ACCOUNT_ID>` (única conta disponível, instância tipo *Account*) |
| Role | `AdministratorAccess` |
| CLI default region | `us-east-1` |
| CLI default output format | `json` |
| Profile name | `sergei-upstart` |

Resultado gravado em `~/.aws/config`:

```ini
[profile sergei-upstart]
sso_session = awssec-lab
sso_account_id = <ACCOUNT_ID>
sso_role_name = AdministratorAccess
region = us-east-1
output = json

[sso-session awssec-lab]
sso_start_url = https://d-xxxxxxxxxx.awsapps.com/start/
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

### 8. Validar

```bash
aws sso login --profile sergei-upstart
aws sts get-caller-identity --profile sergei-upstart
```

Saída esperada (confirma STS `AssumeRole` via SSO, não credencial estática):

```json
{
    "UserId": "...:sergei",
    "Account": "<ACCOUNT_ID>",
    "Arn": "arn:aws:sts::<ACCOUNT_ID>:assumed-role/AWSReservedSSO_AdministratorAccess_<hash>/sergei"
}
```

O `assumed-role/...` no ARN é a prova: o mecanismo é `sts:AssumeRole` com token temporário, e o *session name* (`sergei`) preserva a identidade individual para auditoria futura via CloudTrail (a partir do Lab 02).

## Uso no dia a dia

- Início de cada sessão de estudo: `aws sso login --profile sergei-upstart`.
- O token fica cacheado localmente (`~/.aws/sso/cache/`) até expirar; expirado, `aws sso login` pede novo login no navegador.
- Terraform usa o mesmo profile via `AWS_PROFILE=sergei-upstart` ou `profile = "sergei-upstart"` no provider.
