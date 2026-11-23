# Latency baseline (2026-11-23)

Measured from traces (D-043) on orchestrator `v0.7.0`, data-agent `v0.3.0`, policy-agent `v0.1.6`, gpt-5-mini (Global deployment), all as north.mgr. Times are server-side, from the orchestrator's request span; the client adds network time and, when the orchestrator itself is cold, its start.

## Warm turns

| Question | Runs | Total | Router | Data agent | Policy agent | Composer |
|---|---|---|---|---|---|---|
| "Why did dairy margin drop in the North in October 2026?" (data and policy) | 3 | 60–88 s | 1.6–3.4 s | 33–53 s | 15–16 s | 15–25 s |
| "What was dairy margin in the North in October 2026?" (data only) | 2 | 10–11 s | 2–3 s | 7–9 s | – | – |
| "Can I raise UHT milk 1 L by 3.6% in the North?" (policy only) | 2 | 18–20 s | 2.5–2.9 s | – | 15–18 s | – |

The data and policy agents run at the same time, so a two-agent turn takes the router, then the slower agent, then the composer.

### Where the time goes inside a turn

- **Model calls are almost all of it.** In the demo question, model calls are 32–51 s of the data agent's 33–53 s and 15–16 s of the policy agent's 15–16 s; the composer is one model call.
- **Output tokens set the pace.** The output includes the model's reasoning, at roughly 135 tokens a second:
  - the policy agent writes 2,000–2,700 output tokens for an answer of a few sentences (reasoning effort `medium`);
  - the composer writes 2,200–3,000 (`medium`).
  - Output is also 89% of this month's model spend.
- **The data agent's tool loop:** a simple question takes 2 model calls (about 3–4 s each). The demo question takes 2–8 calls of about 6 s each, while the model queries margins, products, costs and promotions in turn.
- **Not the problem:**
  - warm SQL: about 50 ms to connect and 250–350 ms per query, 2–2.5 s per demo turn over 6–8 queries;
  - the OBO token exchanges: 0.3–1.3 s a turn;
  - AI Search: 0.1–0.2 s.

## Cold turns

One run: every app scaled to zero and the database paused (the free offer showed Paused about 15 minutes after the last query). It was the demo question.

| Part | Time |
|---|---|
| Client total | 167.5 s (warm: 60–88 s) |
| The orchestrator's container start, before its request began | about 28 s |
| Router | 2.7 s |
| The agents' container start, both at once, only when first called | about 28 s |
| The database resuming, in the data agent's first connection | about 45 s (45.9 s over 9 connections) |
| Model calls: data agent (9), policy agent (1), composer (1) | 40 s, 10 s, 20 s |

A cold turn adds about 100 s to a warm one, in three steps: the orchestrator's start, then the agents' start, then the database's resume. Each waits for the one before.

## What to fix first

Ranked by measured share. The estimated gain is for the warm demo question, today 60–88 s.

| # | Fix | Share it targets | Estimated gain | Cost and risk |
|---|---|---|---|---|
| 1 | Lower reasoning effort (`medium` → `low`) in the policy agent and the composer, then in the data agent, wherever the live gate still passes | the policy agent (15 s), the composer (15–25 s), each data-agent call | about 25–40 s; output tokens, and so cost, roughly halved | answers can get less careful; the gate decides, one service at a time |
| 2 | Fewer data-agent turns for "why" questions: one tested tool that returns product-level margin changes with their cost changes and promotions, computed in code | 5–6 sequential model calls (25–35 s) | about 20–30 s | a new tool and its tests; the numbers stay computed by code |
| 3 | Wake the system when someone opens the web app: the orchestrator wakes the agents and the database while the user signs in | cold starts: about 100 s (28 + 28 + 45) | most of the cold wait, hidden behind sign-in | one unauthenticated-safe endpoint, or an authenticated one called after sign-in; no data returned |
| 4 | Stream the answer: show the data agent's reply as soon as it arrives, then the policy part | perceived time | the first words 20–40 s sooner | a change to the `/chat` contract and the web app |
| 5 | `minReplicas: 1` for the orchestrator and two agents during working hours | cold starts | removes them | idle billing for three apps (quote before choosing) |
| 6 | Skip the router for questions an obvious rule can place | 1.6–3.4 s | about 2 s | a rule that can misroute; low value |

Not worth it now: pooling SQL connections (50 ms each, and per-user connections are a rule), caching OBO tokens (under 1.3 s).
