# Latency Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the warm demo question from 60–88 s to at most 40 s (median of three), with lower model cost and every live case still passing. Hide most of the cold wait behind sign-in.

**Outcome (2026-11-24):** done, with the 40 s target missed. The warm demo question takes 48.4 / 44.3 / 43.7 s (median 44.3 s, from 60–88 s) with 5 model calls instead of 10, about $0.016 a turn instead of $0.028; with the policy agent at low it took 33.8 s, but that failed the gate. After sign-in from a fully cold system it took 48.1 s (167.5 s cold before; target warm + 30 s, met). The live gate passed 54/54 three runs in a row: 16.5–17.1 s and $0.0040–0.0042 a question, from 16.9 s and $0.0047. Final versions: orchestrator `v0.8.4`, data-agent `v0.4.6`, policy-agent `v0.1.9`, web `v0.1.2`. Deviations, from the run ledger:
- **Effort low held nowhere.** The data agent (twice a false "not recorded", once a wrong ratio), the composer (a false "Allowed") and the policy agent (the Tier B limit left out) went back to medium after one calibration each, keeping their calibration lines: "check once more before concluding" (data agent), "each limit with its number" (composer) and the what-to-do clauses (policy agent).
- **Found by the final review and its verification:** `margin_change` took a store question's region figures as the store's (now one call per region, a store's figures from `run_sql`), a change dated the "before" period's first day counted twice, the warm-up gave up before the database resumed (60 → 120 s), the data agent wrote its reported facts into the answer, and the composer echoed its input; each fixed with a test that failed first.
- **The Ramadan ratio (data-agent `v0.4.6`):** 4 of 10 live asks divided 2026's units by 335 calendar days (the data ends 31 Oct 2026), 1.22 times too high; G-D13's patterns had passed those answers since milestone 5. The instructions now average over the rows on record, and the case rejects 2.7 and 2.8.
- **G-C03 accepts "not allowed"** (a right answer: "Not allowed. The change was 7.0% … up to 4%"); the case still needs 7.0% and 4%.
- **`A2AAgent.warm(user_token)`** takes the user's token and runs as an `asyncio` task, not a Starlette `BackgroundTask` (it can't rely on the request after the response).
- **`margin_change`'s SQL was first verified live through traces** (12 calls, 84 queries, 0 failed): the laptop isn't on the SQL firewall.
- **`CHAT_P95_SECONDS` 120 → 75:** on the final versions, warm p95 44.8 s and one turn over 75 s (79.7 s) in 162 gate turns; the rule needs two in 15 minutes, and a target at the p95 would email during normal runs.

**Architecture:** Three changes, in the order of the baseline's measured shares (`docs/research/2026-11-latency-baseline.md`):
1. **Reasoning effort `low` instead of `medium`** for the policy agent, the composer and the data agent. Output tokens set the pace, and most of them are reasoning. Each service changes in its own commit, so the gate can keep or revert one alone.
2. **A tested `margin_change` tool in the data agent.**
   - **What it returns:** in one call, a category's margin in two periods, each product's change (worst first), and the supplier cost changes, promotions and price changes behind them, all computed by code on bound parameters as the signed-in user.
   - **Why:** a "why did margin drop" question then needs about 2 model calls instead of 2–8.
3. **Wake the system at sign-in.**
   - **The web app:** calls the orchestrator's new `POST /warm` once after sign-in.
   - **The orchestrator:** answers `202` at once. In the background it fetches the policy and action agents' cards (which starts their containers) and calls the data agent's new `POST /warm` with an OBO token; that runs the cheap `visible_regions` query as the user, which resumes the database.
   - **What comes back:** nothing, on any path.

**Tech Stack:** as today. No new dependency.

**Spec:**
- **The owner (2026-11-22/23):** latency is the top priority. They approved writing this plan after the M9 baseline.
- **`docs/research/2026-11-latency-baseline.md`:**
  - warm demo question 60–88 s: router 2 s, data agent 33–53 s (2–8 model calls), policy agent 15 s (one call of 2,000–2,700 output tokens), composer 15–25 s;
  - cold adds about 100 s: orchestrator start 28 s, agents' start 28 s, database resume 45 s;
  - output tokens are 89% of model spend.
- **`decisions.md`:**
  - D-011: numbers only from data;
  - D-032: the data agent's tested tools and checked `run_sql`, per-user connections;
  - D-033: the live gate, three runs;
  - D-040: composition;
  - D-043: telemetry.
- **`CLAUDE.md`:**
  - every service validates every request;
  - database queries always run on the user's OBO token;
  - never take authorization facts from request bodies;
  - pin versions; tests first.

