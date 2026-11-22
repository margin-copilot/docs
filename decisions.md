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
| D-008 | Custom `run_sql` with T-SQL RLS (Lakehouse at first; Azure SQL since D-031) | 2026-11-15 |
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
| D-026 | Everything account-specific is configuration | 2026-11-16 |
| D-027 | App registrations by script, not Graph Bicep | 2026-11-16 |
| D-028 | Agent card served without a token, inside the environment only | 2026-11-16 |
| D-029 | Eval cases first, gated by milestone; the chat response contract | 2026-11-19 |
| D-030 | Plain-Python generator | 2026-11-19 |
| D-031 | Azure SQL free offer for the data, with T-SQL RLS | 2026-11-19 |
| D-032 | The data agent: gpt-5-mini with a tested margin tool and a checked run_sql | 2026-11-19 |
| D-033 | Cases that need the model and data run in a live suite | 2026-11-19 |
| D-034 | The data agent reaches Azure SQL through firewall rules for its outbound IPs | 2026-11-19 |
| D-035 | A router picks one agent per question before milestone 7 | 2026-11-20 |
| D-036 | The policy agent reads every clause the user may read, not the top few | 2026-11-20 |
| D-037 | Groups come only from the token; overage fails closed | 2026-11-20 |
| D-038 | The action agent extracts; code drafts and words the reply | 2026-11-21 |
| D-039 | proposals-api decides approvals from what it can verify | 2026-11-21 |
| D-040 | Plan, then call: one agent passes through, several are composed and number-checked | 2026-11-21 |
| D-041 | Our own conversation history in Table Storage, under the owner's oid | 2026-11-21 |

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
- **Amended (milestone 7, D-040):** the orchestrator plans each question and code calls the agents; a model loop over tools was rejected.

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
- **Superseded in part (milestone 3, 2026-11-19):** the Fabric trial was refused for the new tenant, so the data lives in the Azure SQL Database free offer (D-031). The T-SQL RLS and per-user token design is unchanged. The Fabric lakehouse and the Fabric Data Agent move to milestone 12, with paid F2 hours.

### D-009 Policy search on AI Search Free
- **Decision:** One search document per policy clause; hybrid + semantic query; filter `group_ids/any(...)` on the user's Entra groups from the token; `is_fixture eq false` in production.
- **Why:** The group filter is GA on every tier. Native ACL filtering is newer and possibly still preview.
- **Revisit if:** native permission filtering is confirmed GA and works on Free.
- **Amended (milestone 5, D-036):** while the corpus fits the prompt, the policy agent reads every clause the user's groups may read (`search_text="*"` plus the group filter) instead of a hybrid, semantic top-k; the filter and `is_fixture eq false` are unchanged.

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
- **Amended (milestone 7, D-041):** history lives in our own Table Storage table under the owner's oid, not in Foundry. The number rule is enforced in code for composed answers (D-040).

### D-012 Approval rules
- **Decision:** proposals-api decides who can approve: a manager can approve their own Tier B drafts up to +4% and Tier C up to +8%; the pricing director approves everything else and every Tier A change. Region and role come from the token.
- **Why:** Mirrors PP-01 §2 and PP-04 §3; deterministic and testable.

### D-013 Narrow scope
- **Decision:** Pricing, margin, promotions and policies for Riad Market only. Out of scope: short decline, no tool calls. In scope but not allowed: "your access doesn't include that", enforced by RLS and the search filter. In scope but no data: "no data recorded". General concepts are answered only from our policies.
- **Layers:** orchestrator instructions, no general tools (no web search, no code execution), Foundry content filters and Prompt Shields, eval cases.
- **Amended (milestone 8):** the data agent's label is set by code from the regions the question names (North/Northern, South/Southern, Center; not "Centre", a North store's name) against the regions the database shows the user; the model's own report of the regions asked is used only when the question names none, because it varied between runs.

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
- **Update (milestone 3):** the data lives in the Azure SQL Database free offer (D-031); Fabric appears only in milestone 12, on paid F2 hours.

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

### D-029 Eval cases first, gated by milestone; the chat response contract
- **Decision:** Eval cases are TOML data in the `evals` repo. Each names the first milestone where it must pass.
  - pytest runs every case against the system on fake adapters.
  - Cases up to `CURRENT_MILESTONE` must pass.
  - Later cases are `xfail(strict=True, raises=CaseFailed)`. They must fail only because the system answered differently from the case; a crash or an early pass fails CI.
  - A 200 case needs at least one positive check. Negative checks alone pass on a system that says nothing.
