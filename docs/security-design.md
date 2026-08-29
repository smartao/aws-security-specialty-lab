# Security Design — AWS Security Specialty Lab

Descreve **qual é a arquitetura-alvo da plataforma e o conjunto de controles** que a
materializa: princípios que guiam o desenho, o estado atual da infraestrutura (fim do
Lab 03) contra a visão conceitual do fim do projeto, o inventário do ambiente e o catálogo
de controles organizado por plano — cada controle amarrado ao ADR que o justifica
(`decisions.md`), à ameaça que ele mitiga (`threat-model.md`) e à tarefa/habilidade
correspondente do SCS-C03.

Documento **vivo e incremental** — cresce ao final de cada laboratório, no mesmo padrão do
threat model e do log de revisão de exame (`quiz/`). É a camada de arquitetura que os ADRs
detalham por decisão e que o threat model consome ao perguntar "qual controle fecha este
cenário?".

## Propósito e uso

- Responder, sem reconstruir lab a lab: _"quais controles a plataforma já tem, onde estão
  implementados e o que ainda falta?"_
- Servir de checklist ao desenhar um lab novo: o controle que vou adicionar entra em qual
  plano? Qual risco residual ele fecha? Qual princípio de design ele precisa respeitar?
- Ser artefato de portfólio: demonstrar que a arquitetura tem um desenho coerente e um
  backlog explícito, não uma pilha de serviços configurados ao acaso.

## Escopo atual

| Fase | Labs | Status no security design |
|---|---|---|
| Fundação | 01 — Secure AWS Foundation | ✅ coberto (v1) |
| Fundação | 02 — Centralized Logging Foundation | ✅ coberto (v1) |
| Domínio 1 — Detecção | 03 — GuardDuty | ✅ coberto (v1) |
| Domínio 1 — Detecção | 04 — Security Hub | ⏳ próximo |
| Demais | 05–20 + capstones | 🔒 fora do escopo desta versão (backlog no fim do doc) |

Tudo abaixo descreve a plataforma **ao final do Lab 03**. Cada lab futuro deve revisar este
arquivo (seção "Registro de revisões").

## Relação com os outros documentos

| Documento | Pergunta que responde |
|---|---|
| `security-design.md` (este) | Qual é a arquitetura-alvo e o conjunto de controles |
| `threat-model.md` | Contra o que defendemos — ativos, fronteiras, cenários |
| `decisions.md` (ADRs) | Por quê de cada escolha pontual — problema, alternativas, trade-offs |
| `troubleshooting.md` | O que quebrou de propósito e como foi investigado (TS-00x) |
| `attack-scenarios/` | Roteiro reutilizável de execução de cada ataque — visão do atacante, cruza labs |

## Princípios de design

Padrões que se repetem nos ADRs e que qualquer lab novo deve respeitar:

1. **Zero credencial estática em qualquer ponto.** Vale para workload (EC2 → IAM Role +
   Instance Profile) e para o operador humano (IAM Identity Center → STS temporário). Sem
   IAM user com access key de longa duração. (ADR-006)
2. **Exposição mínima entre componentes.** Labs consomem uns aos outros pelo que o SSM
   Parameter Store publica, não por `terraform_remote_state` (que exporia o state inteiro).
   A role da EC2 é escopada por serviço; o VPC Endpoint tem endpoint policy além do IAM.
   (ADR-003, ADR-004, ADR-008)
3. **Controle estrutural antes de controle por policy.** Quando a rede pode impedir algo
   (subnet isolada sem rota nenhuma para exfiltração), isso vale mais que uma policy que
   pode ser mal configurada. (ADR-001)
4. **Progressão — cada camada entra no lab que a estuda.** Não antecipar CMK (Lab 17),
   automação de resposta (Lab 09), postura contínua/Config (Labs 04/20) só porque seria
   "mais completo". (ADR-013, ADR-018, ADR-019)
5. **Custo é restrição de primeira classe.** Teto de **US$ 100 / 6 meses**, absoluto. O que
   cobra só por existir (NAT Gateway) sobe/desce por sessão; o que é grátis ocioso
   (detector do GuardDuty) fica de pé. (ADR-002, ADR-007, ADR-015)
