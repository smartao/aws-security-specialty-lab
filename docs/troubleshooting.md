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
