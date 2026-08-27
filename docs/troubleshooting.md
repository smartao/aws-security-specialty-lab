# Troubleshooting Log

Registro dos episódios reais de troubleshooting do projeto, seguindo o processo Sintoma → Hipóteses → Coleta de evidências → Teste → Causa raiz → Correção → Validação → Documentação. Nem todo episódio aqui é uma falha proposital de lab — alguns são problemas reais que apareceram durante a implementação, e são tão válidos de documentar quanto os planejados.

---

## TS-001 — Credenciais SSO inválidas após troca de permission set no console

**Lab:** 01 — durante o primeiro `terraform plan` do lab
**Status:** ✅ Resolvido

**Sintoma:** `terraform plan` (e depois `aws sts get-caller-identity`) passou a falhar com `InvalidClientTokenId`, mesmo logo após um `aws sso login --profile sergei-upstart` bem-sucedido.

**Hipóteses consideradas:**

1. Sessão SSO expirou de novo entre o login e o comando.
2. Cache local de credenciais STS (`~/.aws/cli/cache/`) desatualizado.
3. Alguma mudança do lado da conta (Identity Center) invalidou o acesso.

**Coleta de evidências:**

- `~/.aws/sso/cache/*.json` tinha um token de acesso recém-emitido (login funcionou).
- `~/.aws/cli/cache/*.json` continha uma credencial STS com `Expiration` ainda no futuro (não era expiração por tempo).
- Depois de limpar esse cache, o erro mudou de `InvalidClientTokenId` para `ForbiddenException: No access` na chamada `sso:GetRoleCredentials` — sinal de que o problema não era cache, era a própria atribuição de acesso.
- `aws sso list-account-roles --account-id 230650392331` mostrou que a única role disponível para assumir na conta era `AdministratorFull`, não `AdministratorAccess` (que era o valor configurado em `sso_role_name` no `~/.aws/config`).

**Teste:** comparar o `roleName` retornado por `list-account-roles` com o `sso_role_name` do profile local — divergiam.

**Causa raiz:** o permission set atribuído à conta havia sido trocado no console do Identity Center, de `AdministratorAccess` (gerenciado pela AWS) para um permission set customizado (`AdministratorFull`). Isso muda o nome da role `AWSReservedSSO_<nome-do-permission-set>_<hash>` que o SSO expõe para assumir — o profile local continuava referenciando o nome antigo, que deixou de existir na atribuição.

**Correção:** atualizar `sso_role_name` em `~/.aws/config` (profile `sergei-upstart`) para bater com o permission set atualmente atribuído na conta.

**Validação:** `aws sts get-caller-identity --profile sergei-upstart` voltou a retornar `assumed-role/AWSReservedSSO_AdministratorFull_.../sergei` sem erro.

**Lição:** o nome da role SSO assumível **não é fixo** — ele é derivado do nome do permission set atribuído no momento. Qualquer alteração de permission set no console (renomear, trocar, reatribuir) quebra qualquer profile local que hardcode `sso_role_name`, mesmo com o token de acesso SSO válido.

---

## TS-002 — Billing e Cost Explorer inacessíveis mesmo com policy administrativa total

**Lab:** 01 — mesma sessão do TS-001
**Status:** ✅ Resolvido
**Evidência:** [evidence/lab01/ts-002-billing-iam-access-toggle.png](../evidence/lab01/ts-002-billing-iam-access-toggle.png)

**Sintoma:** mesmo autenticado com um permission set de acesso administrativo total (`AdministratorAccess`, `Action: "*", Resource: "*"`), a conta não conseguia visualizar as páginas de **Billing** e **Cost Explorer** no console.

**Hipóteses consideradas:**

1. O permission set gerenciado `AdministratorAccess` tem alguma restrição implícita não visível na policy.
2. Falta uma permissão explícita de billing (`aws-portal:*`, `ce:*`) que um `Action: "*"` teoricamente já cobriria.
3. Existe um controle de acesso a billing **fora do escopo de IAM policy** — um toggle a nível de conta root.