6. **Evidência e configuração têm ciclos de vida diferentes.** Log bucket, state do
   Terraform e detector do GuardDuty ficam **fora** do ciclo destroy/recreate por sessão —
   e o log bucket e o state ficam fora de qualquer state de lab. (ADR-009, ADR-015, ADR-016)
7. **Notificar um humano antes de automatizar.** Os labs de fundação entregam alerta
   (alarme de root, findings MEDIUM+ por e-mail); a resposta automática é o Lab 09.
   (ADR-010, ADR-018)
8. **Ao habilitar um serviço, verificar o que ele liga por default** (princípio de menor
   funcionalidade) — descoberto com os protection plans que o GuardDuty ativa sozinho.
   (ADR-017)
9. **O código IaC é o enunciado completo do estado desejado**, não só do delta — daí os
   pins `DISABLED` explícitos nas features do GuardDuty. (ADR-017)

## Arquitetura-alvo

### Visão conceitual (fim do projeto)

Uma pequena plataforma AWS corporativa segura: borda (`CloudFront → WAF → ALB`) na frente
de uma aplicação em subnet privada, dados em subnet isolada, e uma camada de segurança
construída progressivamente por cima (CloudTrail, CloudWatch, GuardDuty, Security Hub,
Security Lake, Inspector, Macie, Config, Detective, IAM Access Analyzer, KMS, Secrets
Manager, Network Firewall, Organizations/SCP, Firewall Manager). Ver diagrama no
[`README.md`](../README.md) da raiz. `architecture/` receberá o diagrama versionado quando
a borda existir (Lab 11).

### Estado atual (fim do Lab 03)

```text
                       Internet
                          │
                    Internet Gateway
                          │
        ┌─────────── Public-A / Public-B (10.0.1.0/24, 10.0.2.0/24)
        │             [NAT Gateway único, em Public-A]
        │                          │  (egress compartilhado)
        │             Private-A / Private-B (10.0.11.0/24, 10.0.12.0/24)
        │               [EC2 app_a, t3.micro, sem IP público]
        │                  │  admin via SSM Session Manager (sem SSH)
        │                  └── VPC Gateway Endpoint ──▶ S3 (bucket do lab)
        │             Isolated-A / Isolated-B (10.0.21.0/24, 10.0.22.0/24)
        │               (route table sem 0.0.0.0/0 — reservada p/ dados)
        │
        ▼  observabilidade (Lab 02) + detecção (Lab 03), pipelines independentes
  ┌──────────────────────────────────────────────────────────────────────┐
  │ CloudTrail multi-region  ─┬─▶ S3  awssec-logs-230650392331 (persistente)│
  │  (mgmt + S3 data events)  └─▶ CloudWatch Logs ─▶ metric filter root ─▶ │
  │                                                   alarm ─▶ SNS/e-mail  │
  │ VPC Flow Logs (ALL)       ──▶ S3 + CloudWatch Logs                     │
  │                                                                      │
  │ GuardDuty (detector persistente, us-east-1, freq 15 min)             │
  │  fontes: CloudTrail mgmt · DNS query logs · VPC Flow Logs · S3 data  │
  │  + S3 Protection + Malware Protection for EC2                        │
  │            │ finding severity ≥ 4                                     │
  │            ▼                                                          │
  │  EventBridge rule ─▶ SNS awssec-lab03-sns-guardduty-findings ─▶ e-mail│
  │            │ (SSM /lab03/* — Lab 09 pendura a automação aqui)         │
  └──────────────────────────────────────────────────────────────────────┘
```

## Ambiente e inventário

### Conta e organização

| Item | Valor |
|---|---|
| Conta AWS | `230650392331` — management account da AWS Organization `o-23e9438ykt` (criada ao ativar o IAM Identity Center, ADR-007) |
| Região de recursos | `us-east-1` (única). CloudTrail é multi-region; GuardDuty é regional, só em `us-east-1` |
| Autenticação humana | IAM Identity Center, grupo `Administrators`, permission set gerenciado `AdministratorAccess`, profile CLI `sergei-upstart` |
| Teto de custo | US$ 100 / 6 meses (absoluto). Free Tier perdido em 2026-08-25 |

