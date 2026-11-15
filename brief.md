# Azure Agentic AI Project: brief

Personal project to learn the Azure agentic stack by building a secure multi-agent assistant. Written 2026-11-14, trimmed to project content on 2026-11-15.

This is the starting brief. Current decisions live in `decisions.md`, the plan in `roadmap.md`, and verified prices and product facts in `research/2026-11-docs.md`. Where this brief disagrees with them, they win.

---

## 1. Goal

Build an enterprise-style internal tool, not "chat with your PDF". The interesting work sits around the AI: security, evaluation, cost and failure handling.

Domain: retail pricing and margin. **Fully synthetic data.**

Example question: "Why did margin drop on dairy in the north region last month, and what does our pricing policy allow us to do?" It answers from structured data and policy documents, showing only data the signed-in user may see.

## 2. Concept: Secure Pricing & Margin Copilot

Original architecture idea (refined in `decisions.md`):
- **Orchestrator agent:** routes to specialists, asks clarifying questions.
- **Data agent:** Fabric lakehouse (sales, margin, regions). Fabric Data Agent if F2 is paid; otherwise a custom SQL tool.
- **Policy RAG agent:** Azure AI Search hybrid retrieval with semantic reranking over pricing policies; answers cite sources.
- **Action agent:** drafts a price-change proposal; **human approval required** before it is submitted.
- **Foundry:** model hosting and tracing.

What makes it enterprise-grade:
1. **Identity-aware answers:** Entra sign-in, on-behalf-of flow, RLS by region. A north-region manager must not see south data, even through clever prompting.
2. **Evaluation pipeline:** about 40 golden questions scoring groundedness, tool-call accuracy and refusal behavior, run in CI so regressions fail the build.
3. **Adversarial testing:** prompt injection (for example a poisoned policy document) and attempts to bypass RLS, with findings and fixes written up.
4. **Observability and cost:** trace every request, log tokens and cost per question, budget guardrail, cheaper-model fallback.
5. **Production basics:** Bicep, GitHub Actions, scale-to-zero hosting on Azure Container Apps, retries and graceful tool timeouts.

## 3. Free-tier notes

| Piece | Free? | Notes |
|---|---|---|
| Microsoft Entra ID | Free tier | App registrations, auth, test users and groups |
| Azure AI Search | Free tier | Small limits, enough for a demo index |
| Foundry models | Pay per token, cheap | New Azure accounts get starter credit |
| Fabric (lakehouse, notebooks, PySpark, Power BI, RLS) | 60-day free trial | No credit card needed |
| Fabric Data Agent | Not on the trial | Needs a paid F2+ capacity |

Data Agent options:
1. Pay for an F2 capacity for a few hours, build and test, then **pause** it (a paused capacity stops compute billing).
2. Skip the Data Agent and query the lakehouse SQL endpoint with a custom tool.

Budget: about $20, mostly reserved for F2 hours. Set an Azure budget alert on day one.

## 4. Working with Claude Code

The owner is the architect; Claude Code implements, and the owner reviews every diff.

1. `CLAUDE.md` holds the architecture, conventions and "never do" rules (no hardcoded keys, always add tests, small commits).
2. Build the eval harness and failing tests first, then implement until they pass.
3. Work in small steps, one agent or feature at a time.
4. After each milestone, write a short decision note.

Cautions:
- Azure AI SDKs and product names change fast. Read the current Microsoft Learn docs before writing SDK code.
- Review security-critical code line by line: the on-behalf-of flow, RLS enforcement, secrets handling.
- Secrets: managed identities or Key Vault; `.gitignore` and a secret scan before the first push; budget alert from day one.

## 5. Original research tasks

All done on 2026-11-14; results in `research/2026-11-docs.md`.

1. Current Microsoft product names and agent SDKs; pick one orchestration approach.
2. Fabric Data Agent prerequisites, data sources and per-user RLS.
3. The on-behalf-of pattern for querying Fabric as the signed-in user from Python.
4. Free-tier limits and prices: AI Search, Foundry models, Container Apps, F2.
5. Data Agent vs custom SQL tool.
6. Eval framework, golden set and adversarial cases.
7. Synthetic dataset schema.
8. Hosting target, IaC layout and CI.
9. Architecture diagram and decision log.
10. Whether Copilot Studio fits the budget.

## 6. Sources

- Microsoft Learn, Fabric trial: https://learn.microsoft.com/fabric/get-started/fabric-trial
- Fabric trial unsupported features: https://learn.microsoft.com/ar-sa/fabric/fundamentals/fabric-trial
- Fabric Community, Data Agent needs F2+: https://community.fabric.microsoft.com/t5/Data-Warehouse/Can-t-create-data-agents-in-this-workspace-An-admin-needs-to/m-p/4867356
- Fabric Community, pausing a capacity: https://community.fabric.microsoft.com/t5/Service/Can-t-create-data-agent/m-p/5110396
