# Attack Scenario — public-s3

**Descrição:** Bucket S3 aberto a acesso anônimo por bucket policy `Principal: "*"` ou por
Block Public Access desligado.
**Status:** ✅ Exercitado no Lab 03 (2026-08-28) — Ataque 2.
**STRIDE:** Information disclosure
**Agente:** TA4 (operador / erro humano — credencial administrativa válida, misconfig sem intenção maliciosa)
**Ameaça:** `TM-04` — [`docs/threat-model.md`](../../docs/threat-model.md)
**Labs que exercitam:** 03 (detecção reativa) ✅ · 04 (postura contínua / Config) · 07 (Macie — "o que vazou") · 20 (Conformance Packs)

> **O que este arquivo é.** O roteiro **reutilizável** de execução deste ataque (visão do
> atacante, cruza labs). O registro datado de cada execução fica no
> [README do Lab 03](../../labs/01-detection/03-guardduty/README.md); a moldura de risco
> (preventivo / detecção / residual) fica no [`threat-model.md`](../../docs/threat-model.md);
> a resposta operacional fica em [`runbooks/`](../../runbooks/). Índice e template:
> [`../README.md`](../README.md).

## Objetivo do ataque simulado

Provar o ciclo detectar → investigar para uma **misconfig de S3**, e exercitar o roteamento
de findings **por severidade** (ADR-018): a mesma cadeia de comandos gera um finding HIGH
que notifica e um finding LOW que não.

## Vetor

Um principal com `AdministratorAccess` (TA4) abre um bucket para leitura anônima — por
engano ou para "resolver rápido" um acesso. Dois passos, dois findings:

| Passo | O que faz | Finding | Severidade |
|---|---|---|---|
| Desligar o Block Public Access | remove a trava estrutural | `Policy:S3/BucketBlockPublicAccessDisabled` | 2.0 **LOW** |
| Aplicar bucket policy anônima | `Principal: "*"` + `s3:GetObject` | `Policy:S3/BucketAnonymousAccessGranted` | **HIGH** |

## Pré-condições

- CloudTrail **multi-region** entregando management events (Lab 02) — é a fonte do finding.
- Detector do GuardDuty persistente `ENABLED` em `us-east-1` (Lab 03).
- Regra EventBridge `severity ≥ 4` → SNS → e-mail (Lab 03, ADR-018).

## Execução

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="awssec-attack-public-s3-${ACCOUNT_ID}"

aws s3api create-bucket --bucket "$BUCKET" --region us-east-1

# passo 1 — desliga o BPA  → Policy:S3/BucketBlockPublicAccessDisabled (LOW 2.0)
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false

# passo 2 — policy anônima  → Policy:S3/BucketAnonymousAccessGranted (HIGH)
aws s3api put-bucket-policy --bucket "$BUCKET" --policy '{
  "Version":"2012-10-17",
  "Statement":[{"Sid":"PublicRead","Effect":"Allow","Principal":"*",
    "Action":"s3:GetObject","Resource":"arn:aws:s3:::'"$BUCKET"'/*"}]}'
```

O finding HIGH vem do pipeline de **CloudTrail management events** (`PutBucketPolicy`) —
**não** da feature `S3_DATA_EVENTS` (ADR-020, atualização de 2026-08-28). O GuardDuty faz
*replay* do management event e avalia o acesso público resultante (`EffectivePermission: PUBLIC`).

## Detecção esperada

| Ação | Sinal | Pipeline / fonte | Lab | Exercitado |
|---|---|---|---|---|
| `put-bucket-policy` anônima | `Policy:S3/BucketAnonymousAccessGranted` **HIGH** | GuardDuty — CloudTrail mgmt events | [03](../../labs/01-detection/03-guardduty/README.md) | ✅ e-mail via input transformer |
| `put-public-access-block` off | `Policy:S3/BucketBlockPublicAccessDisabled` LOW 2.0 | idem | 03 | ✅ **sem e-mail** — `< 4` (ADR-018) → **TS-008** |
| `GetObject` anônimo subsequente | CloudTrail **S3 data events** (ADR-010) | CloudTrail → S3 / CloudWatch (Lab 02) | 02 | ❌ |
| exposição que *persiste* | Config Rule `s3-bucket-public-read-prohibited` | AWS Config (postura contínua) | 04 / 20 | ❌ |
| *o que* vazou | classificação de dados sensíveis | Macie | 07 | ❌ |
| acesso anômalo a objeto | `Discovery:S3/*`, `Exfiltration:S3/*` | GuardDuty S3 data events + baseline | 03 | ❌ baseline |

Distinção-chave (SCS-C03): "o time não foi alertado" pode ser **filtro de severidade no
roteamento** (TS-008 — finding existe, não arquivado) ou **suppression rule** (TS-007 —
finding existe, arquivado). Ver
[Lab 03 § Troubleshooting](../../labs/01-detection/03-guardduty/README.md#troubleshooting).

## Resposta

```bash
aws s3api delete-bucket-policy --bucket "$BUCKET"
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3 rb "s3://$BUCKET" --force   # se criado só para o exercício
```

Remediação automática (Config → SSM Automation, ou EventBridge → Lambda) é **Lab 04 / Lab 09**.
Procedimento manual em [`runbooks/remediation/`](../../runbooks/remediation/).

## Risco residual

- **Reativo, não preventivo** — o finding chega *depois* de o bucket já estar público. Sem `s3-bucket-public-read-prohibited` + remediação automática até **Lab 04 / Lab 20**.
- Sem **Macie** para dizer *o que* estava no bucket → **Lab 07**.
- Findings de *data events* (`Discovery:S3/*` / `Exfiltration:S3/*`) dependem de baseline e não foram exercitados.
- Sem **SCP/RCP** barrando `s3:PutBucketPolicy` com `Principal:"*"` a nível de organização → **Lab 19**.

## Referências

- Ameaça: **`TM-04`** — [`docs/threat-model.md`](../../docs/threat-model.md)
- ADRs: ADR-010 (data events de S3), ADR-017 (S3 Protection), ADR-018 (limiar `severity ≥ 4`), ADR-020 (ataque duplo + correção de premissa) — [`docs/decisions.md`](../../docs/decisions.md)
- Evidências: [`evidence/lab03/ts-008-*`](../../evidence/lab03/) — finding JSON, e-mail, contraste de severidade no console
- Troubleshooting: **TS-008** (filtro de severidade engolindo o finding LOW) — [`docs/troubleshooting.md`](../../docs/troubleshooting.md)
- Lab: [03 — GuardDuty](../../labs/01-detection/03-guardduty/README.md)