### Estados Terraform (todos no backend `awssec-tfstate-230650392331`, lock nativo)

| Key | Escopo | Ciclo de vida | ~Recursos |
|---|---|---|---|
| `lab01/terraform.tfstate` | VPC, subnets, rotas, IGW, NAT, VPC Endpoint S3, SG, IAM Role/Profile, EC2, bucket de dados | **efêmero** — destroy/recreate por sessão (ADR-007), via `scripts/manage-foundation.sh` | ~38 |
| `lab02/terraform.tfstate` | CloudTrail, Flow Logs, log groups, metric filter/alarm root, SNS, roles de serviço, bucket de resultados do Athena | **efêmero** — mesmo ciclo, depende do Lab 01 aplicado | ~22 |
| `lab03/terraform.tfstate` | Detector do GuardDuty + features, regra EventBridge, tópico SNS, parâmetros `/lab03/*` | **persistente** — aplicado uma vez; `destroy` só ao encerrar os estudos (ADR-016). Não entra no `manage-foundation.sh` | ~15 |

### Recursos fora de qualquer state (bootstrap / persistentes)

| Recurso | Papel | Gestão |
|---|---|---|
| `awssec-tfstate-230650392331` | Backend do Terraform — SSE-S3, versionado, Block Public Access, lock via conditional writes | CLI, `ManagedBy=manual` (ADR-004) |
| `awssec-logs-230650392331` | Destino de CloudTrail + VPC Flow Logs — SSE-S3, versionado, BPA (4 flags), lifecycle Standard-IA aos 30d, bucket policy TLS-only + delivery CloudTrail/Flow Logs com `aws:SourceArn`/`aws:SourceAccount` | CLI, `ManagedBy=manual` (ADR-009) |
| `awssec-monthly-budget` | AWS Budget mensal US$ 10, notificações `ACTUAL`/`ABSOLUTE_VALUE` em US$ 5 e US$ 10 | CLI (ADR-007) |
| IAM Identity Center | Grupo, usuário, permission set e assignment para autenticação humana | Console (setup) |
| Toggle "IAM user and role access to Billing information" | Habilita acesso a Billing/Cost Explorer para identidades IAM — controle **fora do modelo IAM** | Console, conta root (TS-002) |

### Contrato entre labs — SSM Parameter Store

| Prefixo | Publicado por | Conteúdo |
|---|---|---|
| `/lab01/*` | Lab 01 | 9 parâmetros: `vpc_id`, IDs das 6 subnets, etc. — consumido pelo Lab 02 (Flow Logs) e labs futuros |
| `/lab02/*` | Lab 02 | Nome do trail, nomes dos log groups, nomes dos buckets, ARN do tópico SNS |
| `/lab03/*` | Lab 03 | `detector_id`, `sns_topic_arn`, `eventbridge_rule_name` — o Lab 09 pendura a automação aqui |

Prefixo **não** pode começar com `aws`/`ssm` (nomes reservados do serviço) — por isso é
`/lab01/...` e não `/awssec/lab01/...` (TS-003).

## Conjunto de controles

Cada tabela: controle → como está implementado → ADR → ameaça do threat model → habilidade
SCS-C03. Ao final de cada plano, os **riscos residuais** e o lab que os fecha.

### 1. Identidade e acesso

