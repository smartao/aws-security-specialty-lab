# Attack Scenarios

Roteiros **reutilizáveis** de execução dos ataques simulados do projeto, na **visão do
atacante** e **cruzando labs**. Um cenário é uma cadeia (recon → acesso → ação → impacto),
não o exercício de um lab: `compromised-ec2` é tocado pelo Lab 03 (detecção), Lab 09
(resposta automática), Lab 10 (forense) e Labs 12/13 (contenção de rede / runtime). Nenhum
lab isolado é dono da cadeia inteira.

## Onde cada coisa vive

| Artefato | Pergunta que responde | Escopo |
|---|---|---|
| `attack-scenarios/<cenário>/` (aqui) | **Como se executa** o ataque, ponta a ponta — passos reutilizáveis | vários labs |
| `labs/**/README.md` § "Falha ou ataque proposital" | **O que foi executado naquele lab** — registro datado, resource/finding IDs, investigação com a tooling do lab | 1 lab |
| [`docs/threat-model.md`](../docs/threat-model.md) (`TM-0X`) | **Contra o que** defendemos — vetor, preventivo, detecção, risco residual | plataforma |
| [`runbooks/`](../runbooks/) | **Como responder** quando o ataque acontece | operação |

Regra de fonte única: os **passos de execução genéricos** moram aqui; o README do lab
**referencia** e acrescenta só o registro do que rodou. O cenário **linka** a análise de
detecção do lab, não a copia.

## Cenários

| Cenário | Ameaça (TM) | STRIDE | Status | Labs que exercitam |
|---|---|---|---|---|
| [`compromised-ec2`](compromised-ec2/README.md) | TM-02, TM-03, TM-06, TM-07 | S · T · I · D | 🚧 fase C2/DNS no Lab 03 (2026-08-28) | 03 ✅ · 09 · 10 · 12 · 13 |
| [`public-s3`](public-s3/README.md) | TM-04 | I | ✅ Lab 03 (2026-08-28) | 03 ✅ · 04 · 07 · 20 |
| [`leaked-secret`](leaked-secret/README.md) | TM-01 (rel. TM-02) | S · E | 🔒 não iniciado | 15 · 16 · 09 |
| [`excessive-iam`](excessive-iam/README.md) | TM-05 | E | 🔒 não iniciado | 15 · 16 |

`suspicious-network-activity` foi **fundido** em `compromised-ec2` (2026-08-29): C2,
mineração e exfiltração de rede são fases da mesma cadeia, e TM-02/03/06/07 sempre
apontavam para os dois cenários juntos.

## Preenchimento sob demanda

Um cenário só é preenchido quando o **primeiro lab que o exercita** fecha — antes disso
fica como stub no template abaixo. Não se escreve roteiro de ataque para um controle que
ainda não existe (mesmo princípio de progressão dos ADRs).

## Template

Cada `<cenário>/README.md` segue:

- **Cabeçalho** — descrição, status, STRIDE, agente (`TA#`), ameaça (`TM-0X`), labs que exercitam
- **Objetivo do ataque simulado** — o que se quer provar
- **Fases** (cadeia multi-etapa) ou **Vetor** (ataque de um passo)
- **Pré-condições** — o que precisa estar de pé
- **Execução** — comandos reutilizáveis e genéricos (sem os IDs de uma execução específica)
- **Detecção esperada** — tabela fase/ação → sinal → pipeline → lab → exercitado?
- **Resposta** — contenção / erradicação / forense, com link para `runbooks/` e Lab 09
- **Risco residual** — o que não é pego hoje e o lab futuro que fecha
- **Referências** — TM, ADRs, evidências, README do lab