**Coleta de evidências (parcial):** trocar para um permission set customizado com o mesmo nível de permissão (`AdministratorFull`) não resolveu o problema — reforça a hipótese 3, já que se fosse conteúdo de policy, uma policy equivalente com o mesmo `Action: "*"` teria o mesmo resultado.

**Causa raiz (confirmada):** o toggle **"IAM user and role access to Billing information"** (Billing and Cost Management → Account) estava desativado na conta. Esse controle é independente de IAM policy — bloqueia acesso a Billing/Cost Explorer para **qualquer** identidade IAM, mesmo uma com `Action: "*", Resource: "*"`. Confirma a hipótese 3: essa conta ainda opera no modelo legado (billing controlado por esse toggle de conta root, não só por IAM policy).

**Correção:** ativar "Activate IAM Access" nesse toggle, na conta root.

**Validação:** com `AdministratorAccess` (permission set original, já revertido no TS-001), Billing e Cost Explorer passaram a carregar normalmente.

**Lição:** ao contrário da maioria dos serviços AWS, Billing não segue o modelo padrão "toda permissão vem de IAM policy" em contas mais antigas — existe um gate extra fora do IAM, só alterável pelo root. Relevante pro Domínio 6 (Governança) do SCS-C03: nem todo controle de acesso na AWS é modelado como IAM policy.

---

## TS-003 — SSM Parameter Store rejeita prefixo `/awssec/...`

**Lab:** 01 — primeiro `terraform apply` do lab
**Status:** ✅ Resolvido

**Sintoma:** `terraform apply` criou 29 dos 38 recursos planejados sem erro (VPC, subnets, IGW, NAT, rotas, VPC endpoint, EC2, IAM, S3) e falhou nos 9 `aws_ssm_parameter`, todos com o mesmo erro:

```text
Error: creating SSM Parameter (/awssec/lab01/vpc_id): operation error SSM: PutParameter,
https response error StatusCode: 400, api error AccessDeniedException:
No access to reserved parameter name: awssec/lab01/vpc_id.
```

**Hipóteses consideradas:**

1. Falta de permissão IAM para `ssm:PutParameter` (mas o resto da role é `AdministratorAccess`, pouco provável).
2. Algum limite de conta (nº de parâmetros, tamanho) sendo excedido.
3. O nome do parâmetro colide com algo reservado pela própria AWS.

**Coleta de evidências:** o erro é `AccessDeniedException`, não `ValidationException` (descarta limite de tamanho/quantidade), e o texto é explícito: "No access to **reserved parameter name**". Isso aponta direto pra hipótese 3.

**Causa raiz:** o SSM Parameter Store reserva, para uso interno da AWS, qualquer nome de parâmetro cujo início (removendo a barra inicial) comece com `aws` ou `ssm`, case-insensitive — independente do que vem depois. O prefixo do projeto, `awssec`, começa literalmente com `aws`, então `/awssec/lab01/vpc_id` cai nessa reserva e é rejeitado antes mesmo de avaliar IAM policy.

**Correção:** trocar o prefixo dos parâmetros de `/awssec/lab01/...` para `/lab01/...` — removendo o `awssec` do path (redundante de qualquer forma: essa Parameter Store inteira já pertence a este projeto, mesma lógica já usada na ADR-005 para não repetir `Environment` no nome dos recursos). Atualizado em `terraform/environments/lab01/ssm.tf`, na ADR-004 e no README do Lab 01.

**Validação:** reaplicado só os 9 `aws_ssm_parameter` faltantes (state incremental preservou os outros 29) — `Apply complete! Resources: 9 added, 0 changed, 0 destroyed`, todos com id `/lab01/...`.

**Lição:** o prefixo `awssec`, usado em todo o resto do projeto (buckets, VPC, IAM, tags) sem problema, não é seguro por padrão dentro do SSM Parameter Store especificamente — é o único serviço, até agora, com uma lista de nomes reservados que colide com a convenção de naming do projeto.

