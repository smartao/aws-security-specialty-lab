# Decisions Log (ADR)

Registro das decisões arquiteturais do projeto, no formato problema → alternativas → decisão → motivo → trade-offs. Uma entrada por decisão relevante, em ordem cronológica.

---

## ADR-001 — Segmentação em 3 camadas de subnet

**Lab:** 01 — Secure AWS Foundation
**Status:** Aceito

**Contexto:** a fundação vai hospedar, ao longo dos labs, workloads de aplicação (EC2) e dados sensíveis (S3, futuramente RDS). Um desenho de apenas pública/privada colocaria dados no mesmo nível de rede de uma aplicação que ainda precisa de saída para a internet (patches, chamadas externas).

**Decisão:** 3 camadas por AZ — pública (edge), privada (aplicação, com rota via NAT) e isolada (dados, sem rota externa nenhuma, nem via NAT).

**Alternativas consideradas:** 2 camadas (pública/privada), com dados na mesma subnet privada da aplicação.

**Trade-offs:** mais subnets e route tables para gerenciar, mas elimina por completo a possibilidade de exfiltração de dados via rota de internet a partir da camada de dados — o controle vira estrutural (rede), não apenas uma policy que pode ser mal configurada.

---

## ADR-002 — NAT Gateway único compartilhado entre AZs

**Lab:** 01
**Status:** Aceito

**Contexto:** alta disponibilidade completa pede 1 NAT Gateway por AZ, mas cada NAT Gateway custa ~US$ 0,045/h só de existir, independentemente de uso — e este projeto tem um teto de **US$ 100 para 6 meses** (não mensal).

**Decisão:** um único NAT Gateway (em Public-A), compartilhado pelas subnets privadas das duas AZs.

**Alternativas consideradas:** 1 NAT Gateway por AZ (padrão de produção).

**Trade-offs:** se a AZ-a cair, a AZ-b perde apenas o *egress* para a internet — as instâncias continuam operando entre si (SG, rotas internas). Não é perda de HA da aplicação, é perda de HA do egress, aceita conscientemente para um ambiente de estudo.

**Efeito colateral positivo:** como as duas subnets privadas apontam para o mesmo NAT, elas também compartilham a mesma route table — 3 route tables no total (pública/privada/isolada), não 6.

---

## ADR-003 — VPC Gateway Endpoint para S3

**Lab:** 01
**Status:** Aceito

**Contexto:** sem esse componente, o tráfego EC2 → S3 (autorizado via IAM Role) sairia pela subnet privada, atravessaria o NAT Gateway e a internet pública para alcançar um serviço que é 100% AWS-para-AWS — gerando custo de processamento de NAT desnecessário e uma superfície de rede maior que o necessário.

**Decisão:** VPC Gateway Endpoint para S3 (entrada de route table, sem custo adicional), com endpoint policy restringindo o acesso.

**Alternativas consideradas:** deixar o tráfego passar pelo NAT Gateway normalmente.

**Trade-offs:** nenhum trade-off relevante — Gateway Endpoints para S3/DynamoDB são gratuitos. Reduz custo de NAT e adiciona uma camada extra de controle (endpoint policy) além do IAM.

---

## ADR-004 — Terraform: backend S3 com lock nativo + SSM Parameter Store entre labs

**Lab:** 01 (decisão vale para todo o projeto)
**Status:** Aceito

**Contexto:** o Lab 01 é a fundação reaproveitada pelos 19 labs seguintes. Perder o state local seria equivalente a perder o rastro de toda a infraestrutura existente na conta. Além disso, os labs seguintes precisam consumir outputs do Lab 01 (VPC ID, subnet IDs), e o Lab 01 será destruído/recriado a cada sessão de estudo por causa de custo.

**Decisão:**

- Backend remoto em S3, com locking nativo via conditional writes (`use_lockfile = true`, Terraform 1.10+) — sem tabela DynamoDB.
- O bucket do backend é criado uma única vez fora do ciclo de vida de qualquer lab (bootstrap) e nunca é destruído.
- Labs consomem outputs uns dos outros via **SSM Parameter Store** (`/lab01/...`), não via `terraform_remote_state`. Prefixo não pode ser `/awssec/lab01/...` como planejado originalmente — `awssec` colide com o prefixo reservado `aws*` do SSM Parameter Store (ver TS-003 em `docs/troubleshooting.md`).

**Alternativas consideradas:**

- State local (descartado: risco de perda para uma fundação reutilizada por 19 labs).
- DynamoDB para lock (descartado: redundante desde o locking nativo do S3).
- `terraform_remote_state` para consumir outputs do Lab 01 (descartado: expõe o state inteiro do Lab 01 — que pode conter atributos sensíveis — a todo lab downstream).

