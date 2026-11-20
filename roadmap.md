# Plan

Rough estimates, assuming about 10 hours a week (1–2 hours a day) with Claude writing code and the owner reviewing.

## Workspace layout

All repos belong to the GitHub organization `margin-copilot`.

```
azure_project/                    this folder (not a repo)
  CLAUDE.md -> docs/CLAUDE.md     symlink
  web/             public
  orchestrator/    public
  data-agent/      public
  policy-agent/    public
  action-agent/    public
  proposals-api/   public
  shared/          public   contracts + security module
  data/            public   generator, RLS scripts, policies, indexer
  evals/           public
  docs/            public   start here: how it all works, decisions, roadmap, plans
  infra/           private  Bicep + non-secret config
```

## Inside a Python service

```
src/<package>/
  domain/               pure logic, no I/O (SQL guard, approval rules, price maths)
  application/          use cases; ports defined as Protocols
  adapters/
    inbound/            a2a_server.py or http_api.py (+ token middleware from shared)
    outbound/           fabric_sql.py, search.py, proposals_client.py, llm.py ... each with a fake
  main.py               composition root: ADAPTERS=fake|azure picks the adapters
tests/
  unit/                 domain + application with fakes
  contract/             payloads against shared contracts
  integration/          real Azure, @pytest.mark.azure, opt-in
Dockerfile  pyproject.toml  .env.example  .github/workflows/{ci,build}.yml (ci = baseline secret scan; build = tests + image)
```

## Milestones

| # | Milestone | Hours | Done when |
|---|---|---|---|
| 0 | Accounts and guardrails: Azure free account, budget alerts as code, Entra test users (north.mgr, center.mgr, south.mgr, pricing.director) and groups, the GitHub organization with eleven repos, secret scanning and CI, docs hub | 4 | Alerts set, four users sign in, repos exist with a passing empty CI — done 2026-11-15 |
| 1 | App registrations and managed identities, `shared` + service template + **A2A/OBO spike deployed to Container Apps** (orchestrator stub → data-agent stub, internal ingress, peer-to-peer encryption) | 12 | A request signed in as north.mgr crosses one A2A hop; the agent's tool receives a fresh OBO token; a token from the wrong caller is rejected — done 2026-11-19 |
| 2 | Eval harness: golden and adversarial cases, CI suite on fakes | 5 | CI runs and fails for the right reasons — done 2026-11-19 |
| 3 | Data + RLS on the Azure SQL free offer (D-031; Fabric trial refused) | 8 | north.mgr and south.mgr get different rows from the same query; story checks pass — done 2026-11-19 |
| 4 | data-agent: `run_sql` over Azure SQL, SQL guard, no error text from reading rows, OBO, `mssql-python`; orchestrator reports `agents` and `refusal`; evals wiring for data cases (D-029) | 8 | Data and region eval cases pass in the live suite against Azure SQL, three runs in a row (D-033) — done 2026-11-20 |
| 5 | policy-agent: policy Markdown, indexer, group filter; orchestrator routes to it and reports `citations`; evals wiring | 7 | Groundedness and access cases pass in the live suite (37 cases, three runs in a row) — done 2026-11-20 |
| 6 | proposals-api + action-agent; orchestrator routes to it; D-012 approval boundaries tested in proposals-api | 8 | Tests show no approval path without the right role and region |
| 7 | orchestrator: tools over A2A, conversations, scope rules, chat API; conversation-resume hijack eval case | 8 | End-to-end eval suite passes |
| 8 | web: MSAL sign-in, chat, approvals | 8 | Demo question works in the browser for north.mgr and south.mgr |
| 9 | Observability and cost: traces across services, cost per question | 4 | Every eval run reports cost per question |
| 10 | Full Bicep + per-repo GitHub Actions deploys (OIDC) | 10 | A push to main deploys that service; evals gate it |
| 11 | Adversarial pass: poisoned document, RLS bypass (incl. inference through errors), SQL injection, wrong-caller tokens | 5 | Each finding has a test and a fix note |
| 12 | Stretch: Fabric lakehouse + Fabric Data Agent on paid F2 hours (MCP + OBO), compared with `run_sql` on Azure SQL | 4 | Comparison note written; F2 paused |

Core (0–11): about 87 hours.

## Timeline

| Week | Work |
|---|---|
| 1 | M0, start M1 |
| 2 | Finish M1 (spike deployed), M2 |
| 3 | M3 (Azure SQL free offer; Fabric trial refused) |
| 4 | M4 |
| 5 | M5 |
| 6 | M6 |
| 7 | M7 |
| 8 | M8 |
| 9 | M9, start M10 |
| 10 | Finish M10, M11 |
| 11 | Buffer, then M12 if budget allows |

The Fabric trial starts in week 3 and ends around week 11, so every Fabric-dependent milestone fits inside it with a little buffer.

## Risks

- **A2A auth and token propagation** (D-006): the beta package leaves server auth and token passing to us. M1 proves it first. Fallback: plain HTTPS adapters.
- **Fabric:** the trial was refused for the young tenant (milestone 3); milestone 12 uses paid F2 hours, paused after every session.
- **Model drift:** gpt-5-mini answers can change wording or numbers between runs; each milestone's live answers are reviewed before the gate (D-029, D-033).
- **AI Search Free and RBAC:** docs conflict on keyless access for Free. If it fails, the query key goes to Key Vault.
- **Cold starts:** a first question after idle may wake four services. Acceptable for a demo.
- **Model quota:** the subscription may need pay-as-you-go before any model deployment works.

## Open questions

1. **Chat model:** gpt-5-mini or gpt-6-luna, decided by eval scores and cost at M4–M7. Milestone 4 runs on gpt-5-mini (the only current chat model with free-trial quota); compare with the live suite after the account upgrade (D-032, D-033).
2. **Golden cases in CI:** call Foundry from CI through GitHub OIDC (keyless; costs cents per run), or run golden cases only in the live suite. Decide at milestone 4 (D-029).

Resolved on 2026-11-15: CI eval tokens (D-019), where docs live (D-020), license (D-021), where `CLAUDE.md` lives (D-022).