---

## TS-004 — Falha proposital: EC2 em subnet isolada não registra no SSM

**Lab:** 01 — exercício de troubleshooting proposital (já identificado no planejamento original do lab)
**Status:** ✅ Resolvido
**Recursos:** `terraform/environments/lab01/troubleshoot_isolated.tf` (temporário, fora da arquitetura permanente do lab)

**Sintoma:** instância `aws_instance.isolated_test`, criada de propósito na subnet `Isolated-A`, aparece como "Not connected" no Session Manager (console) e não aparece em `aws ssm describe-instance-information` (retorna `null`).

**Hipóteses consideradas (levantadas durante a investigação):**

1. A subnet isolada não tem rota de saída (nem via NAT, por desenho da ADR-001) — o agente SSM não consegue alcançar os endpoints públicos do serviço.
2. Faltam VPC Endpoints que permitam esse tráfego sem sair da rede AWS.

**Coleta de evidências:**

- `aws ssm describe-instance-information` com filtro no InstanceId retornou `null` — confirma que a instância nunca completou o registro (não é uma sessão caída, é ausência total de handshake).
- Route table da subnet isolada (`aws_route_table.isolated`) só tem a rota `local` automática, sem `0.0.0.0/0` para NAT ou IGW — confirmado por desenho, não por engano.

**Teste:** criar os VPC Interface Endpoints para `ssm`, `ssmmessages` e `ec2messages` na subnet isolada, com Security Group dedicado liberando 443/TCP a partir do SG da EC2 (`sg-ec2-app`). Mesmo com os 3 endpoints em estado `available` e toda a configuração de rede/SG correta, o registro continuou `null` por vários minutos.

**Causa raiz (duas causas, não uma):**

1. **Estrutural:** SSM não é um dos dois serviços com suporte a Gateway Endpoint (só S3 e DynamoDB têm) — exige Interface Endpoint, que depende de ENI + Private DNS dentro da subnet, não de uma entrada de rota. Sem os 3 endpoints (`ssm` para registro/heartbeat, `ssmmessages` para o canal de dados da sessão, `ec2messages` para o canal de comandos), não há caminho de rede possível a partir de uma subnet sem rota de saída.
2. **Operacional:** o agente SSM já vinha falhando em se conectar desde o boot da instância (endpoints não existiam ainda) e caiu num ciclo de retry mais espaçado — mesmo depois da rede ficar correta, não reconectou sozinho dentro de alguns minutos de espera.

**Correção:**

1. Criar os 3 VPC Interface Endpoints + Security Group dedicado (não reaproveitar o SG da EC2 — semânticas diferentes).
2. `aws ec2 reboot-instances --instance-ids i-073fbdb0b8367e892` — força o agente a subir do zero, já com o caminho de rede disponível, em vez de esperar o próximo ciclo de retry.

**Validação:** `describe-instance-information` retornou `PingStatus: Online` após o reboot; comando remoto via `ssm send-command` (`whoami` → `root`) executado com sucesso — acesso administrativo completo, sem SSH, sem rota de internet.

**Lição:** dois aprendizados empilhados. (1) Nem todo VPC Endpoint é igual — Gateway Endpoint (rota, grátis, só S3/DynamoDB) e Interface Endpoint (ENI + Private DNS, cobrado por hora, todo o resto dos serviços) resolvem o mesmo problema de forma completamente diferente, e a subnet isolada só pode contar com o segundo. (2) Corrigir a rede não é garantia de recuperação imediata de um agente que já estava em ciclo de falha — vale sempre validar se o processo/serviço do lado do host precisa de um empurrão (restart/reboot) depois que a causa raiz de rede é corrigida.

---

## TS-005 — Assinatura SNS do alarme de root usage perdida após ciclo destroy/apply do Lab 02

**Lab:** 02 — Centralized Logging Foundation, entre a sessão de implementação (2026-08-26) e a sessão seguinte (2026-08-27)
**Status:** ✅ Resolvido

