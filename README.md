# aws-security-specialty-lab

AWS Security Engineering Lab — Implementação prática dos controles de segurança da AWS

## Sobre o projeto

Projeto prático, progressivo e documentado para estudar a certificação **AWS Certified Security - Specialty (SCS-C03)**, construído como uma pequena plataforma AWS corporativa segura. Cada laboratório aplica o ciclo abaixo, combinando Terraform e AWS CLI, com falhas e ataques propositais para praticar detecção, investigação e resposta a incidentes.

## Metodologia

```text
Design → Implement → Break → Detect → Investigate → Respond → Remediate → Document
```

## Domínios do SCS-C03

| Domínio | Peso |
|---|---:|
| 1. Detecção | 16% |
| 2. Resposta a incidentes | 14% |
| 3. Segurança de infraestrutura | 18% |
| 4. Gerenciamento de identidade e acesso | 20% |
| 5. Proteção de dados | 18% |
| 6. Governança e fundamentos de segurança | 14% |

## Estrutura do repositório

```text
aws-security-specialty-lab/
├── architecture/                      # Diagramas de arquitetura
├── terraform/
│   ├── modules/                       # Módulos Terraform reutilizáveis
│   └── environments/                  # Configurações por ambiente
├── labs/
│   ├── 00-foundation/                 # Labs 01-02
│   ├── 01-detection/                  # Labs 03-07
│   ├── 02-incident-response/          # Labs 08-10
│   ├── 03-infrastructure-security/    # Labs 11-14
│   ├── 04-iam/                        # Labs 15-16
│   ├── 05-data-protection/            # Labs 17-18
│   └── 06-governance/                 # Labs 19-20
├── capstones/                         # Desafios finais 01-02
├── attack-scenarios/                  # Cenários de ataque simulados
├── runbooks/                          # Runbooks de incident response
├── evidence/                          # Screenshots, outputs, findings
└── docs/                              # Security design, threat model, decisions, troubleshooting
```

## Roadmap dos laboratórios

| # | Laboratório | Domínio/Fase | Status |
|---|---|---|---|
| 01 | Secure AWS Foundation | Fase 0 — Foundation | ✅ Concluído |
| 02 | Centralized Logging Foundation | Fase 0 — Foundation | ✅ Concluído |
| 03 | GuardDuty | Domínio 1 — Detecção | 🚧 Em Andamento |
| 04 | Security Hub | Domínio 1 — Detecção | 🔒 Não iniciado |
| 05 | Security Lake + OCSF | Domínio 1 — Detecção | 🔒 Não iniciado |
| 06 | Security Analytics | Domínio 1 — Detecção | 🔒 Não iniciado |
| 07 | Macie + Data Discovery | Domínio 1 — Detecção | 🔒 Não iniciado |
| 08 | Incident Response Playbook | Domínio 2 — Resposta a Incidentes | 🔒 Não iniciado |
| 09 | Automated Incident Response | Domínio 2 — Resposta a Incidentes | 🔒 Não iniciado |
| 10 | Forensics + Root Cause | Domínio 2 — Resposta a Incidentes | 🔒 Não iniciado |
| 11 | AWS WAF + CloudFront | Domínio 3 — Segurança de Infraestrutura | 🔒 Não iniciado |
| 12 | Network Security | Domínio 3 — Segurança de Infraestrutura | 🔒 Não iniciado |
| 13 | Secure Compute | Domínio 3 — Segurança de Infraestrutura | 🔒 Não iniciado |
| 14 | Hybrid / Private Connectivity | Domínio 3 — Segurança de Infraestrutura | 🔒 Não iniciado |
| 15 | IAM Least Privilege | Domínio 4 — IAM | 🔒 Não iniciado |
| 16 | Advanced IAM | Domínio 4 — IAM | 🔒 Não iniciado |
| 17 | KMS + Encryption | Domínio 5 — Proteção de Dados | 🔒 Não iniciado |
| 18 | Secure Data + Secrets | Domínio 5 — Proteção de Dados | 🔒 Não iniciado |
| 19 | Multi-Account Security Governance | Domínio 6 — Governança | 🔒 Não iniciado |
| 20 | Compliance + Secure Deployment | Domínio 6 — Governança | 🔒 Não iniciado |
| Capstone 01 | Simulated Security Incident | — | 🔒 Não iniciado |
| Capstone 02 | Security Architecture Challenge | — | 🔒 Não iniciado |

## Stack

- **Terraform** — infraestrutura, reprodutibilidade, documentação como código
- **AWS CLI** — investigação, troubleshooting, validação, operações pontuais

## Licença

[MIT](LICENSE)
