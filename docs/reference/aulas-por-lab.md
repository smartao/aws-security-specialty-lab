# Aulas do curso a assistir antes de cada laboratório

Mapeamento das aulas de [`aulas-curso.txt`](aulas-curso.txt) (curso AWS SCS-C03)
para o **roadmap real de 20 laboratórios** do [`README.md`](../../README.md).

Cada lab tem:

- **Núcleo** — aulas que cobrem diretamente o serviço/tema do lab. Assistir antes de começar.
- **Apoio / revisão** — aulas de outro lab que ajudam no contexto ou que você reforça aqui.

Convenção: `N. Título` = número da aula no curso. Aulas *Hands On* e *Troubleshooting*
ficam junto da aula conceitual correspondente.

> **Labs 01 e 02 já concluídos.** O Lab 02 cobriu as aulas de logging/monitoramento base
> (ver abaixo) — elas viram pré-requisito assumido dos labs de Detecção.

---

## Fase 0 — Foundation ✅

### Lab 01 — Secure AWS Foundation ✅
Sem aula direta do curso (backend Terraform, VPC, IAM Identity Center, budgets).
Base conceitual: 143–144 (IMDS), 92–93 (NACL/SG), 87 (VPC Endpoints), 138 (STS).

### Lab 02 — Centralized Logging Foundation ✅
Aulas já assistidas (pré-requisito dos labs de Detecção):
- ✅ 14. Logging in AWS for Security and Compliance
- ✅ 15. CloudWatch - Unified CloudWatch Agent - Overview
- ✅ 17. CloudWatch - Unified CloudWatch Agent - Hands On
- ✅ 18. CloudWatch Unified Agent - Troubleshooting
- ✅ 19. CloudWatch Logs / 20. CloudWatch Logs Hands On
- ✅ 21. CloudWatch Alarms / 22. CloudWatch Alarms Hands On
- ✅ 23. CloudWatch Contributor Insights
- ✅ 29. CloudTrail / 30. CloudTrail Hands On
- ✅ 31. CloudTrail - Data Lake
- ✅ 32. CloudTrail - EventBridge Integration
- ✅ 33. CloudTrail for SysOps
- ✅ 34. CloudTrail to CloudWatch Metrics Filter - Example
- ✅ 35. CloudTrail - Integration with Athena
- ✅ 36. Monitoring Account Activity

---

## Domínio 1 — Detecção (Labs 03–07)

### Lab 03 — GuardDuty ✅
**Núcleo**
- ✅ 5. Amazon GuardDuty
- ✅ 6. Amazon GuardDuty - Findings & Automation
- ✅ 7. Amazon GuardDuty - Multi-account Strategy
- ✅ 8. Amazon GuardDuty - Advanced

**Apoio / revisão**
- ✅ 24. Amazon EventBridge / 25. Amazon EventBridge - Hands On *(roteamento de findings)*
- ✅ 32. CloudTrail - EventBridge Integration *(revisão do Lab 02)*

### Lab 04 — Security Hub
**Núcleo**
- ✅ 9. Security Hub Overview
- ✅ 10. Security Hub - Advanced
- ✅ 13. Amazon Inspector *(findings de Inspector agregam no Security Hub)*

**Apoio / revisão**
- ✅ 5–6. GuardDuty *(fonte de findings — feito no Lab 03)*
- ✅ 227. AWS Config - Remediation Examples *(prévia; Config completo no Lab 20)*

### Lab 05 — Security Lake + OCSF
> O curso **não tem aula dedicada a Security Lake**. Assistir as aulas de consulta/consolidação
> de logs, que é o que o lab exercita (ingestão OCSF + query).

**Núcleo**
- ⚠️ 26. Amazon Athena / 27. Amazon Athena - Hands On / 28. Amazon Athena - Troubleshooting
- ⚠️ 35. CloudTrail - Integration with Athena
- ⚠️ 48. OpenSearch / 49. OpenSearch - Advanced

