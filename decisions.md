# Decision log

One entry per decision: what, why, what was rejected, and what would make us revisit it. Newest decisions go at the bottom. Sources for facts: `research/2026-11-docs.md`.

| ID | Decision | Date |
|---|---|---|
| D-001 | Learning project: Secure Pricing & Margin Copilot on synthetic Riad Market data | 2026-11-15 |
| D-002 | Microsoft Agent Framework (Python) for agents | 2026-11-15 |
| D-003 | Orchestrator calls specialists as tools; approval outside the LLM | 2026-11-15 |
| D-004 | One service per agent, plus a non-agent proposals-api | 2026-11-15 |
| D-005 | Azure Container Apps, not Kubernetes | 2026-11-15 |
| D-006 | A2A between services, behind a port | 2026-11-15 |
| D-007 | Entra OBO at every hop, caller allow-lists, no secrets | 2026-11-15 |
| D-008 | Custom `run_sql` over the Lakehouse SQL endpoint with T-SQL RLS | 2026-11-15 |
| D-009 | Policy search on AI Search Free with a group-ID filter | 2026-11-15 |
| D-010 | Proposals and conversation pointers in Azure Table Storage | 2026-11-15 |
| D-011 | Conversation history managed by Foundry, with ownership checks | 2026-11-15 |
| D-012 | Approval rules from PP-01 and PP-04, enforced in proposals-api | 2026-11-15 |
| D-013 | Narrow scope with three kinds of "no" | 2026-11-15 |
| D-014 | English-only corpus and data | 2026-11-15 |
| D-015 | Copilot Studio left out | 2026-11-15 |
| D-016 | One repo per service, public; private infra repo without secrets | 2026-11-15 |
| D-017 | Hosting: Azure (France Central), Fabric, GitHub | 2026-11-15 |
| D-018 | Web app: React + Vite + MSAL.js on Static Web Apps Free | 2026-11-15 |
| D-019 | CI evals on fake adapters with locally issued test tokens; live suite on the owner's laptop | 2026-11-15 |
| D-020 | Public docs repo as the hub, linked from every README | 2026-11-15 |
| D-021 | MIT license on every public repo | 2026-11-15 |
| D-022 | Master `CLAUDE.md` in the docs repo, symlinked into the workspace | 2026-11-15 |
| D-023 | App registrations are created in milestone 1, with their managed identities | 2026-11-15 |
| D-024 | Stay on the free account's spending cap until the upgrade is needed | 2026-11-15 |
| D-025 | GitHub organization `margin-copilot` holds all repos; CI runs the gitleaks CLI | 2026-11-15 |

---

### D-001 Learning project on synthetic data
- **Decision:** Build "Secure Pricing & Margin Copilot", an internal assistant that answers margin questions from sales data and pricing policy, shows each manager only their region, and drafts price changes a person must approve. Data and company (Riad Market) are fictional; store cities are real Moroccan cities; six planted stories.
- **Why:** Learn the Azure agentic stack end to end, with the parts that matter in real systems: identity, evaluation, cost and failure handling. $20 budget, 1–2 h a day.
- **Rejected:** "Chat with your PDF" demos (too shallow); any real company data.

