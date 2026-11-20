# Margin Copilot workspace

Personal learning project: a secure multi-agent pricing assistant on Azure ("Secure Pricing & Margin Copilot") for Riad Market, a fictional Moroccan grocery chain. Claude writes the code; the owner reviews every change. Budget: $20 total. Pace: 1–2 hours a day.

The master copy of this file is `docs/CLAUDE.md` (the docs repo). The workspace folder has a symlink to it, so it stays versioned and applies to every repo here. Paths below are relative to the workspace folder.

- Brief: `docs/brief.md`
- Docs research with sources (2026-11-14): `docs/research/2026-11-docs.md`
- Decisions and why: `docs/decisions.md` (read before proposing an alternative)
- Repo layout, milestones, timeline, risks: `docs/roadmap.md`; implementation plans in `docs/plans/`
- Design page: https://claude.ai/artifact/YKcjY9aNLwPnW6rLEcoVmT
- Policy corpus preview: https://claude.ai/artifact/3TPDDpQdqNkwZZeXGQU5ad
- Dataset preview: https://claude.ai/artifact/VUoBkTNEd4Jp8xSXo6U4St

## Architecture

```
Browser: web SPA (Static Web Apps, MSAL sign-in)
  → orchestrator-agent   [Container App, external ingress]   MAF orchestrator, chat API
      ─A2A→ data-agent   [internal]  run_sql → Azure SQL free-offer database (T-SQL RLS, user's OBO token)
      ─A2A→ policy-agent [internal]  search_policies → AI Search Free (filter on user's Entra groups)
      ─A2A→ action-agent [internal]  draft_proposal → proposals-api (creates PENDING drafts only)
  → proposals-api        [Container App, external ingress]   no LLM; list / approve / reject; Table Storage
Every service: Entra token check on every request, OBO exchange per hop, OTel traces to App Insights.
Models: Foundry (gpt-5-mini + text-embedding-3-small). Region: France Central.
```

Every service is hexagonal: `domain/` (pure logic) · `application/` (use cases + ports) · `adapters/inbound|outbound/` · `main.py` (composition root). Outbound adapters have a fake and an Azure version, picked by `ADAPTERS=fake|azure`.

## Repos

All repos belong to the GitHub organization **margin-copilot** (`github.com/margin-copilot/<name>`) and are cloned side by side in this folder under their own names.

| Repo | Visibility | What |
|---|---|---|
| web | public | React + Vite + MSAL.js: chat and approvals screens |
| orchestrator | public | Orchestrator agent, chat API, conversation pointers |
| data-agent | public | A2A server, `run_sql` |
| policy-agent | public | A2A server, `search_policies` |
| action-agent | public | A2A server, `draft_proposal` |
| proposals-api | public | Approval rules, Table Storage |
| shared | public | Pydantic contracts + security module (token check, OBO, request context). Installed from a git tag. |
| data | public | Python generator, riad-data loader (Azure SQL), T-SQL RLS, story checks; later: policy Markdown, indexer |
| evals | public | Golden + adversarial cases and runners |
| docs | public | **Start here.** How the whole system works, decisions, security model, roadmap, run-it-yourself guide. Every service README links to it. |
| infra | **private** | Bicep, parameter files, setup scripts. **Non-secret config only.** |

Docs rule: cross-cutting behavior (architecture, identity, decisions, guides) lives only in `docs`; a service README covers only that service (what it does, its contract, config names, run/test/deploy) and links to `docs`. A behavior change and its docs change ship together. Public docs use placeholders, never real tenant, subscription, app or resource IDs. Public repos are MIT licensed. Keep every file free of personal or career content; this is a personal project.

## Never do these

