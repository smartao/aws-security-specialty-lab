# Glossário — AWS Security Specialty Lab

Dicionário dos **termos específicos de segurança** que aparecem nos labs, nos ADRs
(`decisions.md`), no threat model, nos `quiz/` e no guia do SCS-C03 — siglas de formatos,
frameworks, controles, técnicas de ataque e conceitos de criptografia/identidade que não são
óbvios pelo nome.

Documento **vivo e incremental** — cresce ao final de cada laboratório, no mesmo padrão do
threat model e do log de revisão de exame. Não repete o que já está definido em outro doc: a
**notação interna do projeto** (`A#` ativo, `TB#` fronteira, `TA#` agente, `TM-##` cenário,
`TS-###` troubleshooting, `ADR-###` decisão) vive no
["Glossário de notação" do threat-model.md](threat-model.md#glossário-de-notação).

## Propósito e uso

- Ter um lugar único para procurar "o que é _CSPM_ / _ASFF_ / _envelope encryption_ /
  _confused deputy_" sem reabrir o slide do curso ou o guia do exame.
- Servir de checklist de vocabulário ao escrever um lab novo: os termos que eu usei no README
  estão definidos em algum lugar? O aluno-futuro-eu entende sem contexto?
- Ser artefato de portfólio: mostrar domínio do vocabulário da área, não só dos serviços.

## Escopo — o que entra e o que fica de fora

**Entra:** todo termo que designe um **controle de segurança, uma propriedade de segurança,
uma técnica de ataque, um formato/framework de segurança ou um conceito de
cripto/identidade** — mesmo quando o serviço-base é genérico (ex.: _endpoint policy_,
_Block Public Access_, _stateful vs stateless_).

**Fica de fora:** primitivos de infraestrutura sem função de segurança própria (EC2, VPC,
IGW, sub-rede, AZ, Route Table, S3 enquanto "armazenamento"). Esses são pré-requisito, não
assunto. Também fica de fora a notação `A#/TB#/TA#/TM-##` (ver acima).

## Relação com os outros documentos

| Documento | Pergunta que responde |
|---|---|
| `glossario.md` (este) | O que **significa** este termo/sigla |
| `threat-model.md` | Contra o que defendemos + notação `A#/TB#/TA#/TM-##` |
| `security-design.md` | Qual a arquitetura-alvo e o catálogo de controles |
| `decisions.md` (ADRs) | Por quê de cada escolha pontual |
| `reference/AWS-SCS-C03-topicos-exame.md` | O que o exame cobra, tarefa a tarefa |

**Notação das entradas:** `**SIGLA** — *Expansão em inglês* (tradução). Definição. → Lab NN`
quando o termo é exercitado num lab específico.

---

## 1. Formatos de dados, frameworks e padrões

- **ASFF** — *AWS Security Finding Format* (formato de descoberta de segurança da AWS). Schema
  JSON único em que o **Security Hub CSPM** normaliza findings de qualquer fonte (GuardDuty,
  Inspector, Macie, Config, parceiros). Campos-chave: `Severity.Label`, `Compliance.Status`,
  `Workflow.Status`, `RecordState`, `ResourceId`, `ProductName`. É o que permite priorizar e
  filtrar findings de origens diferentes lado a lado. Removido da Tarefa 1.1 do SCS-C03 como
  tópico de estudo, mas continua sendo o mecanismo real. → Lab 04
- **OCSF** — *Open Cybersecurity Schema Framework*. Schema aberto e vendor-neutral para
  eventos de segurança, adotado pelo **Security Lake** e pelo **Security Hub unificado novo**
  (GA dez/2025). Sucessor conceitual do ASFF para o mundo multi-fonte/data-lake. → Lab 05
- **FSBP** — *AWS Foundational Security Best Practices*. Standard de controles mantido pela
  AWS dentro do Security Hub CSPM (`EC2.13`, `S3.1`, `IAM.*`, `GuardDuty.1`…). É o standard
  "default" do lab; cada control é lastreado por uma Config managed rule. → Lab 04
- **CIS AWS Foundations Benchmark** — conjunto de recomendações de hardening publicado pelo
  *Center for Internet Security*, disponível como standard no Security Hub. Mais prescritivo e
  mais antigo que o FSBP; cai no exame como "qual standard usar".
- **PCI DSS** — *Payment Card Industry Data Security Standard*. Standard de conformidade para
  ambientes que processam cartão; também disponível como standard do Security Hub.
- **NIST CSF / NIST SP 800-53** — frameworks do *National Institute of Standards and
  Technology*: o **CSF** organiza a segurança em funções (Identify, Protect, Detect, Respond,
  Recover); o **800-53** é o catálogo de controles. Base de conformance packs do Config.
- **CVE** — *Common Vulnerabilities and Exposures*. Identificador único de uma
  vulnerabilidade conhecida (`CVE-2021-44228`). O **Inspector** reporta findings por CVE. → Lab 04, Lab 13
- **CVSS** — *Common Vulnerability Scoring System*. Nota 0–10 de severidade de uma CVE. O
  Inspector calcula um **score contextualizado** (ajustado por exposição de rede e
  explorabilidade), não só o CVSS base.
- **MITRE ATT&CK** — matriz pública de **táticas e técnicas** de adversários (Initial Access,
  Persistence, Privilege Escalation, Exfiltration…). GuardDuty e Detective mapeiam findings
  para táticas ATT&CK. Vocabulário de referência para descrever um ataque.
- **STRIDE** — modelo de categorias de ameaça: **S**poofing, **T**ampering, **R**epudiation,
  **I**nformation disclosure, **D**enial of service, **E**levation of privilege. Usado no
  `threat-model.md` só como tag de natureza da ameaça (o SCS-C03 não cobra STRIDE).
- **OWASP Top 10** — lista dos 10 riscos mais críticos em aplicações web (*Open Worldwide
  Application Security Project*). Alvo típico de regras de **WAF**. → Lab 11
- **OWASP Top 10 for LLM Applications** — variante para aplicações de IA generativa (prompt
  injection, insecure output handling, data poisoning…). Novidade do SCS-C03 (Tarefa 3.2.7),
  endereçada por **Bedrock Guardrails**.
- **Modelo de responsabilidade compartilhada** — *Shared Responsibility Model*. A AWS é
  responsável pela segurança **da** nuvem (hardware, hypervisor, facilities); o cliente pela
  segurança **na** nuvem (config, IAM, cripto, dados, patch de SO). A linha divisória muda
  conforme o serviço (IaaS → mais do cliente; SaaS → mais da AWS).
- **Well-Architected — Pilar de Segurança** — framework de revisão de arquitetura da AWS; o
  pilar de segurança tem as áreas identidade, detecção, proteção de infra, proteção de dados
  e resposta a incidentes. Ferramenta: **AWS Well-Architected Tool**.

## 2. Governança, postura e conformidade

- **CSPM** — *Cloud Security Posture Management* (gestão de postura de segurança na nuvem).
  Categoria de ferramenta que **avalia continuamente a configuração** dos recursos contra um
  baseline de boas práticas, mede um *security score*, detecta **drift** e acompanha o ciclo
  `FAILED → PASSED`. É o papel do **Security Hub CSPM** + **AWS Config**. → Lab 04
- **CNAPP** — *Cloud-Native Application Protection Platform*. Categoria mais ampla que junta
  CSPM + proteção de workload + correlação de vulnerabilidade/ameaça/exposição. Direção do
  **Security Hub unificado novo** (dez/2025) com seus *exposure findings*.
- **CWPP** — *Cloud Workload Protection Platform*. Proteção em nível de carga de trabalho
  (host/container/função): visibilidade de processo, arquivo e rede em runtime. Papel do
  **GuardDuty Runtime Monitoring** e do **Inspector**.
- **Security score** — percentual de controls `PASSED` sobre o total avaliado, por standard,
  no Security Hub. Métrica de tendência de postura; cai com um bucket que fica público,
  recupera com a remediação. → Lab 04
- **Drift** — desvio entre o estado **desejado** (baseline, IaC, política) e o estado
  **real** de um recurso. "Detecção de drift" = perceber que alguém abriu um SG para
  `0.0.0.0/0` fora do Terraform.
- **Config recorder** — componente do **AWS Config** que grava *configuration items* (o
  estado de cada recurso ao longo do tempo). Os security standards do Security Hub CSPM são
  **quase inertes sem um recorder rodando** para o tipo de recurso avaliado. → Lab 04, Lab 20
- **Config rule** — regra do AWS Config que avalia um recurso como `COMPLIANT` /
  `NON_COMPLIANT` / `NOT_APPLICABLE`. **Managed** (prontas da AWS) ou **custom** (Lambda /
  Guard). Podem ter **remediation** automática via SSM Automation. → Lab 20
- **Conformance pack** — coleção versionável de Config rules + remediações empacotada como um
  YAML só, para aplicar um framework inteiro (PCI, NIST, HIPAA) de uma vez. → Lab 20
- **Guardrail / barreira de proteção** — controle preventivo ou detectivo aplicado
  amplamente (org, OU, conta) para impedir ou sinalizar configuração fora da política.
  Preventivos = **SCP**; detectivos = Config rules. Vocabulário do **Control Tower**.
- **SCP** — *Service Control Policy*. Política do **AWS Organizations** que define o **teto
  de permissões** de uma conta/OU: nunca concede acesso, só limita o que IAM pode conceder.
  Não afeta a management account. → Lab 19
- **RCP** — *Resource Control Policy*. Contrapartida da SCP do lado do **recurso**: teto de
  permissões que se aplica a todo acesso a recursos (S3, SQS, KMS, Secrets Manager…) numa
  OU/conta, inclusive de principals externos. Novidade cobrada no SCS-C03. → Lab 19
- **Política declarativa** — *declarative policy*. Configuração de baseline de serviço
  aplicada pelo Organizations que **permanece imposta** mesmo para APIs novas (ex.: forçar
  IMDSv2 em toda EC2 da org). Novidade do SCS-C03. → Lab 19
- **Permission boundary** — política IAM anexada a um usuário/role que define o **máximo** de
  permissões que aquela identidade pode ter, independentemente das policies concedidas.
  Usada para delegar criação de roles com segurança. → Lab 16
- **PoLP / least privilege** — *Principle of Least Privilege*. Conceder apenas a permissão
  estritamente necessária para a tarefa, pelo menor tempo necessário. Norte dos Labs 15–16.
- **Delegated administrator** — conta membro da Organization designada para administrar um
  serviço de segurança (GuardDuty, Security Hub, Macie, IAM Access Analyzer) em nome de toda
  a org, tirando essa função da management account. → Lab 19
- **Landing zone** — ambiente multi-conta inicial, seguro e governado, provisionado de forma
  automatizada. O **AWS Control Tower** entrega uma landing zone opinativa (contas Log
  Archive e Audit, guardrails, Identity Center). → Lab 19
- **Central configuration** — modo do Security Hub/Config em que a conta de admin delegado
  define políticas (standards, controls habilitados) e o serviço as propaga para contas/OUs.
  → Lab 19
- **Trusted Advisor** — serviço que checa a conta contra boas práticas em 5 pilares (custo,
  performance, **segurança**, tolerância a falha, limites). Checks de segurança: SG abertos,
  MFA no root, buckets públicos, chaves IAM expostas.
- **Audit Manager** — coleta evidências de conformidade continuamente e as mapeia para
  frameworks (PCI, SOC 2, GDPR), gerando *assessment reports* para auditoria.
- **AWS Artifact** — portal self-service dos relatórios de conformidade **da AWS** (SOC,
  ISO 27001, PCI AoC) e dos acordos (BAA, GDPR DPA). É onde se baixa a evidência do lado
  "segurança da nuvem".
- **Security Lake** — data lake de segurança gerenciado que centraliza logs de várias contas/
  fontes, **normalizados em OCSF** e particionados em S3/Parquet, consultáveis por Athena/
  parceiros. → Lab 05

## 3. Detecção de ameaças

- **Finding** — descoberta de segurança: um registro estruturado de "algo digno de atenção
  aconteceu / está configurado errado". Unidade de trabalho do GuardDuty, Inspector, Macie,
  Security Hub e Config.
- **IoC** — *Indicator of Compromise* (indicador de comprometimento). Artefato observável que
  sugere intrusão **já ocorrida**: IP/domínio de C2 conhecido, hash de malware, chave de
  registro. Alimenta *threat lists*.
- **IoA** — *Indicator of Attack* (indicador de ataque). Foco no **comportamento em
  andamento** (padrão de recon, escalonamento), não no artefato. GuardDuty combina os dois.
- **TTP** — *Tactics, Techniques, and Procedures*. O "como" de um adversário — o modus
  operandi. Vocabulário do **MITRE ATT&CK**.
- **C2 / C&C** — *Command and Control* (comando e controle). Canal pelo qual o atacante
  opera um host comprometido (recebe ordens, exfiltra). GuardDuty:
  `Backdoor:EC2/C&CActivity.B!DNS`. Exercitado no Lab 03 (TS-007). → Lab 03
- **Baseline de ML** — modelo de comportamento "normal" que o GuardDuty leva **~7–14 dias**
  para formar **por detector**. Findings de anomalia (`InstanceCredentialExfiltration`,
  `Discovery:S3/AnomalousBehavior`) dependem dele — daí manter o detector **persistente**
  (ADR-015). → Lab 03
- **Detector** — a instância regional do GuardDuty; habilitá-lo é o que liga o serviço numa
  região. GuardDuty é **regional**: um detector por região a monitorar. → Lab 03, TM-10
- **Feature / data source** — as fontes que um detector do GuardDuty consome: CloudTrail
  management events, VPC Flow Logs e DNS logs (sempre, sem custo de ingestão à parte) +
  S3 data events, EKS audit logs, Malware Protection, RDS/Aurora login, Lambda network,
  Runtime Monitoring (opcionais). → Lab 03
- **Threat list / trusted IP list** — listas customizadas no GuardDuty: a **threat list**
  (IPs/domínios) gera finding em qualquer contato; a **trusted IP list** suprime findings de
  IPs que você sabe serem seus.
- **Suppression rule** — filtro no GuardDuty que **auto-arquiva** (`RecordState: ARCHIVED`)
  findings que casam um critério, sem apagá-los. Legítima para ruído; abusada por um atacante
  para esconder o próprio finding. Exercitada no TS-007. → Lab 03, TM-10
- **Automation rule** — regra do **Security Hub CSPM** que altera campos de findings na
  ingestão (mudar severidade, `Workflow.Status = SUPPRESSED`, adicionar nota) por `Criteria`
  + `RuleOrder` + `IsTerminal`. Análoga à suppression rule, do lado do Hub. Exercitada no
  TS-010. → Lab 04
- **Insight** — no GuardDuty/Security Hub, um agrupamento salvo de findings por atributo
  comum ("todos os findings por recurso X", "buckets com acesso anônimo") — uma consulta
  nomeada para triagem.
- **SIEM** — *Security Information and Event Management*. Plataforma que centraliza,
  correlaciona e alerta sobre logs de segurança. Papel montado com **Security Lake + Athena/
  OpenSearch** ou parceiro. → Lab 06
- **SOAR** — *Security Orchestration, Automation and Response*. Automação de playbooks de
  resposta (enriquecer, conter, notificar). Papel de **EventBridge + Lambda/Step Functions +
  SSM Automation**. → Lab 09
- **EDR / XDR** — *Endpoint / Extended Detection and Response*. Detecção+resposta em nível de
  endpoint (EDR) ou correlacionando múltiplas camadas (XDR). Equivalente AWS: **GuardDuty
  Runtime Monitoring** (agente eBPF) + Security Hub como correlação. → Lab 13
- **Malware Protection** — feature do GuardDuty que dispara um scan **agentless** de volumes
  EBS (on-demand ou ao gerar um finding de EC2) e de objetos recém-carregados no S3.
- **Runtime Monitoring** — feature do GuardDuty com **agente** (add-on eBPF) que dá
  visibilidade de processo/arquivo/rede dentro de EC2, ECS e EKS. → Lab 13
- **Detective / behavior graph** — o **Amazon Detective** ingere CloudTrail, Flow Logs e
  findings do GuardDuty e monta um **grafo de comportamento** (entidades e relações ao longo
  do tempo) para investigar o "escopo e impacto" de um finding sem montar queries à mão. → Lab 10
- **Exposure finding** — no Security Hub unificado novo: finding **correlacionado** que junta
  uma vulnerabilidade (Inspector) + exposição de rede + finding de ameaça (GuardDuty) num
  caminho de ataque priorizado.
- **Falso positivo / falso negativo** — finding que aponta ameaça onde não há (FP) / ameaça
  real que passou sem finding (FN). Ajustar `Criteria` de suppression/automation rules é o
  trade-off entre os dois.
- **User Notifications** — *AWS User Notifications*. Serviço que centraliza a entrega de
  notificações (inclusive de findings de segurança) por e-mail, chat e console, com regras de
  agregação — alternativa gerenciada ao par EventBridge→SNS.

## 4. Resposta a incidentes e forense

- **Playbook / runbook** — roteiro de resposta a um tipo de incidente. **Playbook** =
  procedimento de decisão (mais humano); **runbook** = passos executáveis (mais automação).
  → Lab 08
- **Containment / isolamento** — primeira ação de contenção: cortar o alcance do recurso
  comprometido sem destruí-lo (trocar o SG por um "quarantine SG" sem regras, tirar de um
  ELB, revogar sessões IAM). → Lab 09
- **Quarantine** — estado intermediário do recurso contido: isolado da rede e das
  identidades, **preservado** para análise (não terminado). Geralmente um SG e uma NACL
  dedicados + tag.
- **Cadeia de custódia** — *chain of custody*. Registro íntegro de quem tocou em qual
  evidência, quando e como, para que ela seja admissível. Na AWS: snapshots EBS com tags e
  hash, cópia para uma conta forense, S3 Object Lock. → Lab 10
- **Conta forense** — conta AWS isolada e endurecida, sem acesso do time de operação, onde
  cópias de evidência (snapshots, logs) são analisadas sem risco de contaminar ou alertar o
  atacante. → Lab 10
- **Disk imaging / memory acquisition** — captura da imagem do disco (snapshot EBS →
  volume na conta forense) e da **memória volátil** (via SSM antes de parar a instância).
  Ordem importa: memória primeiro (mais volátil).
- **Automated Forensics Orchestrator** — solução de referência da AWS (Step Functions) que
  automatiza aquisição de disco+memória, isolamento e triagem de uma EC2 ao receber um
  finding. → Lab 10
- **MTTD / MTTR** — *Mean Time To Detect / Respond*. Métricas de eficácia do programa de
  detecção/resposta. `finding_publishing_frequency = FIFTEEN_MINUTES` (ADR-018) ataca o MTTD.
- **Dwell time** — tempo entre o comprometimento inicial e a detecção. Janela em que o
  atacante opera sem ser visto.
- **Break-glass / conta root** — procedimento de emergência com uma credencial de altíssimo
  privilégio (frequentemente o **root** da conta), guardada offline com MFA, usada só quando
  o caminho normal (SSO) está indisponível. Uso gera alarme (implementado no Lab 02, TM-08).
- **Centralização do acesso root** — recurso do Organizations que **remove as credenciais de
  root** das contas membro e permite executar as poucas tarefas que exigem root a partir da
  management account, sob demanda. Novidade do SCS-C03. → Lab 19

## 5. Vocabulário do adversário (técnicas de ataque)

- **IMDS / IMDSv2** — *Instance Metadata Service*. Endpoint `169.254.169.254` de onde a EC2
  lê as **credenciais temporárias** da sua IAM Role. **IMDSv2** exige uma sessão com token
  (`PUT` + header, TTL, sem redirect) — mitiga roubo via **SSRF**. Alvo do TM-02. → Lab 13
- **SSRF** — *Server-Side Request Forgery*. A aplicação é induzida a fazer requisições em
  nome do atacante; o alvo clássico na AWS é o **IMDS** para exfiltrar credenciais da role.
- **Credential exfiltration** — roubar credenciais (chaves estáticas, token STS do IMDS,
  cache do SSO) e usá-las de fora. GuardDuty:
  `UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration`. TM-02.
- **Privilege escalation** — a partir de um acesso limitado, obter mais privilégio:
  `iam:PassRole` amplo, `iam:CreatePolicyVersion`, anexar policy a role própria,
  `sts:AssumeRole` sem escopo. GuardDuty: `PrivilegeEscalation:IAMUser/*`. TM-05. → Lab 15
- **Lateral movement** — mover-se de um recurso comprometido para outro (assumir outra role,
  pivotar via peering/VPN, reusar credencial). Detecção: Detective, Flow Logs.
- **Confused deputy** — um serviço com mais privilégio é enganado por um terceiro para agir
  em nome dele contra recursos que o terceiro não poderia tocar. Mitigação: `aws:SourceArn` /
  `aws:SourceAccount` na trust policy, ou **`ExternalId`** em roles cross-account. → Lab 16
- **Data exfiltration** — retirar dados do ambiente: `GetObject` em massa, cópia para bucket
  externo, túnel DNS, via credencial roubada. TM-06. Detecção: Flow Logs `ALL`,
  `Exfiltration:S3/*`, Macie. → Lab 07
- **Anti-forensics / defense evasion** — apagar o rastro: `StopLogging`, `DeleteTrail`,
  apagar objetos do log bucket, `DeleteDetector`, criar suppression rule, operar em região
  não monitorada. TM-07, TM-10. Mitigação: CloudTrail multi-region, log bucket fora do state
  (ADR-009), Object Lock. → Lab 18, Lab 19
- **Living off the land** — usar ferramentas/credenciais **legítimas** já presentes (AWS CLI,
  a própria IAM Role, SSM) em vez de trazer malware — reduz a superfície de detecção.
- **Cryptojacking / cryptomining** — sequestrar compute para minerar criptomoeda; corrói o
  teto de custo (TM-11). GuardDuty: `CryptoCurrency:EC2/BitcoinTool.B*`. → Lab 03
- **Recon** — fase de reconhecimento: enumerar permissões, listar buckets/roles, port
  scanning. GuardDuty: `Recon:IAMUser/*`, `Recon:EC2/PortProbeUnprotectedPort`.
- **Blast radius** — extensão do estrago se um dado ativo/identidade for comprometido.
  Reduzi-lo = segmentar rede, escopar roles, separar contas.

## 6. Identidade e acesso

- **STS** — *Security Token Service*. Emite **credenciais temporárias** (access key + secret
  + session token, com expiração). Base de todo acesso sem chave estática no projeto
  (ADR-006). → Lab 01
- **AssumeRole** — chamada STS que troca a identidade atual por uma **role**, recebendo
  credenciais temporárias dela. Variantes: `AssumeRoleWithSAML` (federação SAML),
  `AssumeRoleWithWebIdentity` (OIDC — Cognito, IRSA no EKS, GitHub Actions).
- **Trust policy** — *assume-role policy document*. A policy **anexada à role** que diz
  **quem pode assumi-la** (`Principal`) e sob quais condições. É resource-based. Distinta da
  policy de permissões da role.
- **Identity-based vs resource-based policy** — policy anexada a **quem** age (user/group/
  role) vs policy anexada ao **recurso** (bucket policy, key policy, SQS policy). Acesso
  cross-account normalmente exige as duas pontas.
- **Session policy** — policy passada **no momento** do `AssumeRole`/`GetFederationToken`
  que **restringe ainda mais** a sessão resultante (nunca amplia). Usada por brokers de
  acesso.
- **Boundary vs SCP vs session policy vs identity policy** — as camadas da lógica de
  avaliação: o acesso efetivo é a **interseção** de (SCP/RCP) ∩ (permission boundary) ∩
  (session policy) ∩ (identity + resource policy), e qualquer **`Deny` explícito** ganha de
  tudo. → Lab 16
- **Permission set** — no **IAM Identity Center**, o template de permissões (policies
  gerenciadas + inline + boundary + duração de sessão) que, atribuído a (usuário/grupo ×
  conta), materializa uma IAM Role provisionada naquela conta. → Lab 01, Lab 15
- **ABAC** — *Attribute-Based Access Control*. Autorização por **tags/atributos**
  (`aws:PrincipalTag`, `aws:ResourceTag`, `aws:TagKeys`) em vez de policy por recurso
  nomeado. Escala sem reescrever policy a cada recurso novo. → Lab 16
- **RBAC** — *Role-Based Access Control*. Autorização por **papel/função** — o modelo
  tradicional de policy anexada a grupos/roles nomeados.
- **PassRole** — `iam:PassRole`: permissão de **entregar uma role a um serviço** (dar uma
  instance profile a uma EC2, uma execution role a uma Lambda). `PassRole` amplo é vetor de
  escalonamento — deve ser escopado por `iam:PassedToService` e ARN. TM-05.
- **Service-linked role (SLR)** — role predefinida, **de propriedade de um serviço AWS**
  (GuardDuty, Config, Security Hub, Inspector), que o serviço cria/usa para agir na sua
  conta. Trust policy fixa; permissões gerenciadas pela AWS.
- **Instance profile** — o "contêiner" que anexa uma IAM Role a uma instância EC2, para o
  código na instância obter credenciais via IMDS **sem chave estática**. → Lab 01
- **IdP** — *Identity Provider*. Fonte de verdade de identidade externa (Entra ID, Okta,
  Google) integrada ao IAM Identity Center ou ao Cognito. → Lab 14
- **SAML 2.0** — protocolo XML de asserção de identidade para **federação web SSO** com a
  AWS (console via `AssumeRoleWithSAML`).
- **OIDC** — *OpenID Connect*. Camada de identidade sobre OAuth 2.0, baseada em JWT. Usada
  para federar cargas de trabalho (GitHub Actions → AWS, IRSA no EKS) sem chave estática.
- **SCIM** — *System for Cross-domain Identity Management*. Protocolo de
  **provisionamento/desprovisionamento automático** de usuários e grupos do IdP para o
  Identity Center.
- **MFA** — *Multi-Factor Authentication*. Segundo fator (TOTP, FIDO2/passkey, hardware) além
  da senha. Condição `aws:MultiFactorAuthPresent` em policies. Obrigatória no root e no
  login do Identity Center.
- **JIT access** — *Just-In-Time access*. Conceder privilégio elevado só **no momento e pelo
  tempo** da tarefa, com aprovação e expiração automática, em vez de acesso permanente. → Lab 16
- **IAM Access Analyzer** — analisa policies para achar **acesso externo** (recurso
  compartilhado fora da conta/org), **acesso não usado** (permissões/roles ociosas), e
  **valida** policy contra as boas práticas; também gera policy a partir da atividade do
  CloudTrail. → Lab 15
- **Policy Simulator** — ferramenta que avalia "esta ação neste recurso, para este
  principal, seria `Allow` ou `Deny`?" sem executar de verdade. → Lab 15
- **Cognito user pool vs identity pool** — **user pool** = diretório de usuários da
  aplicação (login, tokens JWT); **identity pool (federated identities)** = troca um token
  (do user pool ou de um IdP) por **credenciais AWS temporárias** para acessar serviços.
- **Verified Permissions** — serviço de autorização **fine-grained** para aplicações,
  baseado na linguagem de policy **Cedar** (externaliza o "quem pode fazer o quê" da app).

## 7. Criptografia e gestão de chaves

- **KMS** — *Key Management Service*. Serviço gerenciado de chaves; as operações
  criptográficas acontecem dentro de HSMs validados FIPS 140 e a chave **nunca sai** em
  claro. → Lab 17
- **CMK** — *Customer Managed Key*. Chave KMS **criada e controlada pelo cliente** (com
  **key policy** própria, rotação configurável, habilita/desabilita). Contrasta com
  **AWS managed key** (`aws/s3`, `aws/ebs` — policy fixa, rotação automática, sem custo de
  chave) e **AWS owned key** (invisível, compartilhada entre contas). → Lab 17
- **Key policy** — a **resource-based policy da chave KMS**; é a autoridade primária sobre
  quem usa/administra a chave. Sem um statement que dê acesso à conta ou a um principal,
  IAM sozinho não concede nada na chave. Permite separar "quem administra" de "quem
  decripta" (ADR-013). → Lab 17
- **Grant** — concessão **programática, temporária e granular** de uso de uma chave KMS a um
  principal (típico: um serviço AWS que precisa cifrar/decifrar em nome do cliente).
  Alternativa à key policy para acesso efêmero; pode ser revogada.
- **Envelope encryption** — cifrar os dados com uma **data key** e então cifrar essa data key
  com a **CMK** (KMS). Só a data key cifrada viaja junto do dado; o KMS só é chamado para
  decifrar a data key (uma chamada pequena), não o dado inteiro. → Lab 17
- **DEK / KEK** — *Data Encryption Key* (cifra o dado) / *Key Encryption Key* (cifra a DEK).
  A CMK do KMS é a KEK.
- **Rotação de chave** — troca do **material criptográfico** da CMK. **Automática** (a cada
  ~1 ano, o KMS mantém as versões antigas para decifrar dados legados) ou **on-demand**. Não
  muda o ARN/ID da chave.
- **Material de chave importado (EXTERNAL)** — CMK criada com `Origin = EXTERNAL`: o cliente
  **fornece o material** e é responsável por guardá-lo (o KMS não consegue recriar). Base do
  **BYOK**. Cai no SCS-C03 a diferença para material gerado pela AWS.
- **XKS** — *External Key Store*. *Custom key store* apoiado em um **HSM/keystore fora da
  AWS**: as operações de cripto usam material que **nunca entra** na AWS, via um proxy XKS.
  Controle máximo, latência e disponibilidade por conta do cliente.
- **Custom key store (CloudHSM-backed)** — *custom key store* em que as CMKs são geradas e
  usadas dentro de um **cluster CloudHSM** de single-tenant do cliente, em vez do KMS
  multi-tenant.
- **CloudHSM** — *Hardware Security Module* dedicado e single-tenant, sob controle exclusivo
  do cliente (FIPS 140-2 nível 3). Para quando há exigência regulatória de posse do HSM ou
  de algoritmos que o KMS não expõe.
- **Multi-Region key** — conjunto de CMKs KMS em regiões diferentes com o **mesmo material** e
  o mesmo key ID, para cifrar numa região e decifrar em outra (DR, dados replicados) sem
  chamada cross-region. → Lab 17
- **Encryption context** — par(es) chave-valor AAD (*Additional Authenticated Data*) passados
  numa operação KMS: não são segredos, mas a decifragem **falha** se não forem reproduzidos
  iguais, e aparecem no CloudTrail. Amarra o ciphertext a um contexto.
- **`kms:ViaService`** — condição de key policy que só permite usar a chave **através de um
  serviço específico** (`s3.us-east-1.amazonaws.com`), não diretamente pela API do KMS.
- **SSE-S3 / SSE-KMS / DSSE-KMS / SSE-C** — *Server-Side Encryption* no S3: **S3** = chaves
  gerenciadas pelo S3 (AES-256, sem custo, sem controle); **KMS** = envelope encryption com
  uma CMK (auditável, key policy); **DSSE-KMS** = **dupla** camada KMS (exigência de alguns
  reguladores); **C** = cliente fornece a chave em cada request, S3 não a guarda.
- **S3 Bucket Key** — cache de nível de bucket de uma data key do KMS que **reduz as chamadas
  ao KMS** (e o custo) em buckets com muito objeto SSE-KMS.
- **CSE** — *Client-Side Encryption*. Os dados são cifrados **antes** de saírem do cliente; o
  serviço AWS só vê ciphertext. Máximo controle, mas gestão de chave 100% do cliente.
- **ACM** — *AWS Certificate Manager*. Provisiona e **renova automaticamente** certificados
  TLS públicos para uso em recursos integrados (ALB, CloudFront, API Gateway). A chave
  privada não é exportável. → Lab 11
- **ACM PCA** — *AWS Private Certificate Authority*. CA privada gerenciada para emitir
  certificados **internos** (mTLS entre serviços, dispositivos, VPN). → Lab 14
- **Secrets Manager** — armazém de segredos com **rotação automática** via Lambda e
  integração com RDS/Redshift/DocumentDB. Contrasta com **SSM Parameter Store `SecureString`**
  (mais simples, sem rotação nativa, cifrado por KMS). → Lab 18
- **Nitro System / Nitro Enclaves** — o **Nitro** isola virtualização em hardware dedicado e
  garante que ninguém (nem a AWS) acessa a memória/dados da instância. **Enclaves** = ambiente
  de execução isolado, sem rede nem storage persistente nem shell, para processar dados
  sensíveis (attestation via KMS). Novidade do SCS-C03 (cripto Nitro).

## 8. Proteção de dados

- **Macie** — descoberta de **dados sensíveis** em S3 por ML + regex: identifica PII, chaves,
  credenciais, e avalia postura dos buckets (público, não cifrado, compartilhado). → Lab 07
- **Managed data identifier** — detector pronto do Macie para um tipo de dado sensível
  (número de cartão, CPF, chave AWS). **Custom data identifier** = regex + palavras-âncora
  do cliente.
- **DLP** — *Data Loss Prevention*. Categoria de controle que impede vazamento de dado
  sensível. Na AWS, montado com Macie (descoberta) + políticas de bucket/RCP + Flow Logs/
  GuardDuty (exfiltração). → Lab 07
- **Data masking / redaction** — ocultar campos sensíveis na saída. **CloudWatch Logs data
  protection policy** e **SNS message data protection** mascaram PII automaticamente por
  data identifier. Novidade do SCS-C03 (Tarefa 5.3.4).
- **Tokenization** — substituir o dado sensível por um **token** sem valor fora de um cofre
  de mapeamento (mais forte que masking para uso persistente; PCI).
- **Block Public Access (BPA)** — quatro flags no S3 (`BlockPublicAcls`, `IgnorePublicAcls`,
  `BlockPublicPolicy`, `RestrictPublicBuckets`) que **vetam** exposição pública por ACL ou
  policy, no nível de conta ou de bucket. Ligado por padrão no projeto. TM-04. → Lab 04
- **S3 Object Lock / WORM** — *Write Once Read Many*. Impede deletar/sobrescrever uma versão
  de objeto por um período. **Governance mode** (um privilégio especial pode remover) vs
  **Compliance mode** (ninguém, nem o root, até expirar). Base de retenção de evidência. → Lab 18
- **MFA Delete** — no S3 versionado, exige um código MFA para **excluir permanentemente uma
  versão** ou desligar o versionamento. Só configurável pela conta root. TM-07.
- **Pre-signed URL** — *URL predefinido*. URL temporário e assinado que concede acesso a um
  objeto S3 (ou operação) **sem** o portador ter credenciais AWS. Herda as permissões de quem
  assinou; expira. → Lab 04 (via STS)
- **Data perimeter** — conjunto de guardrails (SCP/RCP + VPC endpoint policies + condições
  `aws:PrincipalOrgID`, `aws:ResourceOrgID`, `aws:SourceVpc`) que garante que **só
  identidades confiáveis** acessem **só recursos confiáveis** a partir de **redes
  confiáveis**. → Lab 19
- **Backup / cofre imutável** — *AWS Backup* com **Vault Lock** (WORM no backup) e cópias
  cross-account/cross-region: proteção contra ransomware e contra o próprio operador
  comprometido. → Lab 18

## 9. Segurança de rede e borda

- **WAF** — *Web Application Firewall*. Filtra HTTP(S) na camada 7 em CloudFront / ALB /
  API Gateway, por **Web ACL** com regras (SQLi, XSS, IP set, geo, rate-based, managed rule
  groups). → Lab 11
- **Managed rule group** — conjunto de regras WAF mantido pela AWS ou por um parceiro do
  Marketplace (Core rule set, Known bad inputs, Anonymous IP list). SCS-C03: "regras WAF de
  terceiros".
- **Rate-based rule** — regra de WAF que bloqueia um IP (ou chave de agregação) que exceda N
  requests numa janela — mitigação de brute force e DDoS L7.
- **Shield / Shield Advanced** — **Shield Standard** (grátis, automático) protege contra DDoS
  volumétrico L3/L4. **Shield Advanced** (pago) adiciona proteção L7, o **SRT** (Shield
  Response Team), *cost protection* e visibilidade de ataque. → Lab 11
- **DDoS L3/L4 vs L7** — *Distributed Denial of Service*: **L3/L4** = inundar banda/conexões
  (SYN flood, UDP reflection) — Shield/arquitetura; **L7** = exaurir a aplicação com requests
  "válidos" (HTTP flood) — WAF rate-based + Shield Advanced.
- **Firewall Manager** — aplica e **audita centralmente** políticas de WAF, Shield Advanced,
  grupos de segurança e Network Firewall em **todas as contas** da Organization. → Lab 19
- **Network Firewall** — firewall de rede **stateful** gerenciado, na VPC, com regras
  próprias ou no formato **Suricata** (IPS/IDS, filtragem de domínio, TLS SNI). Faz o
  **egress filtering** que um SG não faz. → Lab 12
- **Route 53 Resolver DNS Firewall** — bloqueia/monitora **consultas DNS** da VPC contra
  listas de domínios (C2, exfiltração por DNS, newly-registered domains). Complementa o
  GuardDuty DNS. → Lab 12
- **Security group (stateful) vs Network ACL (stateless)** — **SG**: anexado à ENI, só
  regras de `allow`, **stateful** (a resposta é liberada automaticamente); **NACL**: na
  sub-rede, `allow` **e** `deny`, **stateless** (precisa liberar ida **e** volta, atenção às
  portas efêmeras). Diferença muito cobrada no exame.
- **VPC endpoint (Gateway vs Interface) + endpoint policy** — acesso privado a serviços AWS
  **sem** passar pela internet/NAT. **Gateway** (S3, DynamoDB — rota, grátis); **Interface**
  (ENI + PrivateLink, por hora). A **endpoint policy** é uma resource-policy que restringe o
  que pode ser feito **através daquele endpoint** (ex.: só buckets da minha conta). ADR-003. → Lab 01
- **PrivateLink** — expõe um serviço (seu ou de um parceiro) como uma **Interface Endpoint**
  na VPC do consumidor, sem peering, sem rota para a internet, tráfego só pela rede AWS. → Lab 14
- **VPC Verified Access** — *AWS Verified Access*. Acesso a aplicações internas **sem VPN**,
  avaliando **cada request** contra política Cedar + sinais de identidade (IdP) e de postura
  do dispositivo (Zero Trust). → Lab 14
- **mTLS** — *mutual TLS*. Autenticação **dos dois lados** da conexão por certificado
  (cliente **e** servidor). Suportado em API Gateway, ALB, App Mesh; certificados de cliente
  via ACM PCA. → Lab 14
- **Geo match / geo blocking** — regra (WAF ou CloudFront) que permite/bloqueia por país de
  origem do request.
- **Egress filtering** — controlar **o tráfego de saída** da VPC por destino (domínio/IP/
  porta), não só o de entrada. SG e NACL são fracos nisso; o trabalho é do Network Firewall /
  DNS Firewall / proxy. Fecha o TM-03. → Lab 12
- **Reachability Analyzer / Network Access Analyzer** — **Reachability**: prova se existe um
  caminho de rede entre A e B e mostra o hop que bloqueia. **Network Access Analyzer**:
  encontra **caminhos não intencionais** para a internet / entre segmentos, contra um escopo
  declarado. → Lab 12
- **CloudFront OAC** — *Origin Access Control*. Faz o bucket S3 de origem aceitar requests
  **só do CloudFront** (request assinado SigV4), mantendo o bucket privado. Sucessor do OAI.
  → Lab 11
- **Zero Trust** — modelo em que **nenhuma rede é confiável por padrão**: toda requisição é
  autenticada, autorizada e cifrada, com decisão por identidade + contexto, não por estar
  "dentro". Materializado por Verified Access, PrivateLink, data perimeter.

## Registro de revisões

| Data | Versão | Escopo | Mudança |
|---|---|---|---|
| 2026-08-31 | v1 | Labs 01–04 + guia SCS-C03 | Criação: 9 seções (formatos/frameworks, governança, detecção, resposta/forense, vocabulário de ataque, identidade, criptografia, proteção de dados, rede/borda), ~130 termos. Cross-refs para os labs onde cada termo é exercitado. |

**Ao fechar cada lab futuro:** adicionar os termos novos que o lab introduz na seção
correspondente, com o marcador `→ Lab NN`, e registrar aqui.