**Trade-offs:** SSM Parameter Store desacopla os labs (Lab 02 nem precisa saber que existe Terraform/state por trás do Lab 01) e expõe só os valores que o Lab 01 decide publicar — mesmo princípio de exposição mínima aplicado em outras decisões deste projeto (IAM Role em vez de credencial estática, subnet isolada para dados). Como consequência, recriar o Lab 01 a cada sessão de estudo não exige nenhuma atualização manual nos labs seguintes.

---

## ADR-005 — Naming convention "projeto primeiro", sem token de ambiente no nome

**Lab:** 01 (decisão vale para todo o projeto)
**Status:** Aceito

**Contexto:** o projeto terá dezenas de recursos por lab, espalhados por 20 labs. Era preciso um padrão único desde o início.

**Decisão:** `{projeto}-{lab}-{tipo-recurso}-{detalhe}[-{az}]`, ex: `awssec-lab01-subnet-public-a`. "Ambiente" não entra no nome — vive apenas como tag (`Environment = study`), porque neste projeto todo recurso pertence ao mesmo ambiente de estudo; um token fixo no nome seria redundante.

**Alternativas consideradas:** ordenação "lab primeiro" (`lab01-awssec-...`); inclusão de um token de ambiente explícito no nome (`awssec-study-lab01-...`).

**Trade-offs:** ordenação "projeto primeiro" agrupa todos os recursos do projeto no console mesmo que a conta AWS cresça com outros usos no futuro — considerado mais importante que agrupar por lab individual.

---

## ADR-006 — Autenticação humana via IAM Identity Center (SSO), não IAM user

**Lab:** 01 (decisão vale para todo o projeto)
**Status:** Aceito e validado

**Contexto:** o projeto define "zero credenciais estáticas" como requisito para as EC2 (IAM Role + Instance Profile). Autenticar o operador humano via IAM user com access key de longa duração contradiria esse mesmo princípio aplicado a si mesmo.

**Decisão:** IAM Identity Center em modo **Account instance** (sem exigir AWS Organizations, adequado a uma conta avulsa), com autenticação via `aws sso login`, gerando credenciais STS temporárias para AWS CLI e Terraform via profile nomeado.

**Alternativas consideradas:** IAM user com access key estática (`aws configure` tradicional).

**Trade-offs:** exige um setup inicial único (~15 min) no console e um `aws sso login` no início de cada sessão de estudo — fricção mínima e que, na prática, combina bem com o padrão de "sessão de estudo → destroy ao final".

**Validação:** `aws sts get-caller-identity` confirmou `assumed-role/AWSReservedSSO_AdministratorAccess_<hash>/sergei` — prova concreta de que o mecanismo por trás do SSO é `sts:AssumeRole`, não uma credencial estática, e que o *session name* preserva a identidade individual para fins de auditoria futura (CloudTrail, a partir do Lab 02).

---

## ADR-007 — Cleanup por sessão de estudo + AWS Budget

**Lab:** 01 (decisão vale para todo o projeto)
**Status:** Aceito

**Contexto:** teto de custo do projeto é **US$ 100 para 6 meses** (absoluto, não mensal). Deixar a fundação (com NAT Gateway) sempre de pé consumiria esse teto de forma constante independentemente do ritmo real de estudo.

**Decisão:** `terraform destroy` da fundação ao final de toda sessão de estudo, com reaplicação no início da próxima (viável sem retrabalho manual graças à ADR-004). Configurar um AWS Budget de US$ 100 com alertas em 50/80/100% como rede de segurança.

**Alternativas consideradas:** manter a fundação sempre ativa pelos meses de duração do projeto.

**Trade-offs:** esforço de reaplicar a cada sessão, em troca de eliminar o custo fixo do NAT Gateway (~US$ 32/mês) nos períodos sem estudo ativo.

