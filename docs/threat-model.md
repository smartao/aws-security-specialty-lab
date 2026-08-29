# Threat Model — AWS Security Specialty Lab

Mapa de alto nível de **contra o que este ambiente se defende**: ativos, fronteiras de
confiança, agentes de ameaça e cenários de ataque, cada cenário amarrado ao controle que o
mitiga, ao laboratório que implementa esse controle e à detecção que o cobre.

Documento **vivo e incremental** — cresce ao final de cada laboratório, no mesmo padrão do
log de revisão de exame (`quiz/`). Não é um threat model corporativo formal; é a camada de
cima que os ADRs (`decisions.md`) referenciam para não repetir o raciocínio de ameaça
espalhado.

## Propósito e uso

- Responder, para qualquer controle do projeto, à pergunta que o `agents.md` exige: _"qual
  ameaça ele ajuda a mitigar?"_ — sem ter que reconstruir isso lab a lab.
- Servir de checklist ao desenhar um lab novo: o control que vou adicionar fecha qual
  cenário? Abre algum risco residual novo?
- Ser artefato de portfólio: demonstrar que a arquitetura partiu de risco, não de "quais
  serviços AWS configurar".

## Escopo atual

| Fase | Labs | Status no threat model |
|---|---|---|
| Fundação | 01 — Secure AWS Foundation | ✅ coberto (v1) |
| Fundação | 02 — Centralized Logging Foundation | ✅ coberto (v1) |
| Domínio 1 — Detecção | 03 — GuardDuty | ✅ coberto (v1) |
| Domínio 1 — Detecção | 04 — Security Hub | ⏳ próximo |
| Demais | 05–20 + capstones | 🔒 fora do escopo desta versão |

Tudo abaixo descreve a postura **ao final do Lab 03**. Cada lab futuro deve revisar este
arquivo (seção "Registro de revisões").

## Relação com os outros documentos

| Documento | Pergunta que responde |
|---|---|
| `threat-model.md` (este) | Contra o que defendemos — ativos, fronteiras, cenários |
| `security-design.md` | Qual é a arquitetura-alvo e o conjunto de controles |
| `decisions.md` (ADRs) | Por quê de cada escolha pontual — problema, alternativas, trade-offs |
| `troubleshooting.md` | O que quebrou de propósito e como foi investigado (TS-00x) |
| `attack-scenarios/` | Roteiro reutilizável de execução de cada ataque — visão do atacante, cruza labs |

## Metodologia

Cenários (não STRIDE puro — o SCS-C03 não cobra STRIDE), com uma **tag STRIDE** por cenário
só para nomear a natureza da ameaça. Cada cenário segue a mesma estrutura curta: vetor →
ativo afetado → impacto → controles preventivos (com lab) → detecção (com lab) → risco
residual (aponta para o lab futuro que fecha a lacuna).

STRIDE, para referência: **S**poofing, **T**ampering, **R**epudiation, **I**nformation
disclosure, **D**enial of service, **E**levation of privilege.

## Glossário de notação

Este documento usa prefixos numerados para poder referenciar cada item de forma estável
(inclusive de outros documentos e dos ADRs). O número **não indica prioridade** — é só um
identificador.

| Prefixo | Nome | O que é | Exemplo | Onde é definido |
|---|---|---|---|---|
| `A#` | **Ativo** (_asset_) | Algo que o ambiente precisa proteger — um recurso, um dado, uma capacidade. | `A1` = a conta AWS `230650392331` | Seção "Ativos" |
| `TB#` | **Fronteira de confiança** (_trust boundary_) | Ponto onde o nível de confiança muda e onde, portanto, precisa existir um controle. | `TB4` = subnets de aplicação → subnets de dados | Seção "Fronteiras de confiança" |
| `TA#` | **Agente de ameaça** (_threat actor_) | Quem executa o ataque, e qual capacidade se assume que ele tem. | `TA3` = workload comprometido (RCE na EC2) | Seção "Agentes de ameaça" |
| `TM-##` | **Cenário de ameaça** (_threat model scenario_) | Um ataque concreto: vetor → ativo → impacto → controle → detecção → risco residual. É a unidade central do documento. | `TM-01` = credencial do operador comprometida | Seção "Cenários de ameaça" |
| `TS-###` | **Episódio de troubleshooting** | Um problema quebrado de propósito e investigado. **Vive em `troubleshooting.md`**, não aqui — o threat model só aponta para ele. | `TS-007` = suppression rule arquivando um finding | `troubleshooting.md` |
| `ADR-###` | **Registro de decisão arquitetural** (_architecture decision record_) | O porquê de uma escolha de projeto. **Vive em `decisions.md`.** O threat model referencia, não repete. | `ADR-001` = segmentação em 3 camadas de subnet | `decisions.md` |
| Letra STRIDE | **Natureza da ameaça** | Tag de uma letra por cenário TM (ver lista acima). Não é categoria do SCS-C03 — é só vocabulário. | `TM-04` → _Information disclosure_ | Seção "Metodologia" |