## Global Constraints

- **Answers must not regress:** the live gate (54 cases) passes three runs in a row (D-033) after all changes. A case's wording changes only for a right answer, quoted.
- **One calibration attempt per service.** If lowering a service's effort fails cases and one calibration with a pinning test doesn't fix them, that service goes back to `medium`, and the ruling says so.
- **`margin_change` runs as the user** (OBO, row-level security), on code-written SQL with bound parameters only. It uses only tables `run_sql` may read and returns at most 200 rows per section.
- **`/warm` returns no data and accepts no body.** It goes through the same token check as `/chat` (orchestrator) or as the A2A route (data agent). A failure inside it is logged as a type and never surfaces to the caller.
- **Versions:**
  - policy-agent `v0.1.7` (effort);
  - orchestrator `v0.8.0` (effort, `/warm`);
  - data-agent `v0.4.0` (`margin_change`, `/warm`), then `v0.4.1` (effort);
  - web `v0.1.2`.

## Cost

- **Live work:**
  - targeted runs of the five slowest cases after each change: about $0.10 each;
  - the three-run gate: about $0.60;
  - a new baseline: about $0.20.
- Lower effort should cut model cost per question, which the cost report shows.
- **No new Azure resource.** `/warm` adds a few seconds of container time per sign-in.
- **Spend so far:** $11.64 of $20 (Cost Management lags a day).

## Decisions in this plan (for the owner's review)

- **D-044: answer speed.**
  - Reasoning effort `low` where the gate holds.
  - `margin_change` for "why" questions.
  - Wake at sign-in.
  - **Rejected:**
    - `minReplicas: 1`: about $11.70 a month per app around the clock, or about $2.85 per app for working hours only; three apps would be about $35 or $8.55 a month, against about $8 left;
    - pooling SQL connections: 50 ms each warm, and per-user connections are a rule;
    - a router shortcut: about 2 s, and a rule that can misroute.
- **Streaming the answer is not in this plan.** It changes the `/chat` contract, the A2A calls and the web app. It's the next plan if the measured result still feels slow.
- **The three-run gate applies** because answers change.

## Review Focus

1. **A lower effort makes an answer wrong rather than shorter** (a dropped condition, a wrong verdict, a wrong figure). Expected: the gate catches it; the service reverts after one failed calibration. Test: Task 5 Step 3.
2. **`margin_change` used for a question it doesn't fit** (no "before" period, two categories, a store), or with periods that overlap. Expected: it rejects bad periods with a reason the model can act on, and the model falls back to `margin` and `run_sql`. Test: Task 2 `test_overlapping_periods_are_rejected`, `test_an_unknown_category_is_rejected`.
3. **`/warm` as an amplifier:** a client calling it in a loop. Expected: each call needs a valid user token. A second call while a warm-up is running does nothing (one in flight per process). Test: Task 3 `test_a_warm_call_while_one_runs_does_nothing`.
4. **The data agent's `/warm` for a user without database access** (a personal account, 18456). Expected: 204, a logged type, no error surfaced. Test: Task 2 `test_warm_without_database_access_is_quiet`.
5. **A warm-up that never finishes** (an agent down). Expected: no effect on later turns; the background task ends at its own timeout. Test: Task 3 `test_a_failing_warm_up_never_raises`.

---

### Task 1: Reasoning effort `low` in the policy agent (`v0.1.7`) and the composer (orchestrator)

**Files:**
- Modify: `policy-agent/src/policy_agent/adapters/outbound/analyst.py:45`, `policy-agent/tests/test_analyst.py` (`test_reasoning_effort_is_medium` → `test_reasoning_effort_is_low`)
- Modify: `orchestrator/src/orchestrator/adapters/outbound/composer.py:52`, `orchestrator/tests/test_composer.py` (the effort assertion in `test_the_composer_sees_each_reply_and_no_tools`)

- [ ] **Step 1:** Change both tests to expect `{"effort": "low"}`. Run them. Expected: FAIL (`medium`).
- [ ] **Step 2:** Change both `default_options`. Run both full suites and lint. Expected: all pass.
- [ ] **Step 3:** Commit policy-agent, tag `v0.1.7`, push. Commit the orchestrator; it's tagged with Task 3.

### Task 2: data-agent `v0.4.0`: `margin_change` and `/warm`

**Files:**
- Modify:
  - `data-agent/src/data_agent/application/run_sql.py` (`SqlTool.margin_change`, its SQL constants);
  - `data-agent/src/data_agent/adapters/outbound/analyst.py` (`margin_change_tool`, added to `tools`);
  - `data-agent/src/data_agent/adapters/outbound/instructions.py` (the "To explain a change" rule);
  - `data-agent/src/data_agent/adapters/inbound/a2a_server.py` (`POST /warm`).
