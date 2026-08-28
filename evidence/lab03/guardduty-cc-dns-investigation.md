# Ataque 1 — DNS Command & Control: investigação cruzada no CloudTrail

**Lab:** 03 — GuardDuty
**Finding correlacionado:** `Backdoor:EC2/C&CActivity.B!DNS` — severidade HIGH (8.0)
**Instância:** `i-0a784c2586f40a2e5` (EC2 do Lab 01)
**Domínio consultado:** `guarddutyc2activityb.com` (domínio de teste oficial do GuardDuty)
**Janela do finding:** `EventFirstSeen` 2026-08-28T09:47:30Z → `EventLastSeen` 2026-08-28T09:47:52Z (`Count` = 4)

Depois de ler o finding (`get-findings`, JSON em
[`guardduty-cc-dns-finding.json`](guardduty-cc-dns-finding.json)), a investigação própria
usa o CloudTrail do Lab 02 para responder: **quem** estava na instância, **o que** mais
aconteceu na janela, e se a **credencial da role** da instância foi usada.

---

## 1. Quem abriu sessão na instância logo antes da query C&C?

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=StartSession \
  --start-time 2026-08-28T09:30:00Z --end-time 2026-08-28T10:00:00Z \
  --query 'Events[].{Time:EventTime,User:Username,Src:CloudTrailEvent}' --output json \
  | python3 -c "import sys,json; [print(e['Time'], json.loads(e['Src'])['userIdentity'].get('arn'), json.loads(e['Src']).get('sourceIPAddress'), json.loads(e['Src']).get('requestParameters',{}).get('target')) for e in json.load(sys.stdin)]"
```

**Saída:**

```text
2026-08-28T06:47:14-03:00 arn:aws:sts::230650392331:assumed-role/AWSReservedSSO_AdministratorAccess_38885c65ce5b219c/sergei 168.232.226.99 i-0a784c2586f40a2e5
```

**Interpretação:** sessão via Session Manager aberta às `09:47:14Z` (`06:47:14-03:00`) pela
identidade SSO `AdministratorAccess/sergei`, da origem `168.232.226.99`, com `target` =
`i-0a784c2586f40a2e5`. São **~16 segundos** antes do `EventFirstSeen` do finding
(`09:47:30Z`) — a sessão interativa é a origem direta do `dig`.

---

## 2. Tudo que envolveu a instância na janela do finding

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=i-0a784c2586f40a2e5 \
  --start-time 2026-08-28T09:00:00Z --end-time 2026-08-28T11:00:00Z \
  --query 'Events[].{Time:EventTime,Event:EventName,User:Username}' --output table
```

**Saída:**

```text
---------------------------------------------------------------
|                        LookupEvents                         |
+---------------------+-----------------------------+---------+
|        Event        |            Time             |  User   |
+---------------------+-----------------------------+---------+
|  TerminateInstances |  2026-08-28T07:01:00-03:00  |  sergei |
|  AssumeRole         |  2026-08-28T06:43:45-03:00  |  None   |
|  AssumeRole         |  2026-08-28T06:43:45-03:00  |  None   |
|  RunInstances       |  2026-08-28T06:43:44-03:00  |  sergei |
+---------------------+-----------------------------+---------+
```

**Interpretação:** `RunInstances` às `09:43:44Z` (bate com o `LaunchTime` do finding,
`2026-08-28T09:43:44Z`), os dois `AssumeRole` são a montagem do instance profile, e
`TerminateInstances` às `10:01:00Z` é o cleanup pós-exercício (~14 min após o finding).
Nenhuma ação de rede/API anômala a partir da instância na janela — coerente com um
ataque que é só um lookup de DNS.

---

## 3. A credencial da role da instância (`awssec-lab01-role-ec2-app`) fez alguma chamada?

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=awssec-lab01-role-ec2-app \
  --start-time 2026-08-28T09:00:00Z --end-time 2026-08-28T11:00:00Z \
  --query 'Events[].{Time:EventTime,Event:EventName,Source:EventSource}' --output table
```

**Saída:**

```text
(vazio — nenhum evento)
```

**Interpretação:** a credencial temporária do instance profile
(`awssec-lab01-profile-ec2-app` → `awssec-lab01-role-ec2-app`) **não** fez nenhuma chamada
de API na janela. O C2 DNS não veio acompanhado de abuso de credencial — não há
movimentação lateral nem escalonamento a partir da role da instância.

---

## Conclusão

| Pergunta | Resposta |
|---|---|
| **O quê** | Query DNS para `guarddutyc2activityb.com` (domínio de C2 conhecido), 4 ocorrências em 22 s |
| **Quando** | 2026-08-28T09:47:30Z – 09:47:52Z |
| **Qual recurso** | EC2 `i-0a784c2586f40a2e5` (subnet `subnet-06330a363e382093c`, SG `awssec-lab01-sg-ec2-app`) |
| **Origem** | Sessão SSM interativa aberta 16 s antes pela identidade SSO `AdministratorAccess/sergei` de `168.232.226.99` |
| **Impacto** | Nenhum — domínio de teste do GuardDuty, `Blocked: false` mas sem conexão de dados; role da instância inerte |
| **Contenção** | Encerrar a sessão SSM (nada foi instalado) + `TerminateInstances` (feito às 10:01:00Z). No cenário real: isolar o SG — automação no Lab 09 |

### Lacunas conscientes (viram labs futuros)

- **Qual processo** dentro da instância fez o lookup — o GuardDuty não diz sem Runtime Monitoring → **Lab 13**.
- **DNS query logs consultáveis** de forma dedicada → **Lab 06** (Route 53 Resolver query logging).
- **Grafo de relação** entre as entidades do finding → **Lab 10** (Detective).