### Abreviações recorrentes

| Termo | Significado |
|---|---|
| **GD** | GuardDuty (usado só na tabela "Mapa ameaça → controle → detecção" por espaço) |
| **C2 / C&C** | _Command and Control_ — canal que um atacante usa para operar um host comprometido |
| **Baseline de ML** | Modelo de comportamento "normal" que o GuardDuty leva ~7–14 dias para formar por detector; findings de anomalia dependem dele (ver ADR-015) |
| **IMDS** | _Instance Metadata Service_ — endpoint `169.254.169.254` de onde a EC2 lê as credenciais temporárias da sua IAM Role; alvo do cenário TM-02 |
| **Blast radius** | Extensão do estrago se aquele ativo/identidade for comprometido |
| **Least privilege** | Princípio de conceder só a permissão estritamente necessária |
| **Egress** | Tráfego de saída da VPC em direção à internet (aqui, sempre via o NAT Gateway único) |
| **Fechado / Fecha em** | Coluna do mapa de controles: o lab futuro que elimina aquele risco residual |

## Ativos (o que protegemos)

| ID | Ativo | Por que importa aqui |
|---|---|---|
| A1 | Conta AWS `230650392331` | É **management account** de uma AWS Organization (`o-23e9438ykt`, criada ao ativar o IAM Identity Center — ADR-007). Blast radius máximo: comprometer esta conta é comprometer a org inteira. |
| A2 | Identidades e credenciais | Permission sets do IAM Identity Center, IAM Roles, Instance Profile da EC2, sessões STS. Nenhuma credencial estática por desenho (ADR-006), então o alvo passa a ser a sessão temporária e o mecanismo de assumção de role. |
| A3 | Rede da VPC | Subnets (3 camadas), route tables, Security Groups, NACL, NAT Gateway, VPC Endpoints. A segmentação é o controle estrutural que impede exfiltração pela camada de dados (ADR-001). |
| A4 | Compute — EC2 `app_a` | Única carga de trabalho hoje. Superfície de RCE / credential theft do Instance Profile. |
| A5 | Dados em S3 | Bucket de dados do Lab 01 (hoje só objetos de teste) e todo bucket futuro. Confidencialidade e integridade. |
| A6 | Trilha de auditoria | CloudTrail, VPC Flow Logs, CloudWatch Logs e o **log bucket persistente** `awssec-logs-230650392331` (fora do state — ADR-009). É a base de toda investigação futura (Labs 06, 10). Se some, a investigação fica cega. |
| A7 | Estado do Terraform | Bucket `awssec-tfstate-230650392331` (ADR-004). Pode conter atributos sensíveis; quem o lê/escreve controla o mapa de toda a infra. |
| A8 | Configuração de detecção | Detector do GuardDuty (persistente — ADR-015), regra EventBridge, tópico SNS. Desligar isso é pré-condição de um ataque "silencioso". |
| A9 | Orçamento do projeto | Teto **US$ 100 / 6 meses**, absoluto (ADR-007). Free Tier perdido em 2026-08-25. Aqui a disponibilidade financeira é um ativo: abuso de recurso estoura o projeto. |
| A10 | SSM Parameter Store | Prefixos `/lab01`, `/lab02`, `/lab03` — contrato de referência entre labs. Adulterar um valor aqui envenena o lab que o consome. |

