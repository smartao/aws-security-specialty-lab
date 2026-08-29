# Attack Scenario — compromised-ec2

**Descrição:** Instância EC2 sob controle de um atacante usada como pivô — roubo da
credencial do Instance Profile, canal de C2, mineração, exfiltração de dados e supressão da
trilha de auditoria.
**Status:** 🚧 Parcial — fase **C2 / DNS** exercitada no Lab 03 (2026-08-28); demais fases pendentes.
**STRIDE:** Spoofing · Tampering · Information disclosure · Denial of service
**Agente:** TA3 (workload comprometido) · TA2 (portador de credencial roubada) · TA6 (abusador de recurso)
**Ameaça:** `TM-02`, `TM-03`, `TM-06`, `TM-07` — [`docs/threat-model.md`](../../docs/threat-model.md)
**Labs que exercitam:** 03 (detecção) ✅ · 09 (resposta automática) · 10 (forense) · 12 (egress filtering) · 13 (runtime / IMDSv2)

> **O que este arquivo é.** O roteiro **reutilizável** de execução deste ataque (visão do
> atacante, cruza labs). O registro datado de cada execução fica no
> [README do Lab 03](../../labs/01-detection/03-guardduty/README.md); a moldura de risco
> (preventivo / detecção / residual) fica no [`threat-model.md`](../../docs/threat-model.md);
> a resposta operacional fica em [`runbooks/`](../../runbooks/). Índice e template:
> [`../README.md`](../README.md).

## Objetivo do ataque simulado

Exercitar o ciclo **detectar → investigar → conter** a partir de uma EC2 que o atacante
controla: mostrar qual sinal cada fase gera, em qual pipeline, e o que ainda passa
despercebido na fundação (Labs 01–03).

## Fases

| # | Fase | Meta do atacante | TM | Exercitado |
|---|---|---|---|---|
| 1 | Acesso inicial (RCE / SSRF) | shell na `app_a` | — | assumido (sem app real — simulado por sessão SSM) |
| 2 | Roubo de credencial via IMDS | usar a role da instância de fora | `TM-02` | ❌ (depende de baseline de ML) |
| 3 | **Command & Control (DNS)** | canal de comando | `TM-03` | ✅ Lab 03 |
| 4 | Mineração | monetizar o compute | `TM-03` / `TM-11` | ❌ |
| 5 | Exfiltração de dados | tirar dados da camada sensível | `TM-06` | ❌ (sem carga real) |
| 6 | Anti-forense | apagar rasto (`StopLogging`, `DeleteTrail`, …) | `TM-07` | ❌ (derivado) |

## Pré-condições

- EC2 do Lab 01 no ar (`scripts/manage-foundation.sh up`) — a instância resolve DNS pelo
  resolver da VPC (default), condição da fase 3.
- Acesso admin via **SSM Session Manager** (sem SSH — ADR-006).
- Detector do GuardDuty persistente `ENABLED` em `us-east-1` (Lab 03, ADR-015).

## Execução

### Fase 3 — Command & Control por DNS  ✅

Da EC2, via Session Manager, disparar consultas a um domínio de C&C conhecido das threat
lists do GuardDuty:

```bash
aws ssm start-session --target <instance-id>
# dentro da sessão (a AMI AL2023 não traz dig/nslookup):
for i in 1 2 3; do getent hosts guarddutyc2activityb.com; done
```

`guarddutyc2activityb.com` é um domínio de teste da AWS. **NXDOMAIN não impede o finding** —
o gatilho é a *query* enviada ao resolver da VPC, não uma resolução bem-sucedida.

### Fase 2 — roubo de credencial via IMDS  _(a definir — Lab 13)_
### Fase 4 — mineração  _(a definir — Lab 09 / 13)_
### Fase 5 — exfiltração  _(a definir — Lab 07)_
### Fase 6 — anti-forense  _(a definir — Labs 18 / 19; ver `TM-07`)_

## Detecção esperada

| Fase | Sinal | Pipeline / fonte | Lab | Exercitado |
|---|---|---|---|---|
| 3 C2/DNS | `Backdoor:EC2/C&CActivity.B!DNS` HIGH (8.0) | GuardDuty — DNS query logs (Route 53 Resolver, pipeline próprio) | [03](../../labs/01-detection/03-guardduty/README.md) | ✅ finding `b8d023e3…`, e-mail ~8 min |
| 2 cred theft | `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration` | GuardDuty — CloudTrail + baseline; CloudTrail mostra a role usada de IP fora da VPC | 03 / 13 | ❌ baseline 7–14 d |
| 4 mineração | `CryptoCurrency:EC2/BitcoinTool.B*` | GuardDuty; VPC Flow Logs `ALL` mostram o tráfego `ACCEPT`ado | 03 / 02 | ❌ |
| 5 exfil | `Exfiltration:S3/*`, `Trojan:EC2/DGADomainRequest*`; volume de egress anômalo | GuardDuty (baseline); VPC Flow Logs; CloudTrail S3 data events | 03 / 02 / 07 | ❌ |
| 6 anti-forense | `Stealth:IAMUser/CloudTrailLoggingDisabled` | a chamada `StopLogging` fica no CloudTrail *antes* de parar; GuardDuty | 03 / 02 | ❌ |

Investigação de referência da fase 3 — timeline `StartSession → 1ª query DNS em 16 s`, e a
lição de coletar VPC Flow Logs **antes** do teardown:
[Lab 03 § Detecção e investigação](../../labs/01-detection/03-guardduty/README.md#detecção-e-investigação).

## Resposta

- **Contenção:** isolar o SG da instância, snapshot do EBS, revogar as sessões ativas da
  role, taggear para forense → [`runbooks/containment/`](../../runbooks/containment/);
  automação no **Lab 09** (EventBridge → Lambda, assina em `/lab03/sns_topic_arn`).
- **Erradicação / forense:** grafo de entidades no Detective, análise de processo/arquivo →
  **Lab 10**; snapshot agentless já pronto via Malware Protection for EC2 (ADR-017).
- **No lab:** `exit` da sessão (nada é instalado) + a instância cai no teardown de sessão.

## Risco residual

- Sem **egress filtering** — a EC2 fala com qualquer destino pela rota do NAT → **Lab 12** (Network Firewall).
- Sem visibilidade de **processo/arquivo** no SO — GuardDuty não diz *qual* processo fez a query → **Lab 13** (Runtime Monitoring / Inspector).
- Resposta ainda **100 % manual** → **Lab 09**.
- Findings de anomalia (fases 2, 4, 5) dependem de **baseline de ML** de 7–14 dias por detector — mitigado pelo detector persistente (ADR-015), não eliminado.

## Referências

- Ameaça: **`TM-02`, `TM-03`, `TM-06`, `TM-07`** — [`docs/threat-model.md`](../../docs/threat-model.md)
- ADRs: ADR-015 (detector persistente), ADR-017 (protection plans), ADR-018 (roteamento `severity ≥ 4`), ADR-020 (ataque proposital duplo) — [`docs/decisions.md`](../../docs/decisions.md)
- Evidências: [`evidence/lab03/ts-007-*`](../../evidence/lab03/) — finding C2/DNS + exercício de suppression rule
- Troubleshooting: **TS-007** (suppression rule arquivando o finding) — [`docs/troubleshooting.md`](../../docs/troubleshooting.md)
- Lab: [03 — GuardDuty](../../labs/01-detection/03-guardduty/README.md)