| Controle | Implementação | ADR | Ameaça | SCS-C03 |
|---|---|---|---|---|
| Autenticação humana federada, sem chave estática | IAM Identity Center → `sts:AssumeRole` (`AWSReservedSSO_AdministratorAccess_*`); `aws sso login` por sessão | ADR-006 | TM-01, TM-08 | 4.1.1, 4.1.2 |
| Zero credencial estática no workload | EC2 usa IAM Role `awssec-lab01-role-ec2-app` + Instance Profile; nenhuma access key na instância | ADR-006 | TM-02 | 3.2.2, 4.1.2 |
| Role da EC2 escopada por serviço | `AmazonSSMManagedInstanceCore` (gerenciada) + inline policy só no bucket de dados do lab (`s3:ListBucket` no bucket, `Get/Put/DeleteObject` nos objetos) | ADR-008 | TM-02, TM-05 | 4.2.3 |
| Acesso admin à EC2 sem porta exposta | SSM Session Manager; SG `awssec-lab01-sg-ec2-app` **sem regra de ingress**; sem SSH, sem bastion | ADR-006 | TM-03 | 3.2.5 |
| Uso da conta root vigiado | Metric filter (padrão CIS) sobre o log group do CloudTrail → alarme `awssec-lab02-alarm-root-usage` → SNS `awssec-lab02-sns-security-alarms` → e-mail | ADR-010 | TM-08 | 1.1.4, 6.1.5 |
| Acesso a Billing habilitado conscientemente | Toggle "IAM access to Billing" ligado na conta root (gate fora do IAM) | — (TS-002) | — | 6.x (nota) |

**Risco residual:** operador usa `AdministratorAccess` (sem least privilege na identidade
humana); sem permission boundary na role da EC2; sem condição `aws:SourceVpc` /
`aws:VpcSourceIp` nas policies; **IMDSv2 não forçado** na EC2 (sem bloco `metadata_options`).
→ Labs 13, 15, 16.

### 2. Rede

| Controle | Implementação | ADR | Ameaça | SCS-C03 |
|---|---|---|---|---|
| Segmentação em 3 camadas | 6 subnets (pública/privada/isolada × 2 AZ), 3 route tables | ADR-001 | TM-06 | 3.3.4 |
| Camada de dados sem rota externa | Route table `awssec-lab01-rtb-isolated` sem `0.0.0.0/0` — nem via NAT | ADR-001 | TM-06 | 3.3.4 |
| Egress por um ponto único | NAT Gateway único em Public-A, compartilhado pelas duas subnets privadas | ADR-002 | TM-03, TM-11 | 3.3.1 |
| Tráfego EC2 → S3 privado | VPC Gateway Endpoint S3 (`awssec-lab01-vpce-s3`) na route table privada + endpoint policy restrita ao bucket do lab | ADR-003 | TM-02, TM-06 | 5.1.2 |
| Controle de host por camada | Security Group da camada de aplicação: sem ingress, egress `-1` | — | TM-03 | 3.3.1 |
| Acesso privado a serviços em subnet sem rota | 3 VPC Interface Endpoints (`ssm`, `ssmmessages`, `ec2messages`) + SG dedicado — criados no exercício TS-004, **fora do desenho permanente** | — (TS-004) | — | 5.1.2, 3.2.5 |

**Risco residual:** **NACL explícita não materializada** — só a NACL default da VPC
(allow-all) está em vigor, apesar de listada como componente; SG de egress é `0.0.0.0/0`
(sem egress filtering); SG por camada só existe para a de aplicação; sem AWS Network
Firewall / Network Access Analyzer. → Lab 12 (reforço de hardening no Lab 13).

### 3. Detecção, logging e alerta