**Apoio / revisão**
- ⚠️ 31. CloudTrail - Data Lake *(revisão do Lab 02)*
- ⚠️ 12. Detective - Architectures *(padrões de arquitetura de análise)*

### Lab 06 — Security Analytics
**Núcleo**
- ⚠️ 41. VPC Flow Logs / 42. VPC Flow Logs Hands On / 43. VPC Flow Logs - Advanced
- ⚠️ 44. VPC Traffic Mirroring / 45. VPC Traffic Mirroring - Architectures
- ⚠️ 46. VPC Network Access Analyzer
- ⚠️ 47. Route 53 - Query Logging
- ⚠️ 39. S3 Event Notifications / 40. S3 Event Notifications - Hands On

**Apoio / revisão**
- ⚠️ 23. CloudWatch Contributor Insights *(revisão do Lab 02)*
- ⚠️ 24–25. Amazon EventBridge *(revisão do Lab 03)*
- ⚠️ 26–28. Amazon Athena / 48–49. OpenSearch *(revisão do Lab 05)*

### Lab 07 — Macie + Data Discovery
**Núcleo**
- ⚠️ 37. Macie
- ⚠️ 38. Macie - Advanced

**Apoio / revisão**
- ⚠️ 39–40. S3 Event Notifications *(revisão do Lab 06)*
- ⚠️ 157–159. S3 Access Logs *(rastreamento de acesso a dado sensível; detalhe no Lab 18)*

---

## Domínio 2 — Resposta a Incidentes (Labs 08–10)

### Lab 08 — Incident Response Playbook
**Núcleo**
- ⚠️ 50. Definitions & Terms
- ⚠️ 51. Penetration Testing on AWS
- ⚠️ 52. DDoS Simulation Testing on AWS
- ⚠️ 53. Compromised AWS Resources
- ⚠️ 54. Compromised AWS Credentials
- ⚠️ 61. AWS Abuse Report

**Apoio / revisão**
- ⚠️ 55. EC2 Key Pairs & Remediating Exposed EC2 Key Pairs

### Lab 09 — Automated Incident Response
**Núcleo**
- ⚠️ 62. Systems Manager Overview
- ⚠️ 63. Start EC2 Instances with SSM Agent
- ⚠️ 64. AWS Tags & SSM Resource Groups
- ⚠️ 65. SSM Documents & SSM Run Command
- ⚠️ 66. SSM Automations

**Apoio / revisão**
- ⚠️ 24–25. Amazon EventBridge *(gatilho de automação — revisão do Lab 03)*
- ⚠️ 6. GuardDuty - Findings & Automation *(revisão do Lab 03)*
- ⚠️ 227. AWS Config - Remediation Examples *(prévia do Lab 20)*

### Lab 10 — Forensics + Root Cause
**Núcleo**
- ⚠️ 11. Amazon Detective
- ⚠️ 12. Detective - Architectures
- ⚠️ 56. EC2 Instance Connect
- ⚠️ 57. EC2 Serial Console
- ⚠️ 58. Lost EC2 Key Pair - Linux
- ⚠️ 59. Lost EC2 Key Pair - Windows
- ⚠️ 60. EC2 Rescue Tool for Linux & Windows
- ⚠️ 69. SSM Inventory & State Manager

**Apoio / revisão**
- ⚠️ 266. EBS - Data Volume Wiping *(higienização pós-incidente)*
- ⚠️ 35–36. CloudTrail com Athena / Monitoring Account Activity *(revisão do Lab 02)*

---

## Domínio 3 — Segurança de Infraestrutura (Labs 11–14)