## Fronteiras de confiança

```text
                          Internet  (não confiável)
                             │
                   ── TB1 ── IGW / subnets públicas
                             │
                   ── TB2 ── subnets públicas → privadas (app)
                             │
                            EC2 app  ── TB3 ──►  AWS services (S3, SSM)
                             │                   via IAM Role + VPC Endpoint
                   ── TB4 ── privadas (app) → isoladas (dados)
                             │                  (sem rota — fronteira estrutural)
                        subnets isoladas
                        (sem carga hoje)

     Operador humano ── TB5 ──► control plane AWS   (IAM Identity Center / STS)
     Terraform / CI  ── TB6 ──► backend S3 + APIs   (mesma credencial STS do operador)
     Conta 230650392331 ── TB7 ──► AWS Organization  (é a management account)
     Pipelines gerenciados AWS ── TB8 ──► conta      (GuardDuty, ingestão do CloudTrail)
```

| ID | Fronteira | Controle que a materializa |
|---|---|---|
| TB1 | Internet → borda | Sem serviço publicado (sem ALB/CloudFront/WAF ainda). EC2 sem IP público. Só egress via NAT. |
| TB2 | Borda → app | Security Groups por camada; EC2 em subnet privada; acesso admin só via SSM Session Manager, sem SSH exposto, sem bastion. |
| TB3 | Workload → serviços AWS | IAM Role + Instance Profile (zero access key na instância); VPC Gateway Endpoint para S3 com endpoint policy (ADR-003). |
| TB4 | App → dados | **Sem rota nenhuma** da subnet isolada para fora, nem via NAT (ADR-001). Controle de rede, não policy. |
| TB5 | Operador → AWS | IAM Identity Center (SSO) → STS temporário; sem IAM user com access key de longa duração (ADR-006). |
| TB6 | IaC → AWS | Backend S3 com locking nativo; state versionado e criptografado (SSE-S3). Roda com a credencial STS do operador. |
| TB7 | Conta → Organização | Hoje só existe a management account. SCP/RCP e delegated admin são Lab 19 — fronteira ainda **fraca**. |
| TB8 | Pipelines AWS → conta | GuardDuty e a ingestão nativa do CloudTrail têm pipeline próprio, fora dos destinos de log configurados no Lab 02 (nota na ADR-010). |

## Agentes de ameaça

| ID | Agente | Capacidade assumida | Motivação |
|---|---|---|---|
| TA1 | Externo não autenticado | Scan da internet, exploração de serviço exposto | Acesso inicial |
| TA2 | Portador de credencial roubada | Chaves/sessão de operador ou da role da EC2 obtidas via phishing, secret vazado em código, ou exfiltração da metadata da instância | Uso legítimo-aparente da API |
| TA3 | Workload comprometido | RCE na EC2 `app_a`; usa o Instance Profile e a rede de egress | Pivot, C2, mineração |
| TA4 | Operador / erro humano | Credencial administrativa válida (permission set `AdministratorAccess`) | Misconfig sem intenção maliciosa (bucket público, policy `*:*`) |
| TA5 | Cadeia de suprimentos IaC | Provider/módulo Terraform ou dependência maliciosa | Persistência via infra |
| TA6 | Abusador de recurso | Qualquer um dos acima com acesso a compute | Custo (mineração) — estoura o teto de US$ 100 |

## Cenários de ameaça

### TM-01 — Credencial do operador comprometida
**STRIDE:** Spoofing / Elevation · **Agente:** TA2 · **Ativo:** A1, A2 · **Cenário:** [`leaked-secret`](../attack-scenarios/leaked-secret/README.md)

- **Vetor:** sessão SSO ou token STS do operador obtido (device roubado, phishing do fluxo `aws sso login`, cache `~/.aws/sso` copiado).
- **Impacto:** acesso administrativo total à management account.
- **Preventivo:** SSO com credencial de curta duração e sem chave estática (ADR-006, Lab 01); MFA no login do Identity Center.
- **Detecção:** CloudTrail registra toda chamada da sessão (Lab 02); GuardDuty `UnauthorizedAccess:IAMUser/*`, `Recon:IAMUser/*` (Lab 03); alarme de uso de root se escalar para a raiz (Lab 02).
- **Risco residual:** o operador usa `AdministratorAccess` — sem least privilege na identidade humana até os **Labs 15/16**. Sem detecção de anomalia comportamental de identidade até **Security Hub / Detective** (Labs 04, 10). Janela entre roubo e detecção depende de revisão manual do CloudTrail hoje.