| Controle | Implementação | ADR | Ameaça | SCS-C03 |
|---|---|---|---|---|
| Trilha de API multi-region | CloudTrail `awssec-lab02-trail`, `is_multi_region_trail = true`, `enable_log_file_validation = true`, global service events | ADR-010 | TM-01, TM-05, TM-07 | 1.2.1, 1.2.2 |
| Data events de S3 | Advanced event selector: `AWS::S3::Object` em todos os buckets, `not_starts_with` o log bucket (evita loop autorreferencial) | ADR-010 | TM-04, TM-06, TM-09 | 1.2.6 |
| Entrega dupla | S3 `awssec-logs-230650392331` (retenção barata → Athena/Lab 06) + CloudWatch Logs `/aws/cloudtrail/awssec-lab02-trail` (metric filters / Logs Insights) | ADR-010 | TM-07 | 1.2.2, 1.2.4 |
| Tráfego de rede auditado | 2× `aws_flow_log` (S3 + CloudWatch) na VPC do Lab 01, `traffic_type = ALL` (não só `REJECT`) | ADR-012 | TM-02, TM-03, TM-06 | 1.2.6 |
| Retenção alinhada ao horizonte | 180 dias no CloudWatch Logs; S3 → Standard-IA aos 30 dias, **sem Glacier** (Athena não lê Glacier sem restore) | ADR-011 | — | 5.2.3 |
| Detecção de ameaça gerenciada | GuardDuty detector persistente (`us-east-1`, `FINDING_PUBLISHING_FREQUENCY = FIFTEEN_MINUTES`); features `ENABLED`: `CLOUD_TRAIL`, `DNS_LOGS`, `FLOW_LOGS`, `S3_DATA_EVENTS`, `EBS_MALWARE_PROTECTION` | ADR-015, ADR-016, ADR-017 | TM-02, TM-03, TM-04, TM-10 | 1.1.4, 3.2.3 |
| Menor funcionalidade nos protection plans | Pins explícitos `DISABLED` em `EKS_AUDIT_LOGS`, `RDS_LOGIN_EVENTS`, `LAMBDA_NETWORK_LOGS`, `RUNTIME_MONITORING` (a AWS liga por default) | ADR-017 | — | 1.1.4 |
| Roteamento de finding a humano | EventBridge `awssec-lab03-eventbridge-guardduty-findings` (`source = aws.guardduty`, `severity ≥ 4`) → SNS `awssec-lab03-sns-guardduty-findings` → e-mail, com input transformer | ADR-018 | TM-03, TM-04 | 1.1.4, 1.3.x |

**Risco residual:** sem export de findings para S3 (exige CMK — Lab 17); **GuardDuty
regional** (só `us-east-1`); sem Security Hub agregando GuardDuty/Inspector/Config; sem
alarme dedicado em `DeleteDetector`/`UpdateDetector`/`StopLogging`; sem postura contínua
(AWS Config). Findings de anomalia comportamental ainda dependem de baseline de 7–14 dias.
→ Labs 04, 17, 19, 20.

### 4. Proteção de dados

| Controle | Implementação | ADR | Ameaça | SCS-C03 |
|---|---|---|---|---|
| Block Public Access | 4 flags `true` em todos os buckets do projeto (dados do Lab 01, log bucket, state) | — | TM-04 | 5.2.x / 4.2.x |
| Criptografia em repouso | SSE-S3 (`AES256`) em todos os buckets; CMK adiada para o Lab 17 | ADR-013 | TM-09 | 5.2.1 |
| Integridade / histórico | Versionamento no log bucket e no bucket de state; CloudTrail log file validation | ADR-004, ADR-009 | TM-07, TM-09 | 5.2.2 |
| TLS obrigatório no log bucket | Statement `DenyInsecureTransport` (`aws:SecureTransport = false`) na bucket policy | ADR-009 | TM-07 | 5.1.1 |
| Anti confused-deputy na entrega de log | Bucket policy com `aws:SourceArn` (ARN exato do trail) para CloudTrail e `aws:SourceAccount` para Flow Logs | ADR-009 (TS-006) | TM-07 | 4.2.1 |
| Ciclo de vida de log | Standard-IA aos 30 dias, sem camada Glacier | ADR-011 | — | 5.2.3 |
| Semântica de `force_destroy` | Só em buckets efêmeros/regeneráveis (dados do Lab 01, resultados do Athena) — **nunca** no log bucket | ADR-014 | — | 5.2.x |

**Risco residual:** SSE-S3 e não CMK (sem key policy separando "quem administra" de "quem
decripta" os logs); log bucket sem **Object Lock** nem **MFA Delete** (evidência apagável
por quem tiver `s3:DeleteObject`); bucket de dados do Lab 01 **sem versionamento**; sem
Macie para dizer *o que* vazaria; camada de dados sem carga real (sem RDS). → Labs 07, 17, 18.

### 5. Governança, IaC e custo