- Test: `data-agent/tests/test_margin_change.py`, `data-agent/tests/test_a2a_server.py`, `data-agent/tests/test_analyst.py`

**Interfaces:**
- `async SqlTool.margin_change(before_start: str, before_end: str, after_start: str, after_end: str, region: str, category: str) -> str`.
  - **Validation:** dates are ISO; `before_start <= before_end < after_start <= after_end`; `region in REGIONS` (required); `category in CATEGORIES`. Otherwise `"rejected: <reasons>"`.
  - **The five queries,** each with bound parameters through `self._runner.query(sql, MAX_ROWS, params)`:
    1. category totals for both periods (net sales, COGS, margin %);
    2. per product, margin % and net sales in each period, ordered by the change, worst first;
    3. supplier cost changes in `[before_start, after_end]` with the previous cost (`LAG` over sku and region, computed before filtering);
    4. promotions overlapping either period (dates, `discount_pct`, `supplier_funded_pct`);
    5. price changes in the window (old, new, `change_pct`, reason).
  - **The result:** sections headed `category`, `products`, `cost changes`, `promotions`, `price changes`, each as CSV (`as_csv`). An empty section says `none`; no sales in either period says `no sales rows for that period and filter`. `QueryFailed` gives `"query failed"`.
- **Tool `margin_change`:** with these parameter descriptions:
  - "First day of the period before the change, YYYY-MM-DD"
  - "Last day of the period before, inclusive"
  - "First day of the period after"
  - "Last day of the period after, inclusive"
  - "One region: N, C or S"
  - "One category"
- **Instructions:** the "To explain a change" bullet becomes: call `margin_change` once with the two periods (the rules for choosing them stay), answer from its sections, and use `run_sql` only for what they don't cover.
- **`POST /warm`:** behind the same `AuthMiddleware` as the JSON-RPC route.
  - It awaits `sql.visible_regions()` and returns `204`.
  - `NoDatabaseAccess`, `QueryFailed` or any other exception: `204`, logged as `warm failed: <type>`.

- [ ] **Step 1: Write the failing tests:**
  - `test_margin_change_returns_every_section`: a `FakeRunner` answering per query.
    - The result contains the five section headers, in order.
    - Every query was called with bound params; no date, region or category appears in the SQL text.
  - `test_overlapping_periods_are_rejected`: `("2026-10-01", "2026-10-31", "2026-10-15", "2026-10-31", "N", "Dairy")` returns `rejected: the period before must end before the period after starts`.
  - `test_an_unknown_category_is_rejected`: `category="Cheese"` returns a rejection naming the six categories.
  - `test_no_sales_says_so`: the totals come back all `None`, giving `no sales rows for that period and filter`.
  - `test_the_model_is_given_margin_change`: tool names are `["run_sql", "margin", "margin_change"]`, and the instructions contain `call margin_change once`.
  - `test_warm_runs_the_regions_query_as_the_caller`: with a valid local-issuer token, `POST /warm` returns 204 and the fake runner saw `VISIBLE_REGIONS`.
  - `test_warm_without_database_access_is_quiet`: the runner raises `NoDatabaseAccess`; the result is 204 and the log has `warm failed: NoDatabaseAccess`.
  - `test_warm_needs_a_token`: no token returns 401.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Write the SQL as constants beside `MARGIN`; T-SQL, `JOIN dbo.dim_product`, half-open dates handled by `BETWEEN` on inclusive ends as `margin` does.
- [ ] **Step 4:** Full suite and lint. Expected: all pass.
- [ ] **Step 5: Commit**, tag `v0.4.0`, push.

### Task 3: orchestrator `v0.8.0`: `POST /warm`

**Files:**
- Modify:
  - `orchestrator/src/orchestrator/adapters/outbound/a2a_agent.py` (`A2AAgent.warm`);
  - `orchestrator/src/orchestrator/adapters/inbound/http_api.py` (the route);
  - `orchestrator/src/orchestrator/main.py` (`wakes_database=True` for the data agent).
- Test: `orchestrator/tests/test_warm.py`

**Interfaces:**
- `A2AAgent(..., wakes_database: bool = False)`.
- `async A2AAgent.warm() -> None`:
  - `GET {url}.well-known/agent-card.json` (no token; it starts the container);
  - when `wakes_database`, also `POST {url}warm` with the agent's OBO token.
  - At most 60 s; every exception is caught and logged as `warm failed: <name>: <type>`.