### TM-02 — Credencial da role da EC2 exfiltrada e usada de fora
**STRIDE:** Spoofing · **Agente:** TA2, TA3 · **Ativo:** A2, A4, A5 · **Cenário:** [`compromised-ec2`](../attack-scenarios/compromised-ec2/README.md) (fase 2 — roubo de credencial via IMDS)

- **Vetor:** SSRF / RCE lê o IMDS e extrai as credenciais temporárias do Instance Profile; atacante as usa de um IP externo.
- **Impacto:** ações da role (S3, SSM) executadas fora da instância.
- **Preventivo:** role escopada ao mínimo (S3/SSM), sem `*:*` (Lab 01); endpoint policy no VPC Endpoint de S3 (ADR-003). _IMDSv2 obrigatório: a confirmar / candidato a hardening no **Lab 13**._
- **Detecção:** GuardDuty `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration` (Lab 03 — depende de baseline de 7–14 dias); CloudTrail mostra a role usada de um IP fora do range da VPC (Lab 02); VPC Flow Logs mostram sessão anômala (Lab 02).
- **Risco residual:** finding de exfiltração precisa de baseline de ML — nos primeiros dias de um período de estudo pode não disparar (mitigado parcialmente pelo detector persistente, ADR-015). Sem condição `aws:SourceVpc`/`aws:VpcSourceIp` nas policies da role ainda.

### TM-03 — EC2 comprometida vira host de C2 ou mineração
**STRIDE:** Tampering / Denial of service · **Agente:** TA3, TA6 · **Ativo:** A4, A9 · **Cenário:** [`compromised-ec2`](../attack-scenarios/compromised-ec2/README.md) (fases 3–4 — C2 / mineração)

- **Vetor:** payload na instância abre canal de comando-e-controle ou conecta a pool de mineração pela rota de egress (NAT).
- **Impacto:** persistência do atacante; consumo de compute/tráfego que corrói o teto de US$ 100.
- **Preventivo:** egress só via NAT único, sem rota direta; SG restritivo. (Sem egress filtering / Network Firewall até o **Lab 12**.)
- **Detecção:** **exercitado no Lab 03** — `dig` a domínio de C&C conhecido gerou `Backdoor:EC2/C&CActivity.B!DNS` HIGH (8.0), e-mail em ~8 min (TS-007 / evidência `lab03/ts-007-*`); GuardDuty `CryptoCurrency:EC2/BitcoinTool.B*` para mineração; VPC Flow Logs registram o tráfego `ACCEPT`ado (ADR-012, essencial para forense — Lab 10).
- **Risco residual:** só **notificação a humano** hoje — isolamento automático do SG, snapshot e tag são **Lab 09**. Sem visibilidade de processo/arquivo no SO até Runtime Monitoring / Inspector (**Lab 13**).

### TM-04 — Bucket S3 exposto publicamente
**STRIDE:** Information disclosure · **Agente:** TA4 · **Ativo:** A5 · **Cenário:** [`public-s3`](../attack-scenarios/public-s3/README.md)

- **Vetor:** bucket policy com `Principal: "*"` + `s3:GetObject`, ou Block Public Access desligado por engano.
- **Impacto:** leitura anônima de objetos.
- **Preventivo:** Block Public Access ligado por padrão nos buckets do projeto; `force_destroy` não altera exposição.
- **Detecção:** **exercitado no Lab 03** — policy anônima gerou `Policy:S3/BucketAnonymousAccessGranted` HIGH (via pipeline de **management events** do CloudTrail — `PutBucketPolicy` —, não da feature `S3_DATA_EVENTS`; ver correção na ADR-020); CloudTrail data events de S3 habilitados (ADR-010) para rastrear os `GetObject` subsequentes. Só desligar o BPA gera `Policy:S3/BucketBlockPublicAccessDisabled` LOW (2.0) — **abaixo do limiar de e-mail** (ADR-018), rastreado como TS-008.
- **Risco residual:** sem detecção de postura contínua (Config Rule `s3-bucket-public-read-prohibited`) até o **Lab 04 / Lab 20**. Sem Macie para dizer *o que* vazou (**Lab 07**). Findings `Discovery:S3/*` / `Exfiltration:S3/*` (data events) dependem de baseline e não foram exercitados.