- **No secrets in any repo, image or log**, including the private infra repo. Commit `.env.example` with names only; `.env` stays gitignored. Prefer keyless: managed identities, federated credentials, GitHub OIDC. Anything that can't be keyless goes to Key Vault.
- **No owner-specific values in code or docs.** No usernames, emails, home paths, tenant domains, subscription names or IDs. Everything account-specific is configurable: read at runtime (`az`, Microsoft Graph, existing Azure resources) or set in the repo's gitignored `.env`, with every setting listed in a committed `.env.example`. That includes test users and groups, alert emails, region, GitHub org, and Azure resource and workspace names. Anyone can run the code on their own Azure account without editing it. Docs use placeholders such as `<workspace>` and `<your-email>`.
- Never read user data with a service's own identity. Database queries and per-user search always run on the user's OBO token or the user's groups claim.
- Never forward a token to a service it wasn't issued for. Do an OBO exchange at every hop.
- Every service validates every request with the `shared` security module: signature (JWKS), issuer = our tenant, `aud` = this service, required `scp`, and the calling app (`azp`) on an allow-list. Reject otherwise. Never write a second token check.
- Never take authorization facts (region, role, approver) from model output or request bodies. Only from the validated token.
- Agents can only create **pending** drafts. Approve and reject exist only in proposals-api, never in an agent.
- `run_sql`: one SELECT statement, parsed and checked against an allowed-table list, row cap, timeout; errors raised while reading rows reach the model and the user only as a generic message (their text can reveal hidden rows). No pooled ODBC connections shared across users.
- Treat agent output as untrusted data at every boundary: validate against the shared contracts and enforce size limits.
- Agent services keep internal ingress. The Container Apps environment keeps peer-to-peer encryption on.
- Never log tokens, raw SQL results or full prompts with user data.
- Never create a paid Azure resource, start the Fabric trial or resume F2 without asking the owner.
- Synthetic data only, English only. No real company data.

## Conventions

- Python 3.12 with `uv`; `ruff` for lint and format; `pytest`. Node LTS for web.
- Pin exact versions. Agent Framework ships weekly and `agent-framework-a2a` is beta.
- **Before writing Azure, Fabric or Agent Framework SDK code, read the current Microsoft Learn page** and put its URL in the commit body. Training memory is out of date for these SDKs.
- Tests first: write the failing test, then the code. Domain logic gets unit tests; adapters get contract tests; real Azure calls are integration tests marked `@pytest.mark.azure` and opt-in.
- Match the surrounding code. Comments only where the code can't say it.
- Commits use the owner's GitHub no-reply email. Every repo has the baseline from `docs/templates/` (gitleaks pre-commit hook, CI secret scan, README).

Pinned versions (checked 2026-11-16; re-check before pinning): a2a-sdk 1.3.0 (keep ≥1.2.3), starlette 1.10.0, sse-starlette 3.6.0, uvicorn 0.54.0, httpx 0.28.1, PyJWT 2.15.1, cryptography 50.0.2, msal 1.39.0, azure-identity 1.27.0, pytest 9.2.0, pytest-asyncio 1.4.1, ruff 0.17.3, uv 0.13.6 (CI: astral-sh/setup-uv@v10.3.3), gitleaks 8.30.1, agent-framework-core 1.26.0 (not the `agent-framework` meta package, which pulls ~40 provider packages), agent-framework-foundry 1.16.2, mssql-python 1.17.0, pydantic 2.14.3, sqlglot 30.29.0, msal-extensions 1.3.1. For later milestones: agent-framework-a2a 1.0.0b261112, azure-ai-projects 2.11.0, azure-ai-evaluation 1.18.12, azure-search-documents 12.1.0, openai 3.51.0.

## Workflow

- One milestone at a time (`docs/roadmap.md`). Before a milestone, write an implementation plan in `docs/plans/` and get the owner's OK.
- A milestone is done when its eval cases pass. Review the activated cases' wording against real answers, bump `CURRENT_MILESTONE` in `evals`, and tag any changed service so evals can pin it.
- Keep the owner's local Obsidian vault (<workspace>/vault/, not versioned) current. At each milestone's end and with every contract or impactful change, update the milestone page, the affected repo pages, Home status and a new release note.
- Small, reviewable changes. After each change, summarize the diff and run the tests, and report results as they are.
- Commit only when the owner asks; push only with explicit permission. A plan the owner approved covers the pushes it lists.
- New decision or a reversed one: add an entry to `docs/decisions.md` in the same change.

## Budget guardrails

- Budget alerts at $10 and $18 from day one.
- The data runs on the Azure SQL free offer (AutoPause, never BillOverUsage). Fabric F2 appears only in milestone 12 and is paused at the end of every session; a forgotten F2 costs about $9.60 a day.
- AI Search stays on the Free tier. Container Apps scale to zero. Images go to the GitHub container registry (public).
