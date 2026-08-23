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
- Labs consomem outputs uns dos outros via **SSM Parameter Store** (`/awssec/lab01/...`), não via `terraform_remote_state`.

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