### TM-05 — IAM policy com privilégio excessivo → escalonamento
**STRIDE:** Elevation of privilege · **Agente:** TA4, TA2 · **Ativo:** A2, A1 · **Cenário:** [`excessive-iam`](../attack-scenarios/excessive-iam/README.md)

- **Vetor:** policy com `iam:*`, `iam:PassRole` amplo, `sts:AssumeRole` sem escopo, ou `*:*` — permite criar credencial nova, assumir role mais poderosa, ou virar admin.
- **Impacto:** escalonamento até controle total da conta/org.
- **Preventivo:** roles do projeto escopadas por serviço (Lab 01). Sem permission boundary na role da EC2 ainda.
- **Detecção:** CloudTrail registra `CreateAccessKey`, `AttachRolePolicy`, `PutRolePolicy`, `CreateUser` (Lab 02); GuardDuty `PrivilegeEscalation:IAMUser/*`, `Recon:IAMUser/*` (Lab 03).
- **Risco residual:** IAM Access Analyzer, Policy Simulator, permission boundaries e análise de least privilege são **Labs 15/16**. Sem alarme dedicado para mudança de IAM no CloudWatch ainda (só o de root existe).

### TM-06 — Exfiltração de dados da camada sensível
**STRIDE:** Information disclosure · **Agente:** TA2, TA3 · **Ativo:** A5 · **Cenário:** [`compromised-ec2`](../attack-scenarios/compromised-ec2/README.md) (fase 5 — exfiltração); cruza com [`leaked-secret`](../attack-scenarios/leaked-secret/README.md) na via de credencial roubada

- **Vetor:** dados lidos e enviados para fora — via API de S3 com credencial roubada (TM-02), ou por túnel a partir da EC2.
- **Impacto:** perda de confidencialidade de dados sensíveis.
- **Preventivo estrutural:** a subnet isolada **não tem rota externa nenhuma** (ADR-001) — dados em RDS/futuro não têm caminho de rede para a internet, nem via NAT. Exfiltração teria que passar pela camada de aplicação. VPC Gateway Endpoint mantém tráfego S3 dentro da AWS (ADR-003).
- **Detecção:** VPC Flow Logs `ALL` (ADR-012) mostram volume de egress anômalo; GuardDuty `Exfiltration:S3/*` (baseline), `Trojan:EC2/*`; CloudTrail data events de S3 (ADR-010) para `GetObject` em massa.
- **Risco residual:** sem carga real na camada de dados hoje (sem RDS). Sem DLP/Macie (**Lab 07**), sem criptografia com CMK e key policy separada nos dados (**Lab 17/18**), sem S3 Object Lock. Modelo de dados-em-repouso se expande quando esses labs chegarem.

### TM-07 — Adulteração ou supressão da trilha de auditoria
**STRIDE:** Tampering / Repudiation · **Agente:** TA2, TA3 · **Ativo:** A6 · **Cenário:** [`compromised-ec2`](../attack-scenarios/compromised-ec2/README.md) (fase 6 — anti-forense)

- **Vetor:** `StopLogging`, `DeleteTrail`, `UpdateTrail` (redirecionar destino), apagar objetos do log bucket, ou criar atividade só em região não coberta.
- **Impacto:** investigação futura fica cega; atacante ganha repúdio.
- **Preventivo:** CloudTrail **multi-region** (ADR-010) — não há "região não monitorada" para o CloudTrail; log bucket **fora do state** do Lab 02 (ADR-009) — um `terraform destroy` acidental não o apaga; bucket com versionamento.
- **Detecção:** a própria chamada `StopLogging`/`DeleteTrail` é registrada no CloudTrail antes de parar; GuardDuty `Stealth:IAMUser/CloudTrailLoggingDisabled`, `Stealth:S3/ServerAccessLoggingDisabled` (Lab 03); metric filter é candidato natural a alarme (hoje só existe o de root — Lab 02).
- **Risco residual:** log bucket sem **MFA Delete** nem **Object Lock** — quem tiver `s3:DeleteObject` + versão ainda apaga evidência (**Lab 18**). Sem **organization trail** centralizado em conta de Log Archive separada (**Lab 19**). Log file integrity validation: a confirmar no Lab 02.

