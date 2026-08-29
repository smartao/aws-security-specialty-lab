# Attack Scenario — excessive-iam

**Descrição:** Política IAM com privilégio excessivo (`iam:*`, `iam:PassRole` amplo,
`sts:AssumeRole` sem escopo, ou `*:*`) usada para escalar privilégio.
**Status:** 🔒 Não iniciado — primeiro lab que o exercita: **15 / 16**.
**STRIDE:** Elevation of privilege
**Agente:** TA4 (operador / erro humano) · TA2 (portador de credencial roubada)
**Ameaça:** `TM-05` — [`docs/threat-model.md`](../../docs/threat-model.md)
**Labs que exercitam:** 15 · 16

> **O que este arquivo é.** O roteiro **reutilizável** de execução deste ataque (visão do
> atacante, cruza labs). O registro datado de cada execução fica no README do lab que rodou;
> a moldura de risco fica no [`threat-model.md`](../../docs/threat-model.md); a resposta em
> [`runbooks/`](../../runbooks/). Índice e template: [`../README.md`](../README.md).

## Objetivo do ataque simulado

Pendente — a definir quando o Lab 15 / 16 fechar.

## Vetor

Uma policy anexada a uma role ou usuário permite criar credencial nova, anexar policy mais
poderosa, ou assumir role de mais privilégio — caminho de `AttachRolePolicy` /
`PutRolePolicy` / `CreateAccessKey` / `CreateUser` até controle total da conta ou da
organização.

## Pré-condições

Pendente — a definir.

## Execução

Pendente — a definir quando o Lab 15 / 16 fechar.

## Detecção esperada

| Sinal | Pipeline / fonte | Lab | Exercitado |
|---|---|---|---|
| `CreateAccessKey`, `AttachRolePolicy`, `PutRolePolicy`, `CreateUser` | CloudTrail (Lab 02) | 02 | ❌ |
| `PrivilegeEscalation:IAMUser/*`, `Recon:IAMUser/*` | GuardDuty | 03 | ❌ |
| policy que concede acesso amplo demais | IAM Access Analyzer, Policy Simulator | 15 / 16 | ❌ |

## Resposta

Pendente — reverter a policy, revogar credenciais criadas, [`runbooks/remediation/`](../../runbooks/remediation/).

## Risco residual

IAM Access Analyzer, permission boundaries, session policies e análise de least privilege
são **Labs 15 / 16**. Sem alarme dedicado para mudança de IAM no CloudWatch hoje (só o de
uso de root existe).

## Referências

- Ameaça: **`TM-05`** — [`docs/threat-model.md`](../../docs/threat-model.md)
- Lab: a definir
