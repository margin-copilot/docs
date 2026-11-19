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
- **The policy:** `rls.region_policy` filters every table with `region_id` (`fact_sales`, `supplier_costs`, `promotions`, `price_history`, `competitor_prices`).
- **How it filters:** the function `rls.fn_region_filter` keeps a row only if the caller's sign-in name (`ORIGINAL_LOGIN()`) maps to that region, or to `*`, in `rls.user_region`.
- **The mapping:** built from settings at load time, so no tenant UPN is in the repo.
- **Users and roles:** each test user has a database user in `pricing_readers`, which reads `dbo` and is denied the `rls` schema.
- **Connections:** clients connect with their own Entra token, and pooling is off, so one user's connection is never reused for another. The firewall admits the laptop's IP only, until milestone 4.
- **Proof:** `evals/live/rls_check.py` signs in as three users and compares what each sees.

## Network

All apps share one Container Apps environment with peer-to-peer encryption on. Only the orchestrator has external ingress; the data-agent answers only inside the environment (404 from outside). Container Apps authenticates apps to each other but doesn't authorize them; the token checks above do.

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
