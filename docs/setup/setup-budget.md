# Setup — AWS Budget (alerta de gasto mensal)

**Lab:** nenhum — infraestrutura de bootstrap, conta inteira (ver atualização de [ADR-007](decisions.md#adr-007--cleanup-por-sessão-de-estudo--aws-budget))
**Relacionado:** [ADR-007](decisions.md#adr-007--cleanup-por-sessão-de-estudo--aws-budget)
**Status:** ✅ Executado e validado via CLI campo a campo em 2026-08-25.

## Objetivo

Criar, via AWS CLI, um AWS Budget mensal que avisa por email quando o gasto da conta ultrapassa US$ 5 e US$ 10 no mês corrente. Motivação: em 2026-08-25 a conta (230650392331) foi automaticamente promovida de **Free Plan** para **Paid Plan** — gatilho identificado: ativar o IAM Identity Center como *organization instance* exige uma AWS Organization, e criar/entrar numa Organization é um dos gatilhos oficiais de upgrade automático da AWS. Sem o buffer do Free Tier, qualquer uso passa a ser cobrado desde o primeiro centavo, o que torna um alerta cedo mais útil do que o desenho original (teto absoluto de US$ 100/6 meses com alertas em 50/80/100%, que exigiria modelar `TimeUnit=ANNUALLY` com `TimePeriod` limitado para não resetar mensalmente).

## Por que AWS CLI e não Terraform

Mesmo raciocínio já aplicado ao bucket de backend e ao bucket de logs (ver [setup-backend-bootstrap.md](setup-backend-bootstrap.md), [setup-log-bucket-bootstrap.md](setup-log-bucket-bootstrap.md)): o Budget é um recurso de conta inteira, não pertence a nenhum lab, e não deve ser destruído/recriado junto com o ciclo de `terraform destroy` de nenhum ambiente.

## Nome

```text
awssec-monthly-budget
```

Não segue o padrão `{projeto}-{lab}-{tipo-recurso}-{detalhe}` da ADR-005 pelo mesmo motivo dos buckets de bootstrap — não pertence a um lab. Budget não exige unicidade global (só dentro da conta), então não carrega o sufixo do account ID.

## Pré-requisitos

- Sessão autenticada via IAM Identity Center (`aws sso login --profile sergei-upstart`).
- Permissão de administrador na conta (permission set `AdministratorAccess`).

## Passo a passo (CLI)

### 1. Definição do budget

`budget.json`:

```json
{
  "BudgetName": "awssec-monthly-budget",
  "BudgetLimit": {
    "Amount": "10",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
```

### 2. Notificações — US$ 5 e US$ 10, gasto real (ACTUAL), valor absoluto

`notifications.json`:

```json
[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 5,
      "ThresholdType": "ABSOLUTE_VALUE"
    },
    "Subscribers": [
      { "SubscriptionType": "EMAIL", "Address": "sergei.martao@gmail.com" }
    ]
  },
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 10,
      "ThresholdType": "ABSOLUTE_VALUE"
    },
    "Subscribers": [
      { "SubscriptionType": "EMAIL", "Address": "sergei.martao@gmail.com" }
    ]
  }
]
```

`ThresholdType: ABSOLUTE_VALUE` (não `PERCENTAGE`) porque os alertas são em dólares fixos (US$ 5 / US$ 10), não em porcentagem de um teto — mais simples de raciocinar quando o "teto" do budget (US$ 10) já coincide com o segundo alerta.

### 3. Criar

```bash
aws budgets create-budget \
  --account-id 230650392331 \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json \
  --profile sergei-upstart
```

## Validação (CLI)

```bash
aws budgets describe-budget \
  --account-id 230650392331 --budget-name awssec-monthly-budget \
  --profile sergei-upstart

aws budgets describe-notifications-for-budget \
  --account-id 230650392331 --budget-name awssec-monthly-budget \
  --profile sergei-upstart

aws budgets describe-subscribers-for-notification \
  --account-id 230650392331 --budget-name awssec-monthly-budget \
  --notification NotificationType=ACTUAL,ComparisonOperator=GREATER_THAN,Threshold=5,ThresholdType=ABSOLUTE_VALUE \
  --profile sergei-upstart

aws budgets describe-subscribers-for-notification \
  --account-id 230650392331 --budget-name awssec-monthly-budget \
  --notification NotificationType=ACTUAL,ComparisonOperator=GREATER_THAN,Threshold=10,ThresholdType=ABSOLUTE_VALUE \
  --profile sergei-upstart
```

**Confirmado em 2026-08-25:** `BudgetLimit` US$ 10 MONTHLY, `HealthStatus: HEALTHY`, duas notificações (`Threshold: 5.0` e `Threshold: 10.0`, ambas `ACTUAL`/`ABSOLUTE_VALUE`/`GREATER_THAN`), cada uma com o subscriber `EMAIL sergei.martao@gmail.com`.

## Regras de convivência com este recurso

- **Nunca** roda `terraform destroy` de nenhum lab esperando que alcance este budget — ele está fora do state de qualquer lab, mesma regra dos buckets de bootstrap.
- Se o teto mensal (US$ 10) precisar mudar, editar via `aws budgets update-budget` — não recriar o recurso.
- O alerta é sobre gasto **mensal**, não sobre o teto absoluto de US$ 100/6 meses do projeto (ver atualização da [ADR-007](decisions.md#adr-007--cleanup-por-sessão-de-estudo--aws-budget)). Acompanhar o total acumulado do projeto continua sendo manual (Cost Explorer / `aws ce get-cost-and-usage`).