### TM-08 — Uso da conta root
**STRIDE:** Elevation of privilege · **Agente:** TA2, TA4 · **Ativo:** A1

- **Vetor:** login com o e-mail/senha da raiz da conta (contorna todo IAM).
- **Impacto:** poder irrestrito, incluindo fechar a conta e alterar billing.
- **Preventivo:** operação diária 100% via SSO (ADR-006); MFA na raiz; sem access key de root.
- **Detecção:** **implementado no Lab 02** — metric filter no CloudWatch Logs sobre o CloudTrail + alarme para `userIdentity.type = Root` (ADR-010).
- **Risco residual:** depende do e-mail de alarme ser lido. Sem SCP que barre ações de root em contas member (não aplicável a management account, e só há uma conta — **Lab 19**).

### TM-09 — Comprometimento do state / backend do Terraform
**STRIDE:** Tampering / Information disclosure · **Agente:** TA2, TA5 · **Ativo:** A7

- **Vetor:** acesso de leitura/escrita ao bucket `awssec-tfstate-230650392331`; ou provider/módulo malicioso que injeta recurso no `apply`.
- **Impacto:** leitura de atributos sensíveis do state; drift malicioso persistente na infra.
- **Preventivo:** state **não** compartilhado via `terraform_remote_state` — labs leem só o que o SSM publica (ADR-004), reduzindo exposição; bucket com versionamento e SSE-S3; locking nativo evita corrupção concorrente.
- **Detecção:** CloudTrail data events cobririam `GetObject`/`PutObject` no bucket de state **se incluído no seletor** — hoje o seletor exclui explicitamente só o *log* bucket (ADR-010); acesso ao state cai em data events. GuardDuty S3 (ADR-017).
- **Risco residual:** sem CMK com key policy dedicada no bucket de state; sem verificação de checksum/assinatura de módulos e providers (`.terraform.lock.hcl` cobre hash do provider, não conteúdo). Supply chain de IaC só é tocada no **Lab 20** (cfn-lint, CloudFormation Guard, scanning de pipeline).

### TM-10 — Evasão de detecção
**STRIDE:** Repudiation · **Agente:** TA2, TA3 · **Ativo:** A8 · Relaciona: TS-007, TS-008

- **Vetor:** desabilitar o detector do GuardDuty; criar uma **suppression rule / filtro `ARCHIVE`** que engole o finding do ataque; operar em região sem detector; explorar o limiar de severidade da regra EventBridge (findings LOW não geram e-mail).
- **Impacto:** ataque acontece sem alerta.
- **Preventivo:** detector **persistente** (ADR-015) — não há janela "detector recriado, baseline zerado"; `finding_publishing_frequency = FIFTEEN_MINUTES` (ADR-018) reduz atraso de reocorrência.
- **Detecção / exercício:** **TS-007** cria uma suppression rule casando `Backdoor:EC2/C&CActivity.B!DNS` e investiga "o finding existe mas está *archived*, por quê?" — ensina onde suppression rules escondem coisa. **TS-008** rastreia um finding LOW que sumiu até o `event_pattern` `severity >= 4`. `DeleteDetector`/`UpdateDetector` ficam registrados no CloudTrail.
- **Risco residual:** **GuardDuty é regional** — está em `us-east-1`; um atacante operando em outra região evade o GuardDuty (embora o CloudTrail multi-region ainda o registre). Sem Security Hub agregando + sem alarme em `DeleteDetector` ainda (**Lab 04**). Cobertura multi-region de GuardDuty: **Lab 19**.

### TM-11 — Abuso de custo / negação de serviço financeira
**STRIDE:** Denial of service · **Agente:** TA6, TA3 · **Ativo:** A9