**Sintoma:** a assinatura por e-mail (`sergei.martao@gmail.com`) do tópico SNS `awssec-lab02-sns-security-alarms` (alarme de uso da conta root), confirmada com sucesso em 2026-08-26, tinha desaparecido por completo em 2026-08-27 — `aws sns list-subscriptions-by-topic` retornava lista vazia, mesmo o tópico continuando a existir com o mesmo ARN.

**Hipóteses consideradas:**

1. O token de confirmação expirou (descartada: janela padrão da AWS é 3 dias, o intervalo real foi de ~19h).
2. O usuário clicou sem querer num link de "unsubscribe" no e-mail (ex: cabeçalho `List-Unsubscribe`, ação automática de algum filtro de e-mail).
3. Um `terraform destroy`/`apply` do Lab 02 rodou nesse meio-tempo (fim/início de sessão de estudo, ADR-007) e recriou o tópico sem preservar a assinatura.

**Coleta de evidências:** `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventSource,AttributeValue=sns.amazonaws.com` (o próprio trail do Lab 02 já estava capturando esses eventos) mostrou:

- `Unsubscribe` em `2026-08-26T10:15:10Z`, com `userAgent` contendo `terraform-provider-aws/6.61.0` — **a própria Terraform destruiu a assinatura**, não foi clique acidental em link nem expiração.
- Perguntado diretamente, o usuário confirmou ter rodado o ciclo normal de `terraform destroy` (fim de sessão) + `terraform apply` (início da sessão seguinte) nesse intervalo.

**Causa raiz:** `var.alarm_notification_email` só tinha sido passada via `-var="..."` na linha de comando do primeiro `apply` — nunca foi persistida em nenhum arquivo. No próximo `apply` (sem o `-var`), a variável voltou ao `default = ""`, `count = var.alarm_notification_email != "" ? 1 : 0` caiu para `0`, e o Terraform destruiu a `aws_sns_topic_subscription` silenciosamente — sem erro, sem aviso, porque do ponto de vista do Terraform é uma alteração de configuração legítima, não um bug.

**Correção:** criar `terraform/environments/lab02/terraform.tfvars` (já coberto pelo `.gitignore` do projeto, `*.tfvars`) com `alarm_notification_email = "sergei.martao@gmail.com"` — agora qualquer `apply` (inclusive no próximo ciclo destroy/recreate) usa esse valor automaticamente, sem depender de lembrar de passar `-var` toda vez.

**Complicador na validação:** depois de reaplicar e recriar a assinatura, `list-subscriptions-by-topic` mostrou `SubscriptionArn: "Deleted"` mesmo antes de qualquer clique — e o usuário recebeu um e-mail de "assinatura desativada" com um link de "Inscrever-se novamente". Ao clicar nesse segundo link, a confirmação foi concluída de fato (ARN real retornado, coincidindo com o ID gerado pelo `apply`). Não foi possível confirmar a causa exata desse passo intermediário via CloudTrail (o clique em link de confirmação/desativação do SNS é uma URL pública, sem SigV4/IAM — não gera evento de CloudTrail), mas o fluxo "e-mail de desativação → link de re-inscrição → confirmação" é um comportamento conhecido do SNS para assinaturas recém-criadas em um tópico que teve uma assinatura anterior recém-destruída para o mesmo endpoint.

**Validação:** `aws sns list-subscriptions-by-topic` retornou `SubscriptionArn` com um ARN real (não mais `PendingConfirmation` nem `Deleted`) para `sergei.martao@gmail.com`.

**Lição:** variáveis Terraform passadas só via `-var` na CLI **não sobrevivem** ao próximo `apply`/`destroy` de outra sessão — qualquer valor que precise persistir através do ciclo de destroy/recreate (ADR-007) tem que ir para um arquivo `.tfvars` (gitignored, se sensível) ou um default explícito no código, nunca só na memória de quem digitou o comando. Vale revisar se outros labs futuros com notificação (Lab 09 — Automated Incident Response, por exemplo) têm o mesmo risco.

