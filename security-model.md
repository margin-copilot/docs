# Security model

How a user's identity travels through Margin Copilot, and what each service checks. Code: `shared` (token check, request context, OBO), `orchestrator`, `data-agent`. Setup: app registrations and managed identities from scripts in the infra repo; every name is configurable (D-026).

## One request, end to end

```mermaid
sequenceDiagram
  autonumber
  participant U as User (browser sign-in)
  participant C as Client app (allow-listed)
  participant O as orchestrator (external ingress)
  participant E as Entra ID
  participant D as data-agent (internal ingress)
  participant G as Microsoft Graph
  U->>C: sign in (MFA)
  C->>E: token for orchestrator / access_as_user
  C->>O: POST /chat + token (aud = orchestrator)
  O->>O: check signature, issuer, tenant, aud, scp, azp
  O->>E: OBO: user token + managed-identity assertion
  E-->>O: token for data-agent (same user)
  O->>D: A2A SendMessage + new token (aud = data-agent)
  D->>D: same checks; caller stored for this request
  D->>E: OBO from the tool: token for Graph User.Read
  D->>G: GET /me as the user
  G-->>D: display name
  D-->>O: "data-agent sees <name>"
  O-->>C: answer
```

## What every service checks

The `shared` token check is the only one in the project:
- The signature is RS256 against Entra's published keys.
- The issuer is our tenant's v2 issuer, and `tid` matches.
- `ver` is 2.0.
- `aud` is this service's app ID.
- `scp` contains `access_as_user`.
- The calling app (`azp`) is on this service's allow-list: the client app for the orchestrator, the orchestrator for the data-agent.

The issuer is checked before any key lookup, so a foreign token never makes us fetch keys. An untrusted token gets 401; a trusted token with the wrong scope or caller gets 403.

## Tokens never travel further than one hop

Each service exchanges the incoming token for a new one addressed to the next service (OBO), so a stolen token only works where it was meant to go. Microsoft Graph tokens are forwarded and never parsed.

## No secrets

Each confidential app authenticates to Entra with a federated credential that trusts its own user-assigned managed identity (issuer = the tenant's v2 endpoint, subject = the identity's principal ID, audience `api://AzureADTokenExchange`). There are no client secrets or certificates.

## The caller inside a service

`AuthMiddleware` stores the validated caller and token in a request-scoped context variable. a2a-sdk (from 1.2.3) runs the agent executor inside a copy of the request's context, so a tool reads the caller with `current_request()`, and concurrent requests never see each other. Authorization facts come from the validated token only, never from the message or a model.

## Data: region security in Azure SQL

Sales data lives in an Azure SQL free-offer database on an Entra-only server (no SQL passwords). T-SQL row-level security filters every user, the admin included.
- **The policy:** `rls.region_policy` filters every regional table (`fact_sales`, `supplier_costs`, `promotions`, `price_history`, `competitor_prices`).
- **How it filters:** the function `rls.fn_region_filter` keeps a row only if the caller's sign-in name (`ORIGINAL_LOGIN()`) maps to that region, or to `*`, in `rls.user_region`.
- **The mapping:** built from settings at load time, so no tenant UPN is in the repo.
- **Users and roles:** each test user has a database user in `pricing_readers`, which reads `dbo` and is denied the `rls` schema.
- **Connections:** clients connect with their own Entra token, and pooling is off, so one user's connection is never reused for another. The firewall admits the laptop's IP only, until milestone 4.
- **Proof:** `evals/live/rls_check.py` signs in as three users and compares what each sees.
- **Residual risk: inference through errors.** RLS filters rows, but a crafted query can still raise errors that reveal values in rows the filter hides. Microsoft documents this; for example, a divide-by-zero on a hidden row. A test user with direct SQL access can try it today. From milestone 4, `run_sql` returns a generic error and never passes SQL error text to the model or the user (eval case A-20), and milestone 11 tests it adversarially.
- **Reference tables:** `dim_region` and `dim_store` carry `region_id` but aren't filtered; region and store lists aren't sensitive. Every other `dbo` table with `region_id` is filtered automatically (`rls.regional_tables()`).

## Data agent: run_sql