- **Vetor:** mineração na EC2 comprometida (TM-03); spin-up de recursos caros com credencial roubada (TM-01/02); tráfego forçado pelo NAT.
- **Impacto:** estoura o teto de **US$ 100 / 6 meses** — encerra o projeto na prática. Free Tier já não amortece (perdido em 2026-08-25).
- **Preventivo:** hábito de `terraform destroy` por sessão (ADR-007) reduz superfície ligada; NAT único em vez de um por AZ; sem recursos caros persistentes além do necessário.
- **Detecção:** **AWS Budget mensal** `awssec-monthly-budget` — notificações `ACTUAL`/`ABSOLUTE_VALUE` em **US$ 5 e US$ 10** (ADR-007, `setup/setup-budget.md`); GuardDuty `CryptoCurrency:*` pega a causa mais provável.
- **Risco residual:** Budget é mensal e reativo (detecta drift, não previne). Sem SCP limitando tipos de instância / regiões (**Lab 19**). Sem anomaly detection de custo.

## Mapa ameaça → controle → detecção

| ID | Ameaça | Preventivo (lab) | Detecção (lab) | Fecha em |
|---|---|---|---|---|
| TM-01 | Credencial do operador comprometida | SSO / STS curto, MFA (01) | CloudTrail; GD `UnauthorizedAccess/Recon:IAMUser` (02, 03) | 04, 15, 16 |
| TM-02 | Credencial da role da EC2 exfiltrada | Role escopada, endpoint policy (01) | GD `InstanceCredentialExfiltration`; CloudTrail IP externo; Flow Logs (02, 03) | 13 |
| TM-03 | EC2 vira C2 / mineração | Egress só via NAT, SG (01) | GD `Backdoor:EC2/C&CActivity.B!DNS`, `CryptoCurrency:*`; Flow Logs `ALL` (02, 03) ✅ exercitado | 09, 12, 13 |
| TM-04 | Bucket S3 público | Block Public Access (01) | GD `Policy:S3/BucketAnonymousAccessGranted`; CloudTrail `PutBucketPolicy` (02, 03) ✅ exercitado | 04, 07, 20 |
| TM-05 | IAM excessivo → escalonamento | Roles escopadas por serviço (01) | CloudTrail `Attach/PutRolePolicy`; GD `PrivilegeEscalation:IAMUser` (02, 03) | 15, 16 |
| TM-06 | Exfiltração da camada de dados | Subnet isolada sem rota (01); VPC Endpoint S3 (01) | Flow Logs `ALL`; GD `Exfiltration:S3/*`; CloudTrail data events (02, 03) | 07, 17, 18 |
| TM-07 | Supressão da trilha de auditoria | CloudTrail multi-region; log bucket fora do state (02) | Chamada registrada antes de parar; GD `Stealth:*` (02, 03) | 18, 19 |
| TM-08 | Uso da conta root | Operação 100% via SSO, MFA na raiz (01) | Metric filter + alarme `userIdentity.type=Root` (02) ✅ implementado | 19 |
| TM-09 | Comprometimento do state Terraform | Sem `remote_state`; SSM como contrato; SSE-S3 + versionamento (01) | CloudTrail data events cobrem o bucket; GD S3 (02, 03) | 17, 20 |
| TM-10 | Evasão de detecção | Detector persistente; freq. 15 min (03) | TS-007 (suppression rule), TS-008 (limiar de severidade); CloudTrail `Delete/UpdateDetector` (03) ✅ exercitado | 04, 19 |
| TM-11 | Abuso de custo | `destroy` por sessão; NAT único (01) | AWS Budget US$ 5 / US$ 10; GD `CryptoCurrency:*` (00, 03) ✅ implementado | 19 |

## Fora de escopo (consciente)

| Fora de escopo | Onde vive |
|---|---|
| Segurança física dos data centers, hypervisor, hardware | Responsabilidade da AWS (shared responsibility) |
| DDoS volumétrico (L3/4), Shield Advanced | Só conceitual — Labs 08 e 11 (custo do Shield Advanced) |
| Vulnerabilidades de aplicação (SQLi, XSS, deserialização) | Não há aplicação real ainda; WAF no Lab 11, compute no Lab 13 |
| Segurança de containers / EKS | Sem EKS no projeto |
| Ataques a KMS, key policy, grants, material de chave | Lab 17 |
| SCP / RCP como contorno de controle; contas member | Lab 19 (só há uma conta hoje) |
| Supply chain de dependências de aplicação | Fora; supply chain de IaC parcialmente no Lab 20 |
| Engenharia social fora do fluxo de credencial AWS | Fora |

