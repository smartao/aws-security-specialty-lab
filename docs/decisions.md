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