- **Who reads:** the user. The data agent exchanges the caller's token for Azure SQL (OBO) for every query, so RLS filters by the signed-in user. The data agent's own identity calls only the model (Foundry, keyless) and never the database.
- **What it may run:** margins through one tested, parameterized query (`margin`); anything else as one SELECT, parsed with sqlglot and checked against the eight pricing tables, with no impossible date literals, comments, control characters or T-SQL keywords as names (`domain/sql_guard.py`). The database is the second layer: test users hold only SELECT on `dbo` and are denied the `rls` schema.
- **No shared connections:** pooling is off, and every query opens and closes its own connection with its own token.
- **Errors:** errors raised while reading rows (divide by zero, conversions) reach the model and the user only as `query failed`. Errors raised before any row is read (syntax, unknown names) go back to the model, matched as whole known messages, because their text names only what the query wrote. Logs keep the exception type for queries, and the text of connect failures (server, client IP, error number). The residual risk of inference through errors (above) remains: error vs no error is one bit per query (milestone 11).
- **Region awareness:** a query run as the user finds the regions RLS shows. The model is told them, and code sets the refusal label from them and the facts the model reports (`domain/refusal.py`). It's a label, never a permission: the rows are filtered by the database either way.
- **Agent output is untrusted:** the reply travels as the shared `AgentReply` contract, and the orchestrator validates it (fields, refusal values, 4,000 characters). Anything else becomes a 502.
- **Network:** the SQL server admits the laptop and the data agent's outbound IPs (181 shared platform addresses, D-034); never "Allow Azure services".

## Policies: group trimming

- **Who reads:** the policy agent's own identity reads the AI Search index (Search Index Data Reader), always filtered by the caller's groups from the validated token (D-037). Search is keyless (`disableLocalAuth`); the admin who pushes the corpus holds the only write roles.
- **The filter:** `group_ids/any(g: search.in(g, '<ids>', ',')) and is_fixture eq false`. Group IDs reach it only after GUID parsing, so nothing else reaches OData. Test fixtures (TEST-01, milestone 11) never reach production queries.
- **Restricted documents:** PP-05-N (North supplier terms) is indexed for the North and pricing directors, PP-06 (margin floors) for directors only. Managers don't learn they exist: a question about them gets "no policy you can open covers that".
- **The model can't widen access:** it sees only the clauses the filter returned, and code drops any citation it wasn't given (at most 12 kept). Code maps the model's `found_policy` to the refusal, and an answer whose citations were all dropped becomes "no policy you can open covers that" (`no_data`). A token whose group list overflowed gets nothing (`no_access`).

## Proposals: drafts and approvals

- **Agents only draft.** The action agent's app is on proposals-api's draft allow-list only. Listing, approving and rejecting accept only apps people use (the CLI now, the web app at milestone 8). Each route group has its own instance of the shared token check, so an agent's token never reaches a decision.
- **Every fact behind a decision is verified by proposals-api (D-039):**
  - role and region come from the `groups` claim;
  - tier and current price come from Azure SQL, read as the user;
  - the percent is computed exactly, and the approver needed is stored at draft time.
- **Fail closed:**
  - a group overage, no region group, or two region groups without the directors group get 403;
  - a price row-level security hides is "no current price", never a fallback;
  - another region's manager learns nothing about a proposal, not even whether it exists.
- **One decision per proposal:** a decided proposal answers 409, and every update carries the entity's ETag, so two people can't decide it at once.
- **Storage is keyless:** shared keys are off, and only proposals-api's identity (Storage Table Data Contributor) can touch the `proposals` table.
- **Known limits:**
  - approval changes the proposal's status, not prices in the database;
  - the price is the one at draft time;
  - PP-04 §2.2 (30-day rule), §2.3 (reason code) and §3.1's price index aren't checked by code. The approver checks them.

## Network

All apps share one Container Apps environment with peer-to-peer encryption on. Only the orchestrator and proposals-api have external ingress (people reach them; proposals-api's routes still accept only the allow-listed apps). The data, policy and action agents answer only inside the environment (404 from outside). Container Apps authenticates apps to each other but doesn't authorize them; the token checks above do.

## Tests and the local issuer

`LocalIssuer` signs tokens with a key that lives only in the test process, and services trust it only when `ADAPTERS=fake`. Unit tests cover each rejection case. The live check (`evals/live/identity_hop.py`) proves the deployed path:
- A real user crosses the hop.
- A real token from an unlisted app gets 403.
- A locally signed token gets 401.
- The data-agent can't be reached from outside.

## Known limits

- There is no VNet or private endpoint (cost); every endpoint still requires an Entra token.
- OBO results aren't cached, so each hop calls Entra once per request.
- The agent card (`/.well-known/agent-card.json`) is served without a token, but only inside the environment (D-028).