## Riscos residuais no fim da fundação (Labs 01–03)

Consolidado — cada item aponta o lab que deve fechá-lo:

1. **Identidade humana sem least privilege** — operador usa permission set `AdministratorAccess` (confirmado na validação da ADR-006). → **Labs 15, 16.**
2. **Sem detecção de postura contínua** — nada equivalente a AWS Config / Config Rules / Security Hub para pegar drift (bucket que ficou público, SG que abriu 0.0.0.0/0). → **Lab 04**, reforço no **Lab 20.**
3. **Sem proteção de borda** — nenhum WAF / CloudFront / rate limiting; hoje mitigado só por "não há nada publicado". → **Lab 11.**
4. **Log bucket com SSE-S3, não CMK** — qualquer principal com `s3:GetObject` no bucket lê os logs de auditoria; sem key policy separando "quem administra" de "quem decripta" (ADR-013). → **Lab 17.**
5. **Log bucket sem Object Lock / MFA Delete** — evidência é apagável por quem tiver permissão suficiente (TM-07). → **Lab 18.**
6. **Trilha single-account** — sem organization trail entregando para uma conta de Log Archive isolada; um comprometimento da conta atinge infra e evidência juntas. → **Lab 19.**
7. **GuardDuty regional e sem export** — cobertura só em `us-east-1` (TM-10); findings só na janela de 90 dias do console, sem export para S3/Athena (ADR-019). → **Lab 17** (CMK p/ export), **Lab 19** (multi-region / delegated admin).
8. **Resposta 100% manual** — EventBridge → SNS → e-mail apenas; nenhum isolamento, snapshot ou contenção automática (ADR-018). → **Lab 09.**
9. **Findings de anomalia comportamental dependem de baseline** — `InstanceCredentialExfiltration`, `Discovery:S3/AnomalousBehavior` etc. levam 7–14 dias por detector; mitigado por manter o detector persistente (ADR-015), mas ainda há janela cega no começo de um período de estudo longo. → estrutural, monitorar.
10. **IMDSv2 não confirmado como obrigatório** na EC2 — reduz a facilidade do TM-02. → verificar no **Lab 01**, hardening formal no **Lab 13.**
11. **Sem egress filtering** — EC2 comprometida fala com qualquer destino pela rota do NAT (TM-03). → **Lab 12** (Network Firewall).
12. **Camada de dados sem carga** — TM-06 é hoje teórico; revisar quando RDS/dados reais entrarem. → **Labs 17, 18.**

## Registro de revisões

| Data | Versão | Escopo | Mudança |
|---|---|---|---|
| 2026-08-28 | v1 | Labs 01–03 (fundação + GuardDuty) | Rascunho inicial: ativos A1–A10, fronteiras TB1–TB8, agentes TA1–TA6, cenários TM-01–TM-11, mapa de controles, fora de escopo, 12 riscos residuais. |
| 2026-08-28 | v1.1 | — | Adicionado "Glossário de notação" (prefixos `A#`/`TB#`/`TA#`/`TM-##`/`TS-###`/`ADR-###` + abreviações recorrentes). |
| 2026-08-29 | v1.2 | — | `attack-scenarios/`: papel redefinido (roteiro reutilizável, visão do atacante, cruza labs) + índice/template; `suspicious-network-activity` fundido em `compromised-ec2` (fases da mesma cadeia); cenários `public-s3` e `compromised-ec2` (fase C2/DNS) preenchidos a partir do Lab 03; cenários de TM-02/03/06/07 re-apontados. |

**Ao fechar cada lab futuro:** revisar se algum cenário TM muda de "detecção parcial" para "coberto", mover o risco residual correspondente para "fechado", e adicionar cenários novos que o lab introduza (ex: Lab 17 abre a superfície de ataque a KMS).