| Controle | Implementação | ADR | Ameaça | SCS-C03 |
|---|---|---|---|---|
| State remoto com lock nativo | Backend S3 `awssec-tfstate-230650392331`, `use_lockfile = true`, sem DynamoDB | ADR-004 | TM-09 | 6.2.1 |
| Contrato entre labs desacoplado | SSM Parameter Store `/labNN/*` em vez de `terraform_remote_state` | ADR-004 | TM-09 | 6.2.1 |
| Nomenclatura e tags padrão | `{projeto}-{lab}-{tipo}-{detalhe}[-{az}]`; tags `Project` / `Lab` / `Environment=study` / `ManagedBy` em todo recurso | ADR-005 | — | 6.2.2 |
| Abstração só sob demanda | Root module único por lab; extrair módulo só com 2º consumidor real | ADR-008 | — | 6.2.1 |
| Fronteira notificação / automação | Lab 03 publica tópico SNS + regra no SSM; a automação de resposta é o Lab 09 | ADR-018 | — | 2.1.4 |
| Teto de custo por hábito | `terraform destroy` da fundação por sessão (`scripts/manage-foundation.sh`, Labs 01+02); NAT único; sem recurso caro persistente | ADR-002, ADR-007 | TM-11 | — |
| Rede de segurança de custo | AWS Budget `awssec-monthly-budget` US$ 10/mês, alertas em US$ 5 e US$ 10 | ADR-007 | TM-11 | 1.1.4 |
| Detecção persistente e barata | Detector do GuardDuty fora do ciclo destroy — grátis ocioso, preserva o baseline de ML e o `detectorId` | ADR-015, ADR-016 | TM-10 | 1.1.4 |
| IaC como estado completo | Pins `DISABLED` explícitos nas features do GuardDuty, não só o delta | ADR-017 | — | 6.2.1 |

**Risco residual:** sem organization trail entregando a uma conta de Log Archive isolada;
sem SCP/RCP; sem delegated administrator; sem AWS Config / Config Rules / Conformance
Packs; sem scanning de IaC (cfn-lint, CloudFormation Guard); bucket de state sem CMV
dedicada. `runbooks/` segue scaffoldado; `attack-scenarios/` teve o papel redefinido
(roteiro reutilizável, visão do atacante, cruza labs) e 2 de 4 cenários preenchidos a
partir do Lab 03 (`public-s3`, `compromised-ec2` fase C2/DNS) — `leaked-secret` e
`excessive-iam` pendentes dos Labs 15/16.
→ Labs 19, 20 (e Labs 08–10 para os runbooks).

## Cobertura por domínio SCS-C03

| Domínio | Implementado até o Lab 03 | Próximos labs |
|---|---|---|
| 1 — Detecção (16%) | CloudTrail multi-region + data events, VPC Flow Logs `ALL`, CloudWatch metric filter/alarm de root, GuardDuty + roteamento EventBridge/SNS | 04 Security Hub · 05 Security Lake/OCSF · 06 Analytics · 07 Macie |
| 2 — Resposta a incidentes (14%) | Ponto de entrada (finding) + camada de notificação a humano; `runbooks/` scaffoldado | 08 Playbook · 09 automação (EventBridge→Lambda) · 10 forense/Detective |
| 3 — Segurança de infraestrutura (18%) | Segmentação em 3 camadas, SG por host, VPC Gateway/Interface Endpoints, SSM Session Manager | 11 WAF/CloudFront · 12 Network Firewall + NACL · 13 hardening/IMDSv2/Inspector · 14 conectividade híbrida |
| 4 — IAM (20%) | SSO→STS sem chave estática, role escopada por serviço, Instance Profile | 15 least privilege · 16 ABAC, permission boundaries, Access Analyzer |
| 5 — Proteção de dados (18%) | BPA, SSE-S3, versionamento, TLS-only, lifecycle, log file validation | 17 KMS/CMK + export de findings · 18 Object Lock, Secrets Manager, ACM, Backup |
| 6 — Governança e fundamentos (14%) | Terraform backend + lock nativo, contrato SSM, naming/tags, AWS Budget | 19 Organizations/SCP/delegated admin · 20 Config/Conformance Packs/IaC scanning |