### Lab 11 — AWS WAF + CloudFront
**Núcleo**
- ⚠️ 99. CloudFront Overview / 100. CloudFront Hands On
- ⚠️ 101. CloudFront - ALB/EC2 as an Origin
- ⚠️ 102. CloudFront - Geo Restriction
- ⚠️ 103. CloudFront - Signed URL & Cookies / 104. Hands On
- ⚠️ 105. CloudFront - Field Level Encryption
- ⚠️ 106. CloudFront - OAC & OAI
- ⚠️ 107. CloudFront - Other
- ⚠️ 108. WAF - Web Application Firewall
- ⚠️ 109. Shield
- ⚠️ 110. AWS Firewall Manager
- ⚠️ 111. WAF & Shield - Hands On / 112. WAF - Hands On
- ⚠️ 113. AWS Shield Advanced - Metrics
- ⚠️ 114. DDoS Attack Protection

**Apoio / revisão**
- ⚠️ 52. DDoS Simulation Testing on AWS *(revisão do Lab 08)*
- ⚠️ 115–117. API Gateway *(origem alternativa protegida por WAF)*

### Lab 12 — Network Security
**Núcleo**
- ⚠️ 75. Bastion Host / 76. Bastion Host - Hands On
- ⚠️ 77. NAT Gateway / 78. NAT Gateway - Hands On
- ⚠️ 92. NACL & Security Groups / 93. Hands On
- ⚠️ 94. Security Groups Outbound Rules & Managed Prefixes
- ⚠️ 95. Security Groups - Extras
- ⚠️ 119. Route 53 - DNSSEC
- ⚠️ 120. AWS Network Firewall / 121. AWS Network Firewall - Advanced

**Apoio / revisão**
- ⚠️ 41–43. VPC Flow Logs / 46. VPC Network Access Analyzer *(revisão do Lab 06)*
- ⚠️ 85–86. DNS Resolution Options in VPC *(detalhe no Lab 14)*

### Lab 13 — Secure Compute
**Núcleo**
- ⚠️ 143. EC2 Instance Metadata Overview / 144. IMDSv1 vs IMDSv2
- ⚠️ 70. SSM Patch Manager and Maintenance Windows / 71. Hands On
- ⚠️ 72. SSM Session Manager Overview / 73. Hands On
- ⚠️ 265. ASG Instance Refresh
- ⚠️ 268. EC2 Image Builder / 269. Hands On / 270. Troubleshooting
- ⚠️ 250. Elastic Container Registry (ECR) / 251. ECR Security
- ⚠️ 252. ECS Secret Management
- ⚠️ 253. EKS Concepts
- ⚠️ 254. Lambda Security
- ⚠️ 255. Lambda in VPC / 256. Hands On
- ⚠️ 257. Lambda Function URL / 258. Hands On
- ⚠️ 259. AWS Signer

**Apoio / revisão**
- ⚠️ 74. SSM Cleanup
- ⚠️ 220. AWS Nitro Enclaves *(detalhe no Lab 17)*

### Lab 14 — Hybrid / Private Connectivity
**Núcleo**
- ⚠️ 79. Site to Site VPN / 80. Hands On
- ⚠️ 81. Client VPN / 82. Client VPN - Client Authentication Types
- ⚠️ 83. VPC Peering / 84. Hands On
- ⚠️ 85. DNS Resolution Options in VPC / 86. Hands On
- ⚠️ 87. VPC Endpoints - Overview
- ⚠️ 88. VPC Endpoint Policies
- ⚠️ 89. VPC Endpoint - Examples
- ⚠️ 90. PrivateLink / 91. Hands On
- ⚠️ 96. AWS Transit Gateway
- ⚠️ 97. Direct Connect / 98. Direct Connect + S2S VPN
- ⚠️ 260. AWS Verified Access

**Apoio / revisão**
- ⚠️ 148. S3 - VPC Endpoint Strategy *(detalhe no Lab 18)*

---

## Domínio 4 — Identidade e Acesso (Labs 15–16)

### Lab 15 — IAM Least Privilege
**Núcleo**
- ⚠️ 123. IAM Policies in Depth
- ⚠️ 124. IAM Condition Operators
- ⚠️ 125. IAM Global condition context keys
- ⚠️ 126. IAM Permission Boundaries
- ⚠️ 127. IAM Policy Evaluation Logic
- ⚠️ 128. Identity-Based Policies vs. Resource-Based Policies
- ⚠️ 130. IAM MFA
- ⚠️ 131. IAM Credentials Report
- ⚠️ 135. IAM Security Tools / 136. Hands On
- ⚠️ 137. IAM Access Analyzer

