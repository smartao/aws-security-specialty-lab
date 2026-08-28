# Exam Review Log (SCS-C03)

Banco de questões de revisão, uma seção por lab, no formato do exame (múltipla escolha, múltipla resposta, ordenação, correspondência — nunca só múltipla escolha). Cada pergunta registra a resposta dada, o gabarito, o porquê de cada alternativa e a palavra-chave que deveria chamar atenção numa pergunta parecida na prova real.

Objetivo: revisão espaçada perto da prova, sem precisar reabrir o README de cada lab — e um sinal de quais domínios/conceitos precisam de mais prática, lab a lab.

---

## Lab 02 — Centralized Logging Foundation

**Placar:** 3,5 / 4 — nenhum erro conceitual, um gap de completude na Pergunta 2.

### Pergunta 1 (múltipla escolha)

Por que o Lab 02 escolheu CloudTrail **multi-region** em vez de single-region?

A) Multi-region é obrigatório em contas com IAM Identity Center habilitado
B) Um atacante com credenciais roubadas poderia deliberadamente operar numa região sem trail, ficando invisível
C) Single-region trail não suporta data events de S3
D) Multi-region é a única forma de habilitar log file validation

**Resposta dada:** B
**Gabarito:** B — ✅ correto

- **A)** Falso — Identity Center e CloudTrail multi-region são recursos independentes.
- **C)** Falso — um trail single-region também suporta data events de S3; a diferença entre single/multi-region é só o escopo geográfico.
- **D)** Falso — log file validation funciona em qualquer trail, single ou multi-region.

**Palavra-chave:** "deliberadamente" — quando o enunciado descreve um atacante *escolhendo* onde operar, a resposta certa quase sempre envolve eliminar um ponto cego geográfico/de escopo.

---

### Pergunta 2 (múltipla resposta)

Quais destes recursos **sobrevivem** a um `terraform destroy` rodado em `terraform/environments/lab02/`?

A) O log bucket (`awssec-logs-230650392331`)
B) O trail do CloudTrail (`awssec-lab02-trail`)
C) A VPC do Lab 01
D) O bucket de resultados do Athena
E) Os parâmetros SSM em `/lab01/...`

**Resposta dada:** A
**Gabarito:** A, C, E — ⚠️ parcialmente correto (faltou C e E)

- **A)** ✅ certo — log bucket fica fora do state por decisão explícita (ADR-009).
- **C)** ✅ sobrevive, mas por motivo diferente do A: a VPC do Lab 01 nunca pertenceu ao state do Lab 02 — é só lida via `data "aws_ssm_parameter"`, nunca gerenciada.
- **E)** ✅ mesmo raciocínio de C — os parâmetros `/lab01/...` pertencem ao state do Lab 01, não do Lab 02.
- **B, D)** ❌ são destruídos — pertencem de fato ao state do Lab 02.

**Distinção que a questão testava:** "fora do state por decisão de design" (A — poderia estar no state do Lab 02, mas foi deliberadamente excluído) é diferente de "nunca fez parte desse state" (C, E — pertencem a outro lab inteiramente). Ambas resultam em "sobrevive", por raciocínios distintos.

**Palavra-chave:** "rodado **em lab02**" — `terraform destroy` só tem escopo sobre o state que você aponta; nunca cruza fronteira de lab.

**Para revisar antes da prova:** generalizar de "o log bucket sobrevive" (fato pontual) para "state isolation entre labs" (princípio) — é esse segundo nível que a prova testa.

---

### Pergunta 3 (ordenação)

Coloque na sequência real do TS-006:

a) Rodar `get-bucket-policy` e achar a condição `aws:SourceArn` apontando pro trail errado
b) Notar que nenhum objeto novo aparece no prefixo `CloudTrail/` do bucket
c) Rodar `describe-trails` para confirmar qual bucket o trail realmente usa
d) Corrigir a policy e validar via `get-trail-status`
e) Rodar `get-trail-status` e ver `LatestDeliveryError: AccessDenied`

**Resposta dada:** b, e, c, a, d
**Gabarito:** b, e, c, a, d — ✅ correto

Sequência: sintoma → coleta do erro específico → confirmação do alvo (bucket) → causa raiz (policy) → correção/validação. Espinha dorsal do processo Sintoma→Hipóteses→Evidências→Causa raiz→Correção→Validação usado em todo troubleshooting do projeto.

---

### Pergunta 4 (correspondência)

Relacione a ADR com o motivo técnico:

| Coluna A | Coluna B |
|---|---|
| 1. ADR-011 (Standard-IA, sem Glacier) | I. Ataque bem-sucedido anda sobre tráfego aceito, não rejeitado |
| 2. ADR-012 (Flow Logs `ALL`) | II. Athena não consulta objetos em classe Glacier sem restore explícito |
| 3. ADR-013 (SSE-S3, não CMK) | III. Evita antecipar conteúdo do Lab 17 antes da hora |

**Resposta dada:** 1-II, 2-I, 3-III
**Gabarito:** 1-II, 2-I, 3-III — ✅ correto

As três relações batem com o motivo registrado em cada ADR — bom sinal de que o "porquê" por trás de cada decisão ficou, não só o "o quê".