## Controles-alvo pendentes (backlog de design)

| Lab | Controle a adicionar | Fecha (risco residual / ameaça) |
|---|---|---|
| 04 | AWS Config + Config Rules; Security Hub agregando GuardDuty/Inspector/Config; alarme em `DeleteDetector` | postura contínua ausente; TM-04, TM-10 |
| 07 | Macie — descoberta e classificação de dados sensíveis | "o que vazaria"; TM-04, TM-06 |
| 09 | EventBridge → Lambda/Step Functions: isola SG, snapshot EBS, taggeia; assina no `/lab03/sns_topic_arn` | resposta 100% manual; TM-03 |
| 10 | Detective (grafo de entidades); disciplina de coletar evidência volátil antes do teardown | forense; lição do teardown no Lab 03 |
| 11 | CloudFront + AWS WAF (rate limiting, geo, OWASP, headers) | sem proteção de borda (TB1 fraca) |
| 12 | AWS Network Firewall, **NACL explícita**, Network Access Analyzer, egress filtering | NACL não materializada; TM-03 |
| 13 | IMDSv2 obrigatório, Inspector, Patch Manager, Runtime Monitoring do GuardDuty | TM-02; sem visibilidade de processo no SO |
| 15 / 16 | Least privilege na identidade humana, permission boundaries, session policies, IAM Access Analyzer, condições `aws:SourceVpc` | TM-01, TM-05; operador em `AdministratorAccess` |
| 17 | CMK no log bucket e no state (key policy dedicada); export de findings do GuardDuty para S3 | riscos residuais de dados 4 e 7 |
| 18 | S3 Object Lock / MFA Delete no log bucket; Secrets Manager; AWS Backup; versionamento no bucket de dados | TM-07; risco residual de dados 5 |
| 19 | Organization trail + conta Log Archive isolada; SCP/RCP; delegated admin; GuardDuty/Security Hub multi-account e multi-region | TM-07, TM-10; trilha single-account |
| 20 | Conformance Packs; scanning de IaC (cfn-lint, CloudFormation Guard); remediação automática do Config | supply chain de IaC; TM-09 |

## Convenções

Detalhe completo na ADR-005 e na tabela de naming do
[README do Lab 01](../labs/00-foundation/01-secure-aws-foundation/README.md).

- **Nome:** `{projeto}-{lab}-{tipo-recurso}-{detalhe}[-{az}]`, `awssec` = abreviação do
  projeto. Ambiente **não** entra no nome — só como tag.
- **Tags padrão:** `Project = aws-security-specialty-lab`, `Lab = labNN`,
  `Environment = study`, `ManagedBy = terraform` (ou `manual` nos recursos de bootstrap).
- **SSM Parameter Store:** prefixo `/labNN/...` — nunca começar com `aws`/`ssm`.
- **Buckets persistentes** (bootstrap) não seguem o padrão de nome por lab: usam
  `{projeto}-{papel}-{account-id}` para unicidade global.

## Registro de revisões

| Data | Versão | Escopo | Mudança |
|---|---|---|---|
| 2026-08-28 | v1 | Labs 01–03 (fundação + GuardDuty) | Rascunho inicial: 9 princípios de design, arquitetura-alvo vs. estado atual, inventário (3 states Terraform, recursos de bootstrap fora de state, contrato SSM), catálogo de controles em 5 planos com risco residual por plano, cobertura por domínio SCS-C03, backlog de design para os Labs 04–20. |
| 2026-08-29 | v1.1 | — | `attack-scenarios/` redefinido como roteiro reutilizável (visão do atacante, cruza labs) + índice/template; `suspicious-network-activity` fundido em `compromised-ec2`; cenários `public-s3` e `compromised-ec2` (fase C2/DNS) preenchidos a partir do Lab 03. |

**Ao fechar cada lab futuro:** mover para o catálogo os controles que o lab implementou,
remover do backlog os itens correspondentes, atualizar a cobertura por domínio e revisar
se algum risco residual foi fechado (espelhando o mesmo movimento no `threat-model.md`).