- **`POST /warm` in `create_http_app`:**
  - behind the same middleware as `/chat`;
  - returns `202 {}` at once;
  - runs `asyncio.gather(*(agent.warm() for agent in agents.values()))` as a Starlette `BackgroundTask`;
  - a module-level flag skips a second warm-up while one is running in this process.
- `FakeAgent.warm()` does nothing.

- [ ] **Step 1: Write the failing tests:**
  - `test_warm_answers_at_once_and_wakes_every_agent`: three recording fake agents; the result is 202, and each agent's `warm` was called once.
  - `test_a_warm_call_while_one_runs_does_nothing`: the first warm-up is blocked on an event; a second call returns 202 without calling the agents again.
  - `test_a_failing_warm_up_never_raises`: `A2AAgent.warm` against an `httpx.MockTransport` that raises `ConnectError` returns normally, with the log `warm failed: data-agent: ConnectError`.
  - `test_the_data_agent_is_warmed_with_its_own_token`: the mock transport sees `GET …/.well-known/agent-card.json`, then `POST …/warm` with `Authorization: Bearer <the OBO token for the data agent's scope>`.
  - `test_warm_needs_a_token`: no token returns 401.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Full suite and lint. Expected: all pass.
- [ ] **Step 5: Commit**, tag `v0.8.0` (this includes Task 1's composer change), push.

### Task 4: web `v0.1.2`: warm after sign-in

**Files:**
- Modify: `web/src/api.ts` (`warm`), `web/src/App.tsx` (the call), `web/package.json` (version)
- Test: `web/src/api.test.ts`, `web/src/App.test.tsx`

**Interfaces:** `Api.warm(): Promise<void>`. It POSTs `${orchestratorUrl}/warm` with the orchestrator token and resolves on any outcome; a failure is swallowed. `App` calls it once when the signed-in screen first renders.

- [ ] **Step 1: Write the failing tests:**
  - `warm posts once with the orchestrator token and never throws` (a fetch returning 500 still resolves);
  - `the app warms the copilot once after sign-in` (render twice, one call).
- [ ] **Step 2: Run** `npm test`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** `npm test && npx tsc --noEmit && npm run build`. Expected: all pass.
- [ ] **Step 5: Commit**, tag `v0.1.2`, push.

### Task 5: Deploy, measure, the data agent's effort, the gate

- [ ] **Step 1: Deploy** (`deploy-spike.sh deploy apps`, `wait-revisions.sh`, `monitoring-check.sh`) and redeploy the site (`deploy-web.sh`). Expected: OK.
- [ ] **Step 2: Targeted runs.** Run G-D01, G-D02, G-C01, G-D10 and G-D13 three times, with the cost report. Expected:
  - all pass;
  - the demo question's median at most 45 s;
  - the data agent at about 2 model calls on G-D01 and G-D02.
- [ ] **Step 3: The data agent's effort.** Data-agent `v0.4.1` sets `effort: "low"` (test first, as in Task 1), then deploy and rerun Step 2.
  - **Keep it** when the cases pass and time drops.
  - **Otherwise** make one calibration attempt; if that fails, revert to `medium` and record the ruling.
- [ ] **Step 4: The gate:** `uv run live/run_cases.py` three times (54 cases), then `clear_drafts.py`. Expected:
  - 54/54 ×3;
  - the reports' average time and cost per question lower than M9's (16.9 s, $0.0047).
- [ ] **Step 5: Measure:**
  - **warm:** the demo question ×3, a data-only and a policy-only question ×2 each;
  - **after sign-in:** with everything scaled to zero and the database paused, call `POST /warm`, wait 60 s, then ask the demo question.
  - **Expected:**
    - warm demo median at most 40 s;
    - the after-sign-in question at most the warm time plus 30 s.
  - Every figure goes in the ledger as measured, met or not.

### Task 6: `docs` and the vault

- [ ] **Step 1: docs:**
  - D-044 and the summary table;
  - D-040: the composer's effort; D-032: `margin_change`;
  - the security model: `/warm` (authenticated, no data);
  - `research/2026-11-latency-baseline.md`: an "After the fixes" section, with the same tables;
  - roadmap: a "Latency fixes" line after row 9;
  - README status;
  - this plan's outcome note.
  - Scan for real IDs. Commit, push.
- [ ] **Step 2: Vault:**
  - repo pages: orchestrator, data-agent, policy-agent, web;
  - Home;
  - the decisions index;
  - release note "Faster answers";
  - the chat-slow runbook's target, if `CHAT_P95_SECONDS` changes (set it from the new warm p95, then redeploy monitoring).