---

## TS-006 — Falha proposital: CloudTrail para de entregar no S3 (bucket policy com trail errado)

**Lab:** 02 — exercício de troubleshooting proposital
**Status:** ✅ Resolvido
**Evidência:** [evidence/lab02/ts-006-cloudtrail-bucket-policy-investigation.md](../evidence/lab02/ts-006-cloudtrail-bucket-policy-investigation.md), [evidence/lab02/ts-006-cloudtrail-console-bucket-access-denied.png](../evidence/lab02/ts-006-cloudtrail-console-bucket-access-denied.png)

**Sintoma:** o trail `awssec-lab02-trail` continuava com `IsLogging: true` no console e via CLI, mas nenhum objeto novo chegava no prefixo `CloudTrail/` do log bucket, mesmo com atividade de API gerada na conta.

**Investigação (conduzida pelo usuário, sem a causa revelada de antemão):**

1. `aws cloudtrail get-trail-status --name awssec-lab02-trail` → `LatestDeliveryError: "AccessDenied"` — primeiro sinal, aponta direto para permissão em vez de "trail desligado" ou "sem eventos".
2. `aws cloudtrail describe-trails --trail-name-list awssec-lab02-trail` → confirmou o bucket de destino real (`awssec-logs-230650392331`), em vez de assumir.
3. `aws s3api get-bucket-policy --bucket awssec-logs-230650392331` → encontrou a causa: as statements `AWSCloudTrailAclCheck` e `AWSCloudTrailWrite` tinham a condição `aws:SourceArn` apontando para `arn:aws:cloudtrail:us-east-1:230650392331:trail/awssec-lab02-trail-old` — um trail que não existe.
4. Console (CloudTrail → Trails) corroborou de forma independente: status "Bucket access denied — Fix policy" na listagem do trail.

**Causa raiz:** a bucket policy do log bucket (mantida fora do Terraform, ver ADR-009/setup-log-bucket-bootstrap.md) tinha o `aws:SourceArn` das duas statements do CloudTrail apontando para um nome de trail (`awssec-lab02-trail-old`) diferente do trail real (`awssec-lab02-trail`). Como a condição nunca batia, a `Allow` nunca se aplicava — *implicit deny* em `s3:PutObject`, mesmo o restante da policy (Flow Logs, deny insecure transport) permanecendo correto e não afetado.

**Nuance de diagnóstico:** a primeira leitura da causa citou "o ARN do bucket está errado" — impreciso. O `Resource` das statements (ARN do bucket/prefixo) estava correto o tempo todo; o que estava errado era o **valor da condição** `aws:SourceArn`, que deveria referenciar o ARN do **trail**, não do bucket. Distinção relevante para o SCS-C03: `Resource` define o que a policy protege, `Condition` define quando a permissão se aplica.

**Correção:** restaurar o valor correto do `aws:SourceArn` (`arn:aws:cloudtrail:us-east-1:230650392331:trail/awssec-lab02-trail`) nas duas statements, via `aws s3api put-bucket-policy`.

**Validação:** nova chamada de API (`aws sts get-caller-identity`) gerada como evento de teste; `get-trail-status` voltou a mostrar `LatestDeliveryAttemptSucceeded` avançando para um timestamp posterior à correção, confirmando entrega restabelecida.

**Lição:** este é exatamente o risco que já havia sido antecipado em `docs/setup-log-bucket-bootstrap.md` no momento do bootstrap ("se o nome do trail mudar, a bucket policy precisa ser reaplicada manualmente") — mas o exercício mostrou como o sintoma se manifesta na prática: o trail parece saudável em quase todos os campos (`IsLogging: true`), e só o campo `LatestDeliveryError` do `get-trail-status` denuncia o problema. Reforça por que este bucket ficar fora do Terraform (ADR-009) é uma decisão com trade-off real: nenhum `terraform plan` avisa sobre esse tipo de divergência, a validação tem que ser manual/CLI.