**Atualização (2026-08-25) — Budget revisado após perda do Free Tier:** ao ativar o IAM Identity Center como *organization instance* (ver [ADR-006](#adr-006--autenticação-humana-via-iam-identity-center-sso-não-iam-user)), a conta passou a ser management account de uma AWS Organization — um dos gatilhos oficiais de upgrade automático de Free Plan para Paid Plan. A conta 230650392331 recebeu o email de upgrade em 2026-08-25. Com isso, o buffer do Free Tier que sustentava a suposição original (custo ~$0 fora dos componentes intencionais como o NAT Gateway) deixa de existir — qualquer uso passa a ser cobrado desde o primeiro centavo.

Diante disso, o desenho do Budget foi simplificado: em vez do teto absoluto de US$ 100/6 meses com alertas em 50/80/100% (que exigiria `TimeUnit=ANNUALLY` com `TimePeriod` limitado, para não resetar mensalmente), optou-se por um **AWS Budget mensal simples** — `awssec-monthly-budget`, limite de US$ 10/mês, notificações `ACTUAL`/`ABSOLUTE_VALUE` em US$ 5 e US$ 10. Prioriza detectar drift de gasto cedo (mensal, resposta rápida) sobre modelar com precisão o teto absoluto do projeto. O teto de US$ 100/6 meses continua valendo como limite real do projeto (ver seção de custos de cada lab), só não é mais o que o Budget da AWS modela diretamente.

Criado via CLI, fora do state de qualquer lab (mesmo padrão do bucket de backend e do bucket de logs — ver [setup-budget.md](setup-budget.md)).

---

## ADR-008 — Terraform: root module único no Lab 01, sem `terraform/modules/` ainda

**Lab:** 01 (decisão vale para todo o projeto até que a condição de extração apareça)
**Status:** Aceito

**Contexto:** o planejamento original (seção Implementação do README do Lab 01) previa módulos reutilizáveis desde o início (`vpc`, `iam-role-ec2`, `security-group`). Na prática, dentro do Lab 01, cada componente (VPC, Security Group, IAM Role, EC2, S3) tem exatamente um consumidor — o próprio lab01. Uma divisão temática alternativa (`compute`/`network`/`security`/`data`) também foi cogitada, mas revelou dependências reais entre módulos (a IAM Role e a endpoint policy do VPC Gateway Endpoint de S3 precisam do ARN do bucket, que sairia do módulo de dados) e agruparia recursos de natureza distinta — Security Group é controle de rede, IAM Role é identidade — sob um único rótulo genérico.

**Decisão:** manter todo o Lab 01 em um único root module (`terraform/environments/lab01/`), sem `terraform/modules/` por enquanto. Regra adotada para o projeto: só extrair um módulo quando houver um **segundo consumidor real** (não hipotético) — mesmo princípio de não criar abstração antes de precisar dela.

**Exceção conhecida:** o CIDR `10.0.0.0/16` do Lab 01 foi reservado dentro do bloco `10.0.0.0/8` prevendo que labs futuros (14, 19) vão precisar de VPC própria — `vpc` já tem um segundo consumidor conhecido, mesmo que ainda não implementado. Candidato natural a ser o primeiro módulo extraído, quando esse lab futuro for de fato construído (não antes).

**Alternativas consideradas:**

- Módulos granulares por tipo de recurso desde o início (`vpc`, `iam-role-ec2`, `security-group`) — plano original do README, adiado por não ter reaproveitamento real ainda.
- Divisão temática (`compute`, `network`, `security`, `data`) — descartada por misturar recursos de natureza diferente no mesmo módulo e criar dependências cruzadas (`data` → `network`/`security` via ARN do bucket) sem ganho de reuso correspondente.

**Trade-offs:** menos boilerplate (sem `variables.tf`/`outputs.tf` de módulo, sem blocos `module`) e um único lugar pra ler o código do Lab 01. Em troca, se um segundo consumidor real aparecer, vai exigir refatoração (mover recursos pra dentro de um módulo) — custo aceito conscientemente, adiado até ser necessário.

---

## ADR-009 — Log bucket persistente, fora do state do Lab 02

**Lab:** 02 — Centralized Logging Foundation
**Status:** Aceito e implementado

**Contexto:** o Lab 02 segue o mesmo padrão de destroy/recreate por sessão de estudo do Lab 01 (ADR-007). O bucket S3 que recebe CloudTrail e VPC Flow Logs, porém, guarda evidência/histórico — destruí-lo junto com o resto do lab apagaria o rastro de auditoria que os Labs 06 (Security Analytics) e 10 (Forensics) precisam consultar.

**Decisão:** o log bucket (`awssec-logs-230650392331`) é criado **uma única vez, via AWS CLI**, inteiramente fora do state Terraform do Lab 02 — mesmo padrão de bootstrap já usado para o bucket de backend do Terraform (ADR-004). Ver [setup-log-bucket-bootstrap.md](setup-log-bucket-bootstrap.md).

**Alternativas consideradas:** manter o bucket dentro do state do Lab 02 com `lifecycle { prevent_destroy = true }`.

**Trade-offs:** `prevent_destroy` foi descartado porque falha o `plan`/`destroy` **inteiro** do Lab 02 (não apenas daquele recurso) — quebraria o hábito de destroy/recreate de todo o resto do lab a cada sessão. Bootstrap via CLI resolve isso, ao custo de um recurso que o Terraform do Lab 02 não gerencia nem enxerga (precisa ser referenciado por nome fixo, não por `aws_s3_bucket.log.id`).

---

## ADR-010 — CloudTrail multi-region, com data events S3 e dual delivery (S3 + CloudWatch Logs)

**Lab:** 02
**Status:** Aceito

**Contexto:** um trail single-region cria uma lacuna óbvia — um atacante com credenciais roubadas escolheria deliberadamente operar numa região não monitorada. Além disso, actions de dados em S3 (`GetObject`/`PutObject`) não aparecem em management events por padrão, e o destino do trail determina quais ferramentas de investigação enxergam esses eventos depois.

**Decisão:**

- Trail **multi-region** (`awssec-lab02-trail`).
- **Data events de S3 habilitados**, escopados a "todos os buckets, atuais e futuros" (advanced event selector, ARN wildcard `arn:aws:s3`), **excluindo explicitamente o próprio log bucket** (evita eventos autorreferenciais do `PutObject` que o próprio CloudTrail gera ao entregar logs).
- **Entrega dupla: S3 + CloudWatch Logs** — S3 para retenção barata/durável (Athena, Lab 06); CloudWatch Logs para metric filters e CloudWatch Logs Insights (Lab 06) em tempo quase real.
- **Metric filter + alarm de uso da conta root incluído neste lab** (não adiado) — usa a entrega para CloudWatch Logs.

**Alternativas consideradas:** trail single-region; sem data events (só management events); entrega só para S3.

**Trade-offs:** mais eventos = mais custo de ingestão (pequeno, dado o volume de um lab de estudo) e mais superfície pra configurar exclusões corretamente (esquecer de excluir o próprio log bucket geraria ruído/custo). Ganho: nenhuma lacuna de "região não monitorada" nem de "atividade de dados invisível".

**Nota — correção de raciocínio durante a sessão de design:** a entrega dual (S3+CloudWatch) e o escopo `ALL` do Flow Logs (ADR-012) foram inicialmente justificados por "o GuardDuty do Lab 03 precisa disso" — premissa **incorreta**, corrigida na mesma sessão. Ver observação abaixo.

> **GuardDuty (e provavelmente outros serviços de detecção nativos da AWS) tem seu próprio pipeline de dados, independente**, para management events do CloudTrail, VPC Flow Logs e DNS query logs — ele **não** consome os destinos (S3/CloudWatch Logs) configurados neste lab. As decisões acima continuam corretas, mas pelo motivo certo: servem à **investigação própria** do usuário (Labs 06, 10, 12), não são pré-requisito para o Lab 03 funcionar. Vale checar se o mesmo padrão se aplica a Security Hub e Detective quando esses labs chegarem, em vez de assumir caso a caso.

---

## ADR-011 — Lifecycle Standard-IA aos 30 dias, sem Glacier

**Lab:** 02
**Status:** Aceito

**Contexto:** o log bucket é persistente (ADR-009) e cresce indefinidamente sem alguma política de custo. A opção mais barata de longo prazo seria uma transição para Glacier.

**Decisão:** transição para **Standard-IA aos 30 dias**, sem nenhuma camada Glacier.

**Alternativas consideradas:** transição adicional para Glacier (ex: aos 90 dias).

**Trade-offs:** Standard-IA custa mais por GB que Glacier, mas **Athena não consulta objetos em classe Glacier** sem um restore explícito antes — e o Lab 06 (Security Analytics) precisa consultar exatamente este histórico via Athena. Ir para Glacier quebraria essa consulta silenciosamente (o objeto continua "existindo", só não é lido). Dado que a conta tem horizonte de 6 meses (teto de custo do projeto), o ganho de ir mais fria que Standard-IA não compensou a complexidade adicionada.

---

## ADR-012 — VPC Flow Logs: destino S3+CloudWatch, tráfego `ALL` (não só `REJECT`)

**Lab:** 02
**Status:** Aceito

**Contexto:** Flow Logs no VPC do Lab 01 (lido via SSM `/lab01/vpc_id`) podem ser configurados só para tráfego rejeitado (`REJECT`), reduzindo volume/ruído, ou para todo o tráfego (`ALL`).

**Decisão:** `ALL`, com destino S3+CloudWatch Logs (mesmo racional de dual-delivery da ADR-010).

**Alternativas consideradas:** `REJECT`-only (opção inicial, revertida durante a mesma sessão de design).

**Trade-offs:** mais volume de log (mais custo de ingestão/armazenamento, ainda pequeno neste escopo) em troca de não cegar o Lab 10 (Forensics + Root Cause) exatamente onde ele mais precisa enxergar: um ataque bem-sucedido, por definição, anda sobre tráfego **`ACCEPT`ado** (ex: callback de C2 numa porta 443 liberada). `REJECT`-only mostraria só as tentativas que já falharam — o interessante para forense é o que passou.

---

## ADR-013 — Encryption SSE-S3 no log bucket, CMK adiado para o Lab 17

**Lab:** 02
**Status:** Aceito

**Contexto:** o log bucket (ADR-009) pode usar SSE-S3 (chave gerenciada pela AWS, gratuita) ou SSE-KMS com Customer Managed Key (CMK, ~US$ 1/mês + custo por chamada, permite key policy separada de quem pode decriptar).

**Decisão:** **SSE-S3** por agora.

**Alternativas consideradas:** SSE-KMS com CMK dedicada já neste lab.

**Trade-offs:** CMK adicionaria uma camada real de controle de acesso à decriptação dos logs (interessante em produção), mas antecipa conteúdo do **Lab 17 — KMS + Encryption** (Key Policies, grants, multi-region keys) antes do lab que formalmente estuda isso — inconsistente com o princípio de progressão do projeto (construir a camada de segurança progressivamente, não tudo de uma vez). SSE-S3 também mantém consistência com o bucket de backend do Terraform (ADR-004), que já usa o mesmo padrão. Revisitar quando o Lab 17 for implementado: candidato natural a migrar este bucket para SSE-KMS com CMK, formalizando key policy dedicada para leitura de logs de auditoria.

---

## ADR-014 — Athena query-results bucket é ephemeral (dentro do state do Lab 02)

**Lab:** 02
**Status:** Aceito

**Contexto:** diferente do log bucket (ADR-009), o bucket que recebe resultados de queries do Athena (usado no Lab 06) não guarda evidência — guarda a saída, regenerável, de uma consulta contra o histórico persistente de logs.

**Decisão:** bucket de resultados do Athena vive dentro do state Terraform normal do Lab 02, seguindo o ciclo de destroy/recreate por sessão de estudo (ADR-007), com `force_destroy = true` (mesmo padrão do bucket de dados do Lab 01).

**Alternativas consideradas:** tratá-lo com a mesma persistência do log bucket.

**Trade-offs:** nenhum — resultado de query é trivialmente regenerável reexecutando a mesma query contra o log bucket persistente. Não há razão para pagar o custo operacional extra de mantê-lo fora do state.

---

## ADR-015 — Detector do GuardDuty é persistente, fora do ciclo de destroy/recreate

**Lab:** 03 — GuardDuty
**Status:** Aceito

**Contexto:** o padrão do projeto (ADR-007) é `terraform destroy` da infraestrutura ao final de toda sessão de estudo, para não sangrar o teto de custo (US$100 / 6 meses). Essa regra existe por causa de recursos que cobram só por existir — o NAT Gateway do Lab 01 (~US$32/mês). O detector do GuardDuty não é assim: é grátis de existir, e todo o custo do serviço é proporcional ao **volume analisado** (management events, VPC Flow Logs, DNS query logs). Com a EC2 do Lab 01 parada entre sessões, esse volume cai para quase nada.

**Decisão:** o detector do GuardDuty é **persistente** — aplicado uma vez e mantido de pé, fora do ciclo de destroy/recreate por sessão. `terraform destroy` só ao encerrar os estudos.

**Alternativas consideradas:** detector efêmero, recriado a cada sessão junto com o resto do lab.

**Trade-offs:**

- O gatilho de custo do ADR-007 não se aplica — manter o detector ligado 24/7 custa ~US$0 enquanto não há atividade para analisar.
- **Baseline de ML preservado.** Findings de anomalia comportamental (`UnauthorizedAccess:IAMUser/InstanceCredentialExfiltration`, `Discovery:S3/AnomalousBehavior`, os "AnomalousBehavior" em geral) dependem de um modelo de comportamento que leva ~7–14 dias para se formar por detector. Recriar o detector zera esse baseline. Findings de threat-intel / assinatura (`Backdoor:EC2/C&CActivity.B!DNS`, `CryptoCurrency:*`, IP malicioso conhecido, Tor) não dependem de baseline e disparam na hora mesmo em detector novo — mas são só parte da cobertura.
- **Detector ID estável.** Recriar geraria um `detectorId` novo a cada sessão, com churn no SSM `/lab03/detector_id` e em tudo que os Labs 04/09/10 amarrarem nele.
- **O trial de 30 dias não reseta** ao reabilitar — não há economia nenhuma em destruir/recriar, só perda de histórico e de baseline.

---

## ADR-016 — Lab 03 inteiro num único root module persistente, sem ciclo de destroy

**Lab:** 03
**Status:** Aceito

**Contexto:** decidido o detector persistente (ADR-015), restava definir o layout Terraform: manter o resto do Lab 03 (regra EventBridge, tópico SNS, roles) no ciclo de destroy/recreate e isolar só o detector, ou tratar o lab inteiro como persistente.

**Decisão:** **todo o Lab 03** vive num único root module `terraform/environments/lab03/` (state próprio, key `lab03/terraform.tfstate`, mesmo backend bucket `awssec-tfstate-230650392331`), **persistente**, sem ciclo de destroy por sessão. Aplicado uma vez; `terraform destroy` só ao encerrar os estudos.

**Alternativas consideradas:**

- **(B)** Detector via bootstrap CLI, fora de qualquer state (padrão do log bucket, ADR-009) + o resto num `lab03/` efêmero.
- **(C)** Dois states Terraform: `lab03-foundation/` persistente + `lab03/` efêmero.

**Trade-offs:** nenhuma peça do Lab 03 cobra por ficar de pé — regra EventBridge, tópico SNS, assinatura e roles IAM são todos gratuitos. Inventar um ciclo de `destroy` para eles seria cerimônia sem economia, e (B)/(C) espalhariam o lab por 2–3 diretórios/states sem ganho. Opção (A) também mantém o cleanup de fim de estudos trivial (um único `terraform destroy`). **Efeito colateral positivo:** como não há ciclo destroy/apply, a classe de bug do TS-005 (assinatura SNS de e-mail perdida no ciclo) não existe no Lab 03 — a confirmação do link só é feita uma vez.

**Consequência para o SSM:** o Lab 03 **não lê** nenhum parâmetro SSM do Lab 01/02 — o GuardDuty tem pipeline de dados próprio e não depende dos destinos de log do Lab 02. Só o exercício de ataque proposital precisa da EC2 do Lab 01 no ar. Por isso o Lab 03 **não entra** no `scripts/manage-foundation.sh`.

---

## ADR-017 — Protection plans: S3 + EBS Malware agora; Runtime, RDS, Lambda adiados

**Lab:** 03
**Status:** Aceito

**Contexto:** o GuardDuty base já analisa CloudTrail management events, VPC Flow Logs e DNS query logs sem config e sem custo além do volume. Em cima disso há *protection plans* opcionais, cada um com pipeline e cobrança próprios.

**Decisão:** habilitar, além da base:

- **S3 Protection** (`S3_DATA_EVENTS`) — analisa S3 data events (`Policy:S3/BucketAnonymousAccessGranted`, `Discovery:S3/AnomalousBehavior`, `Exfiltration:S3/*`). Custo ~US$0,80/milhão de eventos → centavos no volume de estudo. Serve direto o cenário `attack-scenarios/public-s3/` e dá um trigger barato e determinístico (ADR-020).
- **Malware Protection for EC2** (`EBS_MALWARE_PROTECTION`) — snapshot + scan agentless do EBS em findings suspeitos de EC2. Custo US$0 enquanto nenhum scan dispara; ~US$0,05/GB (~US$0,40 para um volume de 8 GB) quando dispara. Deixa a capacidade pronta para os Labs 08/10.

Implementado com `aws_guardduty_detector` enxuto + um `aws_guardduty_detector_feature` por plano (forma da AWS provider v6; os blocos `datasources {}` no recurso monolítico estão *deprecated*).

**Não habilitados, de propósito:**

| Plano | Adiado para | Motivo |
|---|---|---|
| Runtime Monitoring (`RUNTIME_MONITORING`) | Lab 13 — Secure Compute | É sobre agente via SSM / hardening — tema formal do Lab 13. Custo ~US$1,50/vCPU/mês pró-rata. |
| RDS Protection (`RDS_LOGIN_EVENTS`) | Lab 18 | Não há RDS ainda. |
| Lambda Protection (`LAMBDA_NETWORK_LOGS`) | Lab 09/13 | Não há Lambda ainda. |
| EKS Protection (`EKS_AUDIT_LOGS`) | — | Fora do escopo do projeto (sem EKS). |

**Trade-offs:** S3 + Malware adicionam superfície mínima de custo (centavos + US$0-idle) em troca de dois pipelines de detecção a mais e dois cenários de ataque exercitáveis. Runtime Monitoring daria a detecção de EC2 mais forte (visibilidade de processo/arquivo/rede no SO), mas puxa gestão de agente — melhor no lab que estuda isso.

**Atualização (2026-08-27) — descoberto na validação pós-apply:** um detector novo do GuardDuty **não nasce "só com a base"** — a AWS liga por default quase todos os protection plans. Depois do primeiro `apply`, `get-detector` mostrou `EKS_AUDIT_LOGS`, `RDS_LOGIN_EVENTS` e `LAMBDA_NETWORK_LOGS` também como `ENABLED`, sem que o Terraform os tivesse tocado (e os nossos `aws_guardduty_detector_feature` para `S3_DATA_EVENTS`/`EBS_MALWARE_PROTECTION` foram, na prática, no-ops — já vinham on). Custo real hoje = US$0 (não há EKS/RDS/Lambda na conta para analisar), mas (a) contraria a decisão de habilitar cada plano no lab que o estuda, e (b) viraria cobrança silenciosa quando o Lab 09 criar Lambda e o Lab 18 criar RDS. **Correção:** adicionados pins explícitos `status = "DISABLED"` para `EKS_AUDIT_LOGS`, `RDS_LOGIN_EVENTS`, `LAMBDA_NETWORK_LOGS` e `RUNTIME_MONITORING` — o Terraform agora é um enunciado completo do estado desejado das features, não só do delta. Lição SCS-C03: ao habilitar um serviço de detecção, sempre verificar o que ele liga por default (princípio de menor funcionalidade).

---

## ADR-018 — Roteamento de findings: EventBridge → SNS/e-mail (severity ≥ 4); automação de resposta no Lab 09

**Lab:** 03
**Status:** Aceito

**Contexto:** findings do GuardDuty já caem no EventBridge (`source = aws.guardduty`, `detail-type = "GuardDuty Finding"`) sem config — falta uma regra + alvo para agir. O `agents.md` reserva a **resposta automatizada** (Lambda isola SG, tira snapshot, taggeia) para o Lab 09 — Automated Incident Response.

**Decisão:** o Lab 03 constrói só a camada de **notificação a um humano** — mesmo padrão do alarme de root usage do Lab 02:

- Regra EventBridge com `event_pattern` filtrando `detail.severity` por `{ "numeric": [ ">=", 4 ] }` (default MEDIUM+; parametrizável via `var.finding_severity_threshold`).
- Alvo: tópico SNS → assinatura por e-mail (`var.finding_notification_email`, mesmo padrão `terraform.tfvars` gitignored do Lab 02).
- *Input transformer* na regra para o e-mail sair legível (tipo, severidade, região, recurso, finding ID, link do console) em vez de JSON cru.
- Tópico SNS + nome da regra publicados no SSM (`/lab03/sns_topic_arn`, `/lab03/eventbridge_rule_name`) — o Lab 09 pendura a automação aqui.
- `finding_publishing_frequency = "FIFTEEN_MINUTES"` no detector: a primeira ocorrência de um finding sempre vai ao EventBridge em ~5 min, mas as **reocorrências** seguem esse parâmetro (default AWS = 6 h). 15 min (o mínimo) evita que um re-teste na mesma sessão pareça não gerar nada.

**Escolha do limiar MEDIUM+ (≥ 4):** num inbox real, findings LOW (`Recon:*`, `Policy:S3/BucketBlockPublicAccessDisabled` a 2,0) viram ruído — a tendência seria subir o filtro de qualquer jeito. Tudo continua visível no console e via `list-findings`; só o e-mail é filtrado. O filtro engolindo um finding LOW é, ele próprio, um caso de troubleshooting (ADR-020, cenário B).

**Alternativas consideradas:** notificar a partir de LOW (mais pedagógico num lab, ruidoso demais no geral); já montar um esqueleto de automação (EventBridge → Lambda no-op) no Lab 03 (descartado — mistura escopo do Lab 09).

**Trade-offs:** regra EventBridge + SNS por e-mail são gratuitos. A fronteira "notificação aqui / automação no Lab 09" mantém cada lab com um foco, ao custo de o Lab 09 precisar ler o tópico/regra do Lab 03 via SSM (já é o padrão do projeto).

---

## ADR-019 — Sem export de findings para S3 no Lab 03 (KMS CMK adiado para o Lab 17)

**Lab:** 03
**Status:** Aceito

**Contexto:** o GuardDuty pode exportar findings para uma bucket S3, o que dá retenção além dos 90 dias que o console guarda e permite consulta histórica via Athena / Security Lake. Mas o export **exige uma KMS CMK** (chave gerenciada pelo cliente, com key policy dando `kms:GenerateDataKey` ao GuardDuty) — SSE-S3 e chave AWS-managed não são aceitas. É a mesma parede do ADR-013 no log bucket do Lab 02.

**Decisão:** **sem export para S3 no Lab 03.** Findings vivem no console (janela móvel de 90 dias) + fluem pelo EventBridge. O export com CMK entra no **Lab 17** (KMS + Encryption), junto com a migração do log bucket para SSE-KMS.

**Alternativas consideradas:** criar uma CMK dedicada agora só para viabilizar o export.

**Trade-offs:** 90 dias de retenção de findings são suficientes para o ritmo de estudo, e o Security Hub (Lab 04) ingere findings do GuardDuty direto pela integração de serviço, sem depender do export para S3. Antecipar a CMK quebraria o princípio de progressão do projeto (construir a camada de KMS no lab que a estuda). Revisitar no Lab 17; se o Lab 05/06 precisar de findings históricos antes disso, adianta-se lá.

---

## ADR-020 — Ataque proposital duplo + dois cenários de troubleshooting

**Lab:** 03
**Status:** Aceito

**Contexto:** o lab precisa de um evento **real** (não só `create-sample-findings`) para exercitar o ciclo detectar → investigar, e de um cenário de "GuardDuty sem o finding esperado" (item explícito da lista de troubleshooting do `agents.md`). O limiar de e-mail é MEDIUM+ (ADR-018), então o gatilho precisa gerar um finding ≥ 4.

**Decisão — dois ataques propositais:**

1. **DNS C&C** — `dig guarddutyc2activityb.com` da EC2 do Lab 01 via Session Manager → `Backdoor:EC2/C&CActivity.B!DNS` (HIGH, 8.0). Usa o pipeline de DNS query logs; exige que a EC2 resolva pelo resolver da VPC (default). Custo ~US$0. É o gatilho principal.
2. **Bucket policy anônima** — aplicar numa bucket uma policy com `Principal: "*"` + `s3:GetObject` → `Policy:S3/BucketAnonymousAccessGranted` (HIGH). Exercita o S3 Protection do ADR-017 e conecta com `attack-scenarios/public-s3/`.
   - ⚠️ Só desligar o Block Public Access dispara `Policy:S3/BucketBlockPublicAccessDisabled` (LOW, 2,0) — abaixo do limiar, não gera e-mail. Por isso o gatilho é a policy anônima, não o toggle de BPA.

**Decisão — dois cenários de troubleshooting:**

- **A (principal) — suppression rule / filtro arquivando o finding.** Criar um `aws_guardduty_filter` (ou filtro no console) com `action = ARCHIVE` casando `Backdoor:EC2/C&CActivity.B!DNS`, rodar o gatilho, observar que nenhum e-mail chega e o finding aparece como *archived*. Investigar "o finding existe mas está arquivado, por quê?" → achar a suppression rule. Ensina suppression rules (tópico pesado no exame). A regra **não** fica no Terraform — é passo manual do exercício (documentado no `cli-reference`).
- **B (secundário) — filtro de severidade engolindo um finding LOW.** Desligar só o BPA de uma bucket (finding LOW 2,0), notar que nenhum e-mail chega, e rastrear a causa até o `event_pattern` `severity >= 4` da regra EventBridge. Custo zero, amarra numa config que já é nossa.
- C (região errada — `list-findings` em `us-west-2` com o detector em `us-east-1`) e D (`finding_publishing_frequency` alta atrasando reocorrência) ficam como nota de rodapé no README.

**Trade-offs:** dois ataques cobrem dois pipelines distintos (DNS query logs vs S3 data events) ao custo de um lab um pouco menos enxuto. Um só (DNS C&C) bastaria para o ciclo, mas deixaria o S3 Protection do ADR-017 sem exercício próprio.

**Atualização (2026-08-28) — correção de premissa, descoberta na execução:** o Ataque 2 (`Policy:S3/BucketAnonymousAccessGranted`) vem do pipeline de **CloudTrail management events** (`PutBucketPolicy`), **não** da feature `S3_DATA_EVENTS`. Os findings `Policy:S3/*` e `Stealth:S3/*` são gerados da análise de management events (fonte fundacional, sempre on). A feature `S3_DATA_EVENTS` (ADR-017) adiciona findings de *data events* object-level (`Discovery:S3/AnomalousBehavior`, `Exfiltration:S3/AnomalousBehavior`, `Impact:S3/*`), que dependem de baseline comportamental (7–14 dias) e **não foram exercitados** neste lab — inviável no dia 1. Consequência: o Ataque 2 valida o ciclo detectar→investigar para uma misconfig de S3 e o roteamento por severidade, mas o retorno de custo/detecção da feature `S3_DATA_EVENTS` em si fica para um lab com carga de acesso a objetos ao longo do tempo (Lab 06/07). O finding do Ataque 1 (`Backdoor:EC2/C&CActivity.B!DNS`) veio do pipeline de DNS query logs como previsto. **Execução:** ambos os ataques + TS-007 (suppression rule) + TS-008 (filtro de severidade) rodados e documentados em `docs/troubleshooting.md`; o teardown do Lab 01/02 no meio da investigação gerou uma lição extra (evidência volátil — VPC Flow Logs — se coleta antes do `destroy`; ver README do lab, seção "Detecção e investigação").

---

## ADR-021 — GuardDuty multi-account / delegated administrator: conceitual no Lab 03, implementação no Lab 19

**Lab:** 03
**Status:** Aceito

**Contexto:** a conta 230650392331 já é management de uma AWS Organization (`o-23e9438ykt`, criada ao ativar o IAM Identity Center — ver ADR-007). O GuardDuty suporta *delegated administrator* + auto-enable para contas da org, e a estratégia multi-account é conteúdo de exame (aula 7 do curso). Mas **só há uma conta** — montar delegated admin "para si mesmo" é mecânica sem nenhum member.

**Decisão:** o Lab 03 cobre multi-account / delegated admin **só conceitualmente** no README (modelo administrator/member, `enable-organization-admin-account`, auto-enable, por que centralizar findings de várias contas). A **implementação real** acontece no **Lab 19 — Multi-Account Security Governance**, quando existirem contas member de verdade.

**Alternativas consideradas:** rodar um `enable-organization-admin-account` simbólico agora.

**Trade-offs:** consistente com como o projeto adia a profundidade de Organizations para o Lab 19. Um gesto simbólico agora não teria nada para administrar e só adicionaria estado para limpar depois.