- **Response contract:** `POST /chat` returns JSON with these fields; services implement them by milestone 7:
  - `answer` (text);
  - `refusal`: `null`, `out_of_scope`, `no_access` or `no_data` (D-013);
  - `agents`: the agents called in this turn (`data-agent`, `policy-agent`, `action-agent`);
  - `citations`: clause IDs such as `PP-04 §3.2`.
- **Why:** The brief asks for the harness and failing tests first. Strict xfail makes "fails for the right reasons" checkable, and turns each finished milestone into a list of cases that must go green.
- **Known limits:**
  - Golden wording may be stricter than a correct answer; each milestone reviews its cases against real answers before bumping `CURRENT_MILESTONE`.
  - Golden cases need a model, and milestone 4 decides whether CI gets one keylessly or golden cases run only in the live suite.
  - Groundedness is checked through required facts and citations. Model-judged scores (azure-ai-evaluation: groundedness, tool-call accuracy) join the live suite in milestone 7.
- **Amended (milestone 7):**
  - **Model-judged scores** move to milestone 9. D-011's number rule is enforced in production by code for composed answers (D-040).
  - **G-C01** expects the +6% cost rise (or the new 5.62 MAD cost) and the 4% limit, not "7.25", which no data row or clause contains.
  - **A-14** waits for the TEST-01 fixture (milestone 11).
  - **A-21** (a resume of another user's conversation gets 404) runs live with `conversation_of`.
- **Amended after the milestone 2 review:**
  - **Server errors:** a 5xx where a case expects an answer is a `SystemFault`, never an expected failure. A broken downstream can't hide behind pending cases.
  - **Number matching:** numbers in `contains`/`not_contains` match whole (`0%` isn't in `30%`, `21.3` isn't in `121.3`). Words still match inside longer words.
  - **Forbidden alternatives:** each `|` alternative in `not_contains` is forbidden on its own.
  - **`not_agents`:** lists agents that must not be called. Example: the action agent when a prompt or a retrieved document asks for an approval.
  - **Field timing:** each response field arrives at the first milestone whose cases use it, not all at milestone 7:
    - `agents` and `refusal` at milestone 4;
    - `citations` and routing to the policy agent at milestone 5;
    - routing to the action agent at milestone 6.
  - **Harness changes ride along:** the evals harness (`system.py`) gains each new agent in the same milestone.
  - **Missing fields:** a response missing `agents` or `citations` fails any case that checks it, so contract drift is visible.
  - **Error reasons:** `expect.error` checks the reason on error responses (e.g. `calling app not allowed`).
  - **Partial answers:** `refusal` stays `null` whenever any part of the question was answered; the text says what's missing.
    `refusal` is set only when nothing could be answered.
  - **Not testable through `/chat`, so tested elsewhere:**
    - D-012 approval boundaries (e.g. 4.0% vs 4.1% on Tier B) are tested in proposals-api.
    - A conversation-resume hijack case (D-011) is added once conversation IDs exist (milestone 7).

### D-030 Plain-Python generator
- **Decision:** The `data` repo generates the dataset in plain Python (seed 42) and loads it with `mssql-python`, not with PySpark.
- **Why:** The generator and its 11 story checks run in CI and on a laptop in seconds, with no Spark and no capacity use. Dairy margins are calibrated to the preview's monthly targets, and the October bridge is checked.

### D-031 Azure SQL free offer for the data, with T-SQL RLS
- **Decision:** One Azure SQL Database on the free offer (serverless, `useFreeLimit`, `AutoPause` on exhaustion), on an Entra-only server whose admin is a native work account (`ADMIN_USERS`).
  - The firewall admits the laptop's IP only.
  - `riad-data` signs in through the `<prefix>-data-tools` public client. It creates a database user per test user plus a `pricing_readers` role (SELECT on `dbo`, DENY on `rls`). Then, in one transaction, it loads the tables, the rows and the policy.
  - The predicate compares `LOWER(ORIGINAL_LOGIN())` with `rls.user_region`, which is built from `ENTRA_DOMAIN` and `USER_REGIONS` at load time. Region `*` means all regions.
- **Why:**
  - The Fabric trial was refused ("A Fabric trial isn't available for your account"). F2 costs about $0.40/h and would limit experimenting on a $20 budget.
  - Azure SQL keeps the same security design (T-SQL RLS on the user's own token, OBO in milestone 4) at $0.
  - The tenant's personal-account Global Admin isn't used for data.
- **Rejected:** Fabric F2 now (cost); waiting for trial eligibility (undocumented, weeks to months).
- **Watch:**
  - RLS filters the admin (`dbo`) too, by design.
  - A changed laptop IP needs a re-deploy.
  - Milestone 4 decides how Container Apps reaches the database. Not the "Allow Azure services" rule, which admits every Azure customer.
  - The data-tools app keeps its Fabric API and Storage consents, and the admin keeps the Fabric Administrator role, for milestone 12.
  - `dim_store` carries `region_id` but isn't filtered: the store list isn't sensitive.
  - Milestone 4 adds the data-agent's Azure SQL consent for OBO.
  - RLS doesn't stop inference through errors (Learn: "carefully crafted queries"). `run_sql` must return generic errors only, from milestone 4 (eval case A-20).

### D-032 The data agent: gpt-5-mini with a tested margin tool and a checked `run_sql`
- **Decision:** data-agent is an Agent Framework agent (`agent-framework-core` 1.26.0, `FoundryChatClient`) on a Foundry project's gpt-5-mini deployment (`2025-08-07`, GlobalStandard, reasoning effort medium). It calls the model keylessly with its managed identity, which holds the Foundry User role; the account has local auth disabled.
  - **`margin(start, end, region?, category?, sku?)`:** net sales, cost of goods and margin % from one tested query. The arguments are checked and bound as parameters, the end date is inclusive, and the query always joins the product table for the category. Without a region it lists each region the user can see plus their total, so a manager's total is never presented as the chain's. The model must use it for every margin figure.
  - **`run_sql`:** sqlglot parses the SQL (T-SQL). The guard accepts one SELECT or set operation over the eight pricing tables in `dbo`. Not allowed: `INTO`, `APPLY`, temp tables, table-valued functions, other schemas, 3- or 4-part names, impossible date literals (2026-02-29), comments, control characters, alias column lists, and T-SQL keywords as unquoted names (sqlglot can read `FROM t EXEC('…')` as an alias while SQL Server runs a second statement).
  - **Connections:** each query exchanges the caller's token for Azure SQL (OBO) and opens its own connection: pooling off, a 30-second timeout, 200 rows, returned as CSV.
  - **What the model sees:**
    - rows;
    - the guard's reason;
    - errors raised before any row is read (syntax, unknown column or table, GROUP BY), matched as whole known messages: their text names only what the query wrote;
    - otherwise `query failed`, after which it rewrites the query more simply, at most twice.
    It never sees the text of errors raised while reading rows (A-20).
  - **The refusal label is set by code:**
    - before the model runs, `SELECT DISTINCT region_id FROM dbo.fact_sales` as the user finds the regions RLS allows;
    - the model reports `regions_asked` and `found_data` (a figure the question asks for was found);
    - `domain/refusal.py` turns those into `no_access`, `no_data` or none, the same way every time;
    - a user who sees no region gets `no_access` without a model call;
    - `out_of_scope` is left to the orchestrator's scope rules (milestone 7).
  - **The reply:** the shared `AgentReply` (pydantic, at most 4,000 characters, no unknown fields), which the orchestrator validates again.
  - **Limits:** 8 model round trips and 8 tool calls per question. Failures reach the caller as the fixed message `data-agent failed`.
  - The milestone-1 `whoami` tool and its Graph grant are removed.
- **Why:**
  - The `run_sql` rule in `CLAUDE.md`. RLS on the user's own token stays the authorization; the guard and the tools limit the query's shape, not which rows it sees.
  - Database errors raised while reading rows can reveal rows RLS hides (A-20).
  - **Live runs showed where a model can't be trusted to be consistent, and each gap moved into code:**
    - the model's own refusal labels wobbled on right answers;
    - its hand-written SQL once forgot the product join, a false number;
    - it gave up on its own SQL typos it couldn't see;
    - it repeated an impossible February date that only fails at run time.
- **Rejected:**
  - Foundry prompt agents: service-managed, and per-user OBO tools need our code anyway.
  - The `agent-framework` meta package: about 40 provider packages, many of them beta.
  - Showing errors raised while reading rows to the model.
  - A database view of the user's own mapping: a data change, when the probe works on the existing tables.
  - Gating on a pass rate: the owner accepts no regressions or false results (D-033).
- **Model choice is provisional:** made by constraints, not a comparison.
  - On the free trial only gpt-5-mini, gpt-4.1-mini and o4-mini (retiring) have chat quota.
  - gpt-5-mini is a reasoning model with tools and structured output, at $0.25 / $2.00 per million tokens, supported until July 2027.
  - The roadmap's open question (gpt-5-mini or gpt-6-luna, by eval scores and cost) stays open until the account upgrade; the live suite is how to settle it.
- **How it was calibrated:**
  - **Prompt rules, from runs 1 to 3 (14/22, then 6/8, then 2/2):**
    - read `price_history`;
    - compare before and after a change's date, with a clean "before" period, for every figure;
    - "current" means the latest data;
    - name products by name;
    - "above normal" is a ratio;
    - number formats;
    - everyday product names;
    - the headline figure first.
  - **Then the structural changes above,** until three consecutive full runs passed 22/22.
  - No expected answer is written into the prompt. One calendar fact (the Ramadan 2026 dates) is; a calendar table in the database would be the general fix.
- **Watch:**
  - **The schema is described twice:** tables in the `data` repo, their description in the prompt and the guard. A new table fails closed (the guard rejects it). A column whose meaning changes would give numbers that look right but aren't. The fix is column descriptions in the database, read at startup.
  - The unit tests' scripted model uses Agent Framework's private `_inner_get_response`; re-check it on upgrades.
  - Error vs no-error still leaks one bit per query (milestone 11).
  - Model answers drift between runs, so every milestone re-runs its live gate.

### D-033 Cases that need the model and data run in a live suite
- **Decision:** cases carry `suite = "ci"` (the default) or `"live"`.
  - Live cases are skipped in CI. `live/run_cases.py` runs them on the laptop against the deployed system, with one browser sign-in per test user, and prints every answer.
  - The milestone gate (owner, 2026-11-20: no regressions or false results): every live case up to `CURRENT_MILESTONE` passes in **three consecutive full runs**. A single passing run can be luck.
  - CI keeps the plumbing and security cases on fakes, plus every service's unit tests (the data agent's against a scripted model).
  - All 22 milestone-4 cases are live.
- **Why:**
  - Their answers depend on the real model and the real row-level security; a fake would test the fake.
  - CI can't sign in as test users (MFA, D-019).
  - A CI model would need GitHub OIDC, a Foundry role and a copy of the data, and would cost money on every push.
- **Rejected:** Foundry through OIDC in CI with a SQLite copy of the data (diverges from T-SQL RLS); scripted model answers in the eval suite (prove nothing).
- **Closes** D-029's open question, and milestone-2 deferred items 2–4: fake-mode factories and persona UPNs are no longer needed.
- **Sign-ins are remembered:** each test user signs in through the browser once. `msal-extensions` keeps the tokens encrypted in the OS keychain (macOS: Keychain item `msal-extensions`; forget them with `security delete-generic-password -s msal-extensions`), so later runs are silent. A token is used only for the account whose name matches the case's persona.
- **Revisit at milestone 10:** deploys gated by evals would need non-interactive test-user tokens for a scheduled live run.

### D-034 The data agent reaches Azure SQL through firewall rules for its outbound IPs
- **Decision:** `infra/scripts/sql-allow-apps.sh` adds one SQL firewall rule per outbound IP of the data-agent container app (`properties.outboundIpAddresses`) and removes stale ones. Run it after every apps deploy. The laptop's rule stays. No "Allow Azure services".
- **Why:**
  - A VNet-integrated environment with a `Microsoft.Sql` service endpoint means recreating the environment, and it bills managed resources (a static IP and a load balancer): about $22–40 a month even at zero replicas.
  - A private endpoint adds about $7.30 a month on top of that VNet. Both break the $20 budget.
  - Entra-only authentication, per-user OBO and RLS are the real controls; the IP rules only narrow who can reach the login endpoint.
- **Trade-off:** the app's `outboundIpAddresses` lists **181** addresses in France Central (Azure SQL allows up to 256 server-level rules). They can change, and they're shared platform IPs. Other customers' apps in the region could reach the server, but would still need an Entra token for one of its database users. That's far narrower than "Allow Azure services", which admits any Azure subnet.
- **Watch:** after any change, a question fails with 502 and `connect failed: ... 40615` in the data agent's log; re-run the script.
- **Revisit if** the budget allows a VNet, or at milestone 10.

### D-035 A router picks one agent per question before milestone 7
- **Decision:** the orchestrator makes one gpt-5-mini call (reasoning effort low, structured `{"agent": "data-agent" | "policy-agent"}`) to pick the agent; that agent's reply passes through unchanged, citations included. Its instructions carry tie-breaks for questions that sound like the other side: who approved a change is data, whether something was allowed is policy, "our price index" is a data figure while the price index target is policy.
- **Why:** milestone 5 needs routing (D-029), and passing the chosen reply through can't introduce a false number. A misroute shows up in the live gate: milestone 4's 23 data cases must keep passing.
- **Rejected:** calling both agents and merging (twice the cost, noisy answers, muddled refusal labels); keyword rules (fragile); milestone 7's full orchestration now (answer composition before scope rules and conversations exist).
- **Result:** the live gate passed 37/37 three runs in a row after one tie-break was added (G-D09, "our price index").
- **Revisit at milestone 7:** questions that need both agents.
- **Amended (milestone 6):** four routes. `action-agent` drafts price changes. `approvals` (approve, reject, apply or list proposals) gets a fixed answer from code pointing to the approval screen, and no agent is called (A-16, A-17). A role claimed in the message changes nothing.
- **Amended (milestone 7, D-040):** six routes, one per question: `data-agent`, `policy-agent`, `data-and-policy`, `action-agent`, `approvals` and `out_of_scope`. A two-field plan (`route` plus an agent list) and policy examples placed inside the approvals line both sent policy questions to approvals in the gate. The single-choice shape fixed that.

### D-036 The policy agent reads every clause the user may read, not the top few
- **Decision:** per question, the policy agent loads every clause the caller's groups may read (46 clauses, about 5,000 tokens) and the model answers from them, citing clause IDs. Code keeps only citations of clauses it handed the model (brackets and stray spaces stripped, at most 12) and sets the refusal: `no_data` when no clause covers the question, or when an answer cites nothing the caller may read.
- **Why:** retrieval can't miss a relevant clause, so it can't turn into a false "no policy covers that". The security property is the same group filter.
- **Revisit when** the corpus outgrows the prompt (about 200 clauses): hybrid and semantic search (D-009). Semantic ranker is available on Free in France Central.

### D-037 Groups come only from the token; overage fails closed
- **Decision:** `shared` v0.3.0 reads the `groups` claim from the validated token into `Caller.groups`; an overage indicator (`_claim_names` naming `groups`, or `hasgroups`) empties it and sets `groups_overage`. The policy agent answers `no_access` to an overage without reading anything, and filters on GUID-checked group IDs only. Only the policy agent's app registration requests `groupMembershipClaims: SecurityGroup`: on-behalf-of tokens follow the resource's manifest.
- **Why:** the region and role behind a policy's audience are authorization facts; `CLAUDE.md` takes them only from the validated token, never from a model or a request body.
- **Watch:**
  - A user in more than 200 groups sees no policies until the policy agent learns to read groups from Microsoft Graph.
  - Group changes reach tokens only as they renew (about an hour): removing someone from a group isn't instant.

### D-038 The action agent extracts; code drafts and words the reply
- **Decision:**
  - gpt-5-mini fills `{is_draft, product, region, new_price, change_pct}` (structured output, reasoning low, no tools).
  - Code sends the draft to proposals-api (`POST /drafts`, on-behalf-of) and writes the reply from fixed sentences built from the stored proposal: product, region, old → new price, percent, who may approve, and the clause.
  - The manager sentence never contains "director", so a case expecting the director can't pass on the wrong approver.
- **Why:** a reply the model writes could call a draft approved or misstate the percent or the approver: a false result. Fixed wording from the stored proposal can't.
- **Rejected:** a tool-calling agent writing its own reply.
- **Result:** the live gate passed 42/42 three runs in a row on the first gate, with no case-wording changes, and again after the final-review fixes.

### D-039 proposals-api decides approvals from what it can verify
- **Decision:**
  - **Role and region** come from the token's `groups` claim (the D-037 pattern, `groupMembershipClaims` on the proposals-api app), mapped by `REGION_GROUPS`: north, center, south and directors, four distinct group IDs.
  - **Tier and current price** come from Azure SQL, read as the user (on-behalf-of, row-level security). A draft request can't carry either.
  - **The percent** is exact `Decimal` arithmetic. The approver needed is decided once, at draft time, and stored.
  - **Two caller allow-lists in one service:** drafts accept only the action agent's app; listing and decisions accept only apps people use (the CLI now, the web app at milestone 8). These are two instances of the shared token check, not a second check.
- **Conservative where checks are missing:**
  - every price cut needs the director (PP-04 §3.5's margin-floor check needs PP-06 data);
  - every fresh-produce increase (tomatoes, potatoes, onions, oranges) needs the director under PP-04 §3.4, without the tier caps §3.4 lifts (its price index ≤ 105 isn't checked).
- **Percents for people:** two decimals, and rounding never lands on a limit (0, 3, 4, 8, 10%) the exact value isn't on, so the figure can't contradict the approver. Prices are stored in cents.
- **Hard caps:** a draft over Tier A +3% (§3.1) or Tier B +10% (§3.2) is refused with the clause, since nobody may approve it.
- **Groups vs USER_REGIONS** (milestone 3's open item): Entra groups are the source of truth for roles. SQL's mapping must also allow the price read, so a disagreement fails closed.
- **Known limits:**
  - approval changes the proposal's status, not the database's prices;
  - the price is the one at draft time;
  - the proposer is stored as an object ID;
  - **policy checks proposals-api doesn't make:** PP-04 §2.2 (one increase per product and region in 30 days), §2.3 (a reason code), and §3.1's price index ≤ 102 for Tier A. The person approving checks these.
- **Why:** who may approve is an authorization decision, so `CLAUDE.md` allows it only from the validated token and data the service reads itself, never from a model or a request body.

### D-040 Plan, then call: one agent passes through, several are composed and number-checked
- **Decision:** One gpt-5-mini call routes each question to one of six routes: `data-agent`, `policy-agent`, `data-and-policy`, `action-agent`, `approvals`, `out_of_scope`. Code calls the chosen agents concurrently over A2A, with OBO.
  - **One agent:** its reply passes through unchanged.
  - **Two agents:** a composer call writes one answer from their replies. Code checks that every number in it appears in a reply or in what the user typed: a percentage against a percentage, clause IDs as IDs, never as numbers. It retries once naming what's ungrounded, and otherwise returns the replies side by side, as it does when the composer fails.
  - **Known gaps:** number words and date parts reused as figures aren't caught. A turn has 230 seconds; past that it's a 502 and nothing is stored.
  - Citations, `agents` and `refusal` are set by code. The refusal label applies only when every agent refused; `no_access` wins.
  - **Amended (milestone 8):** with two agents, the data agent's reply now leads unchanged and the composer writes only what the policies say below it (numbers still checked). Composed answers had dropped the data agent's headline figures or the policy's limits in about one gate run in three (G-D02, G-C01), and calibrating the prompt moved the omission between cases. When the data agent refuses with `no_access`, its reply answers the turn alone: beside a policy checklist it read as answered anyway (A-22).
  - **Approvals and out-of-scope questions** get fixed answers, with no agent called. No route pairs the action agent with another.
- **Why:** milestones 4–6's single-agent answers stay exactly as tested. A composed answer can't carry a number no agent gave (D-011), and drafts happen only when asked for.
- **Rejected:** an orchestrator agent looping over tools. It would rewrite every answer, cost more tokens, and nothing in the cases needs its sequencing.
- **Result:** the live gate passed 52/52 three runs in a row, after the calibration noted in D-035's amendment, and 53/53 again after the final-review fixes (with G-V01, a follow-up in the owner's own conversation).

### D-041 Our own conversation history in Table Storage, under the owner's oid
- **Decision:**
  - Turns live in the `conversations` table: PartitionKey = the validated token's `oid`, RowKey = conversation ID plus time.
  - Another user's conversation is simply not found. So are unknown, malformed and expired ones, all with the same 404.
  - A follow-up is rewritten into a standalone question from the last 10 turns (a condenser call), and agents stay stateless.
  - Conversations expire 7 days after their first turn.
  - The request body accepts only `question` and `conversation_id`, so history never comes from the client.
  - The orchestrator's identity holds a data role on this table only.
- **Why:** ownership is structural, not a check that could be forgotten. Exact control over what is kept, with no new service holding user answers.
- **Rejected:** Foundry-managed conversations. That's another service and SDK surface, and ownership would still be ours.
- **Known limit:** expired turns stay in the table until a cleanup job exists. The data is synthetic.