**Apoio / revisão**
- ⚠️ 145. S3 - Authorization Evaluation Process
- ⚠️ 147. S3 - Samples S3 Bucket Policies
- ⚠️ 150. S3 - Block Public Access Settings

### Lab 16 — Advanced IAM
**Núcleo**
- ⚠️ 129. ABAC (Attribute based access control)
- ⚠️ 132. IAM Roles and PassRole to Services
- ⚠️ 133. IAM Roles Anywhere
- ⚠️ 134. IAM Trust Policies
- ⚠️ 138. STS Overview
- ⚠️ 139. STS Version 1 & Version 2
- ⚠️ 140. STS External ID
- ⚠️ 141. STS - Revoking IAM Role Temporary Security Credentials
- ⚠️ 142. Sample SCP
- ⚠️ 146. S3 - Cross Account Access and Canned ACL
- ⚠️ 149. S3 - Regain Access to Locked S3 Bucket

**Apoio / revisão**
- ⚠️ 160. Cognito User Pools / 161. Cognito Identity Pools / 162. Cognito User Pool User Groups
- ⚠️ 163. Identity Federation & Cognito / 164. SAML 2.0 Metadata File Troubleshooting
- ⚠️ 165–166. IAM Identity Center *(uso multi-conta detalhado no Lab 19)*

---

## Domínio 5 — Proteção de Dados (Labs 17–18)

### Lab 17 — KMS + Encryption
**Núcleo**
- ⚠️ 168. Encryption 101
- ⚠️ 169. CloudHSM / 170. CloudHSM - Advanced
- ⚠️ 171. KMS
- ⚠️ 172. KMS Multi Region Key
- ⚠️ 173. KMS Envelope Encryption
- ⚠️ 174. KMS Key Rotation
- ⚠️ 175. KMS Key Deletion
- ⚠️ 176. KMS Key Policies Deep Dive
- ⚠️ 177. KMS Grants
- ⚠️ 178. KMS Condition Keys
- ⚠️ 179. KMS Key Policies Evaluation Process
- ⚠️ 180. KMS Key Cross-Account Access
- ⚠️ 181. KMS Asymmetric Encryption
- ⚠️ 182. KMS API Calls Limits and Data Key Caching
- ⚠️ 183. KMS Encryption Context
- ⚠️ 184. KMS with EBS
- ⚠️ 185. EFS Encryption
- ⚠️ 186. KMS with ABAC
- ⚠️ 187. KMS with Parameter Store
- ⚠️ 220. AWS Nitro Enclaves

**Apoio / revisão**
- ⚠️ 129. ABAC *(revisão do Lab 16, base para a aula 186)*

### Lab 18 — Secure Data + Secrets
**Núcleo**
- ⚠️ 67. SSM Parameter Store Overview / 68. Hands On (CLI)
- ⚠️ 188. Secrets Manager / 189. Hands On / 190. Advanced
- ⚠️ 191. S3 Encryption / 192. Summary / 193. Default Encryption
- ⚠️ 194. S3 Bucket Policies Examples
- ⚠️ 195. S3 Bucket Key
- ⚠️ 196. Large File Upload to S3 with KMS Key
- ⚠️ 197. S3 Batch Encryption
- ⚠️ 198. S3 Object Lock & Glacier Vault Lock / 199. Deep Dive / 200. Hands On
- ⚠️ 201. S3 Lifecycle Rules (with S3 Analytics) / 202. Hands On
- ⚠️ 203. S3 Replication / 204. Hands On / 205. Notes
- ⚠️ 151. S3 Access Points / 152. Hands On
- ⚠️ 153. S3 Multi-Region Access Points / 154. Hands On
- ⚠️ 155. S3 CORS / 156. Hands On
- ⚠️ 157. S3 Access Logs / 158. Permissions / 159. Hands On
- ⚠️ 206. RDS & Aurora Security
- ⚠️ 211. ELB SSL Certificates / 212. Advanced
- ⚠️ 213. Network Load Balancer - TLS Listeners
- ⚠️ 214. AWS Certificate Manager (ACM) / 215. Hands On / 216. ACM - Advanced
- ⚠️ 217. AWS Backup / 218. Hands On
- ⚠️ 219. Amazon Data Lifecycle Manager
- ⚠️ 271. Redshift Security
- ⚠️ 272. DynamoDB - Time To Live (TTL)
- ⚠️ 252. ECS Secret Management