### D-002 Microsoft Agent Framework (Python)
- **Decision:** Agents are built with Microsoft Agent Framework (MAF) 1.x, pinned.
- **Why:** GA since 2026-04-03; direct successor of Semantic Kernel and AutoGen; supports tools, MCP, A2A, OpenTelemetry and evaluation in one library.
- **Rejected:** Semantic Kernel (superseded), AutoGen (archived), Foundry Workflows (retire 2026-12-01), raw Responses API (we'd rebuild orchestration).
- **Revisit if:** a MAF release breaks something we can't pin around.

### D-003 Orchestrator calls specialists as tools; approval outside the LLM
- **Decision:** An orchestrator agent calls data-agent, policy-agent and action-agent as tools and writes one answer. The action agent only creates **pending** drafts. Approval is a plain endpoint in proposals-api.
- **Why:** Compound questions (data + policy + action) get one coherent, citable answer. In Python, tool approvals raised inside a child agent can't be resumed through the parent and "fail closed" (MAF "Agents as Tools" page). Approval as an endpoint is durable for days, needs no checkpoint store, and keeps the model away from commits.
- **Rejected:** Handoff orchestration. It returns control to the user whenever an agent doesn't hand off, splits answers across agents, and needs durable checkpoints for approvals.
- **Revisit if:** evals show the orchestrator routes badly and handoff rules would fix it.

### D-004 One service per agent, plus proposals-api
- **Decision:** Five Container Apps: orchestrator-agent, data-agent, policy-agent, action-agent, proposals-api. Hexagonal inside each.
- **Why:** Owner's choice, to learn secure service-to-service agent communication. proposals-api is separate because approval must live outside every agent, and the web app must reach it while agents stay internal.
- **Rejected:** Modular monolith (fastest) and a two-service split. Kept as fallbacks if time runs out.
- **Cost of the choice:** about 85–100 hours instead of 60–70; OBO at every hop; cold starts across up to four services.

### D-005 Azure Container Apps, not Kubernetes
- **Decision:** All services run in one Container Apps environment (Consumption plan, scale to zero).
- **Why:** Container Apps runs Kubernetes for us and gives internal ingress, per-app managed identity, service discovery by name and peer-to-peer encryption. AKS needs a node VM running around the clock, which breaks the budget.
- **Revisit if:** we need something Container Apps can't do. Nothing like that is known.

### D-006 A2A between services, behind a port
- **Decision:** The orchestrator talks to the agents over the A2A protocol (`agent-framework-a2a` with `a2a-sdk` 1.x). A2A sits behind an inbound port on each agent and an outbound port on the orchestrator.
- **Why:** Owner's choice; it's the standard agent-to-agent protocol and GA in Foundry. Agent cards describe each agent.
- **Known gaps:** The Python package is beta. Server authentication is ours to add ("your application assembles… authentication" in the MAF A2A hosting docs). Passing the caller's token to tools isn't built in (feature request microsoft/agent-framework#2958). Forwarded metadata "isn't an authentication boundary".
- **Plan:** Starlette middleware validates the token and stores it in a request-scoped context variable; tools read it for the next OBO exchange. Proven in the milestone 1 spike before anything depends on it.
- **Revisit if:** the spike fails or the beta API churns too much. Fallback: plain HTTPS with JSON contracts, one adapter per side.
- **Update (milestone 1, 2026-11-16):** both sides use `a2a-sdk` 1.3.0 directly while there's no model in the loop. `agent-framework-a2a` joins in milestone 4, when the orchestrator becomes a MAF agent; its `A2AAgent` takes per-user auth through an `httpx.Auth` that reads the same context variable (checked 2026-11-16). The context-variable plan works because a2a-sdk 1.2.3 and later run the executor inside a copy of the request's context. Proven by in-process tests and the live check.

### D-007 Entra OBO at every hop, caller allow-lists, no secrets
- **Decision:** Each service has its own app registration and user-assigned managed identity. Each hop exchanges the incoming user token for one addressed to the next service (OBO). Each service checks signature, issuer, `aud`, `scp` and the calling app (`azp`) against an allow-list. The OBO client credential is a federated credential on the managed identity. GitHub Actions log in with OIDC. Key Vault holds only what can't be keyless (possibly the AI Search query key).
- **Why:** The user's identity has to reach SQL three hops down so RLS applies. Container Apps authenticates apps to each other but doesn't authorize them, so authorization is ours.
- **Rejected:** Forwarding the same token everywhere (replay risk, services accept tokens not meant for them); client secrets; secrets in the private repo.
- **Known limitation:** no VNet or private endpoints (cost; AI Search Free can't). Every endpoint still requires an Entra token.

### D-008 `run_sql` over the Lakehouse SQL endpoint
- **Decision:** PySpark writes Delta tables into a Fabric lakehouse. data-agent queries the lakehouse SQL analytics endpoint, kept in **delegated mode**, with the user's OBO token (`https://database.windows.net//user_impersonation`) through `mssql-python`. T-SQL security policies filter every table that has `region_id`.
- **Why:** Runs on the free Fabric trial. The endpoint is read-only, a second safety layer behind the SELECT check. RLS applies to every user, admins included. No copy into a Warehouse.
- **Rejected:** Fabric Data Agent as the core (not on the trial; per-user OBO from Python is undocumented), now a stretch goal on F2 hours. Warehouse (extra copy step). User-identity mode (ignores T-SQL RLS).
- **Watch:** switching the endpoint mode deletes SQL roles; deny managers SELECT on `rls.user_region`.

### D-009 Policy search on AI Search Free
- **Decision:** One search document per policy clause; hybrid + semantic query; filter `group_ids/any(...)` on the user's Entra groups from the token; `is_fixture eq false` in production.
- **Why:** The group filter is GA on every tier. Native ACL filtering is newer and possibly still preview.
- **Revisit if:** native permission filtering is confirmed GA and works on Free.

### D-010 Azure Table Storage
- **Decision:** One storage account. Table `proposals` (PartitionKey = region, RowKey = proposal ID, status pending, approved or rejected) and table `conversations` (PartitionKey = user oid, RowKey = conversation ID).
- **Why:** The SQL endpoint is read-only. Table Storage stays up when Fabric capacity is paused or the trial ends, fits small key lookups, and costs cents.
- **Rejected:** A Warehouse table (down whenever Fabric is down).
- **Trade-off:** Fabric RLS doesn't cover it, so proposals-api checks the region from the token, with tests.

### D-011 Conversation history
- **Decision:** Only the orchestrator keeps history, stored by Foundry (service-managed session ID). Our `conversations` row maps our conversation ID to the service ID and the owner's oid. Last 10 turns go to the model; conversations expire after 7 days. History never comes from the browser.
- **Why:** Least code. MAF docs warn that service-side IDs aren't authorization boundaries, so ownership is checked on every resume.
- **Rule:** every number in an answer comes from a tool call in the current turn.
- **Revisit if:** we need exact control over retention, in which case we'd write our own `HistoryProvider`.

### D-012 Approval rules
- **Decision:** proposals-api decides who can approve: a manager can approve their own Tier B drafts up to +4% and Tier C up to +8%; the pricing director approves everything else and every Tier A change. Region and role come from the token.
- **Why:** Mirrors PP-01 §2 and PP-04 §3; deterministic and testable.

### D-013 Narrow scope
- **Decision:** Pricing, margin, promotions and policies for Riad Market only. Out of scope: short decline, no tool calls. In scope but not allowed: "your access doesn't include that", enforced by RLS and the search filter. In scope but no data: "no data recorded". General concepts are answered only from our policies.
- **Layers:** orchestrator instructions, no general tools (no web search, no code execution), Foundry content filters and Prompt Shields, eval cases.

### D-014 English only
- **Decision:** Policies, data and evals are English only. Another language later means a translation and language-detection layer, not a multilingual corpus.

### D-015 Copilot Studio left out
- **Decision:** No Copilot Studio front end.
- **Why:** The trial can't publish, and Teams needs licenses an individual tenant doesn't have.

### D-016 Repos
- **Decision:** Eleven repos in the GitHub organization `margin-copilot` (D-025): web, orchestrator, data-agent, policy-agent, action-agent, proposals-api, shared, data, evals, docs (public) and infra (private, non-secret config only). The docs repo was added by D-020.
- **Why:** Owner's choice. Public service repos mean public images, so Container Apps pulls them without a registry secret.
- **Cost of the choice:** contract changes span several PRs; `shared` is versioned by git tag.

### D-017 Hosting
- **Decision:** Azure in France Central (Container Apps, Static Web Apps, Foundry, AI Search, Storage, Key Vault, App Insights); Microsoft Fabric for the lakehouse and Power BI; GitHub for code, CI/CD and container images (ghcr.io); local development on the owner's laptop.
- **Why:** France Central has the cheapest F2 in the EU; Global model deployments; everything else on free tiers.

### D-018 Web app
- **Decision:** React + Vite + MSAL.js, two screens (chat, approvals), on Static Web Apps Free.

### D-019 Evals: CI on fakes, live suite locally
- **Decision:** CI runs the golden and adversarial suites with fake outbound adapters (data, search, proposals) and tokens issued by a local test issuer that the services trust only when `ADAPTERS=fake`. A live suite runs on the owner's laptop against real Fabric, AI Search and Entra after an interactive browser sign-in per test user (device code flow is blocked in new tenants since 2026-07-01).
- **Why:** New tenants enforce MFA through security defaults, so CI can't sign in as test users. Hexagonal ports make the fakes cheap.
- **Rule:** the test issuer is never trusted in a deployed environment; a test checks that the Azure configuration rejects its tokens.
- **Rejected:** Turning off MFA for test users (weakens the tenant); password-based sign-in (deprecated, fails with MFA).

### D-020 Public docs repo as the hub
- **Decision:** `margin-copilot-docs` (public) explains how the whole system works: architecture, identity and security model, agents, data and policies, evals, decision log, roadmap, and a run-it-yourself guide with teardown. Every service README links to it. Diagrams in Mermaid, rendered by GitHub; no docs site generator until it's needed.
- **Why:** With eleven repos, readers need one starting point. Cross-cutting behavior documented once can't contradict itself across READMEs.
- **Rules:** each fact lives in one place (service-specific details stay in the service README); behavior and docs change together; placeholders instead of real IDs.
- **Supersedes:** the open question of whether `docs/` moves into the infra repo.

### D-021 MIT license
- **Decision:** Every public repo carries the MIT license.
- **Why:** Others should be able to reuse the code and docs for their own projects; MIT is simple and permissive.

### D-022 Master `CLAUDE.md` in the docs repo
- **Decision:** From milestone 0, the workspace rules live in `margin-copilot-docs/CLAUDE.md`. The workspace folder keeps a symlink `CLAUDE.md` pointing to it. Each service repo can add its own short `CLAUDE.md` for service-specific rules.
- **Why:** The workspace folder isn't a repo, so a file there isn't versioned. Claude Code reads `CLAUDE.md` from parent folders, so the symlink still applies the rules in every repo.

### D-023 App registrations in milestone 1
- **Decision:** The per-service app registrations, exposed scopes and federated credentials are created in milestone 1, together with the managed identities they trust, not in milestone 0.
- **Why:** They're first used by the milestone 1 spike, and a federated credential can't point at a managed identity that doesn't exist yet.

### D-024 Stay on the free account's spending cap
- **Decision:** Keep the Azure free account until model quota or the 30-day limit forces the upgrade; upgrade by day 28.
- **Why:** The free account has a hard spending limit equal to the $200 credit. Pay-as-you-go has no spending limit at all, only budget alerts. Remaining credit carries over only until day 30.
- **Watch:** if the subscription is disabled before the upgrade, resources are re-enabled and billed after upgrading.

### D-025 GitHub organization
- **Decision:** All repos live in the free GitHub organization `margin-copilot`, named without a prefix (`margin-copilot/orchestrator`). Repos are created empty and get their MIT LICENSE locally, so every commit carries the owner's no-reply email. CI runs the gitleaks CLI (release binary, checksum-verified) instead of `gitleaks/gitleaks-action`, which needs a license key for organizations.
- **Why:** One place for the whole project, like a GitLab group; shorter names; an organization profile can act as the landing page; images publish under `ghcr.io/margin-copilot/`. Free plan, unlimited repos.
- **Rejected:** Prefixed repos under the personal account (scattered among other repos).

### D-026 Everything account-specific is configuration
- **Decision:** No code or doc names the owner's usernames, emails, home paths, tenant domain or Azure IDs. Scripts read account-specific values at runtime (tenant default domain from Graph, subscription from `az`, an existing budget's start date from Azure) or from the repo's gitignored `.env`; a committed `.env.example` lists every setting. Configurable so far: `ALERT_EMAIL`, `BUDGET_AMOUNT`, `BUDGET_NAME`, `AZURE_LOCATION`, `ENTRA_DOMAIN`, `TEST_USERS`, `TEST_GROUPS`, `GITHUB_ORG`. Azure resource and workspace names follow the same rule as they're added.
- **Why:** Privacy, and anyone can deploy the same code to their own Azure account and GitHub org without editing hardcoded names.
- **Watch:** Azure rejects a changed budget start date, so `deploy-budget.sh` reuses the existing budget's.

### D-027 App registrations by script, not Graph Bicep
- **Decision:** `infra/scripts/entra-apps.sh` (Azure CLI + Microsoft Graph REST) creates the app registrations, scopes, service principals, federated credentials and consent grants. It's idempotent, with `entra-apps-check.sh` as its test, like the test users.
- **Why:** The Microsoft Graph Bicep extension doesn't accept a personal Microsoft account as the deployer, and the owner administers the tenant with one. The script works with the same sign-in as everything else.
- **Revisit if:** the deployer becomes a work account; then Graph Bicep could hold the apps and the managed identities in one template.

### D-028 Agent card served without a token, inside the environment only
- **Decision:** Agents serve `/.well-known/agent-card.json` without a token; every other path requires one.
- **Why:** Clients fetch the card once to learn the endpoint, before any user is involved; it describes skills, not data. Internal ingress keeps it inside the Container Apps environment.
