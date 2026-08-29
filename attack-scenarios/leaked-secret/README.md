# Attack Scenario — leaked-secret

**Descrição:** Vazamento e reuso da credencial / sessão do **operador humano** — device
roubado, phishing do fluxo `aws sso login`, cache `~/.aws/sso` copiado, ou token em código.
**Status:** 🔒 Não iniciado — primeiro lab que o exercita: **15 / 16** (least privilege da identidade humana) ou **09** (resposta).
**STRIDE:** Spoofing · Elevation of privilege
**Agente:** TA2 (portador de credencial roubada)
**Ameaça:** `TM-01` (relaciona `TM-02`) — [`docs/threat-model.md`](../../docs/threat-model.md)
**Labs que exercitam:** 15 · 16 · 09 _(a confirmar)_

> **O que este arquivo é.** O roteiro **reutilizável** de execução deste ataque (visão do
> atacante, cruza labs). O registro datado de cada execução fica no README do lab que rodou;
> a moldura de risco fica no [`threat-model.md`](../../docs/threat-model.md); a resposta em
> [`runbooks/`](../../runbooks/). Índice e template: [`../README.md`](../README.md).

## Objetivo do ataque simulado

Pendente — a definir quando o Lab 15 / 16 fechar.

## Vetor

Sessão SSO ou token STS do operador obtido e reutilizado de outro host. Difere de
[`compromised-ec2`](../compromised-ec2/README.md) (credencial **da role da EC2**, fase 2) e
de [`excessive-iam`](../excessive-iam/README.md) (a credencial já é legítima — o problema é
o excesso de permissão dela).

## Pré-condições

Pendente — a definir.

## Execução

Pendente — a definir quando o Lab 15 / 16 fechar.

## Detecção esperada

| Sinal | Pipeline / fonte | Lab | Exercitado |
|---|---|---|---|
| `UnauthorizedAccess:IAMUser/*`, `Recon:IAMUser/*` | GuardDuty | 03 | ❌ |
| chamada da sessão de IP / ASN novo | CloudTrail (Lab 02) | 02 | ❌ |
| escalonamento para root | alarme `userIdentity.type = Root` (Lab 02) | 02 | ✅ (controle pronto) |
| anomalia comportamental de identidade | Security Hub / Detective | 04 / 10 | ❌ |

## Resposta

Pendente — revogar sessões ativas, rotacionar credenciais, [`runbooks/incident-response/`](../../runbooks/incident-response/).

## Risco residual

Operador usa `AdministratorAccess` — sem least privilege na identidade humana até os
**Labs 15 / 16**. Sem detecção de anomalia comportamental até **Lab 04 / 10**. A janela
entre roubo e detecção depende de revisão manual do CloudTrail hoje.

## Referências

- Ameaça: **`TM-01`** — [`docs/threat-model.md`](../../docs/threat-model.md)
- Lab: a definir