**Apoio / revisão**
- ⚠️ 207. Elastic Load Balancing Overview / 208–210. NLB / Sticky Sessions
- ⚠️ 171–183. KMS *(revisão do Lab 17 — criptografia em repouso)*
- ⚠️ 148. S3 - VPC Endpoint Strategy

---

## Domínio 6 — Governança e Fundamentos (Labs 19–20)

### Lab 19 — Multi-Account Security Governance
**Núcleo**
- ⚠️ 221. Organizations / 222. Hands On
- ⚠️ 223. AWS Organizations - IAM Policies & Tag Policies
- ⚠️ 224. AWS Control Tower
- ⚠️ 228. AWS Config - Aggregators
- ⚠️ 230. AWS Config - Organizational Rules
- ⚠️ 165. AWS IAM Identity Center / 166. Extras
- ⚠️ 167. AWS Directory Services
- ⚠️ 247. AWS Resource Access Manager (AWS RAM)
- ⚠️ 246. AWS Service Catalog

**Apoio / revisão**
- ⚠️ 7. GuardDuty - Multi-account Strategy *(revisão do Lab 03)*
- ⚠️ 10. Security Hub - Advanced *(administração delegada — revisão do Lab 04)*
- ⚠️ 142. Sample SCP *(revisão do Lab 16)*

### Lab 20 — Compliance + Secure Deployment
**Núcleo**
- ⚠️ 225. AWS Config / 226. Hands On
- ⚠️ 227. AWS Config - Remediation Examples
- ⚠️ 229. AWS Config - Conformance Packs
- ⚠️ 231. AWS Config - Use Cases
- ⚠️ 232. Trusted Advisor + Hands On
- ⚠️ 235. AWS Well-Architected Framework & Well-Architected Tool
- ⚠️ 237. Audit Manager
- ⚠️ 118. AWS Artifact
- ⚠️ 238. CloudFormation / 239. Hands On
- ⚠️ 240. CloudFormation - Service Role
- ⚠️ 241. CloudFormation - Stack Policy
- ⚠️ 242. CloudFormation - Dynamic References
- ⚠️ 243. CloudFormation - Termination Protection
- ⚠️ 244. CloudFormation - Drift
- ⚠️ 245. CloudFormation Guard
- ⚠️ 248. AWS Fault Injection Simulator (FIS)
- ⚠️ 249. AWS Resilience Hub

**Apoio / revisão**
- ⚠️ 233. AWS Cost Explorer / 234. AWS Cost Anomaly Detection
- ⚠️ 236. AWS Acceptable Use Policy (AUP)

---

## Aulas sem laboratório dedicado

Encaixe-as onde fizer sentido no seu ritmo — não bloqueiam nenhum lab.

| Aula | Onde revisar |
|---|---|
| 16. AWS Console UI Update | informativa, assistir a qualquer momento |
| 122. Amazon SES | Lab 20 (governança de e-mail/abuse) ou avulsa |
| 261. Glue Overview / 262. Glue Security | Lab 05/06 (pipelines de dados) ou avulsa |
| 263. Amazon WorkSpaces / 264. WorkSpaces - Security | Lab 14 (acesso remoto) ou avulsa |
| 267. CloudShell | Lab 09 (operação/IR) ou avulsa |
| Quizzes / provas de seção | avaliação, não são labs |
