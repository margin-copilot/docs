# Streaming Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The chat shows what the copilot is doing from the first second and the data agent's reply as soon as it's ready (about 20 s into the demo question instead of 44 s), with every answer exactly as checked as today; `margin_change` saves a few more seconds by running its queries at the same time.

**Outcome (2026-11-24):** done. On the warm demo question the first step shows within 0.2 s, the data agent's reply at 19.2 / 21.0 / 15.6 s (median 19.2 s, target 26 s) and the full answer at 35.3 / 40.2 / 35.8 s (median 35.8 s, from 44.3 s); the data agent's span is 13–19 s (18–23 before). The live gate passed 54/54 three streamed runs in a row (15.4–16.2 s, $0.0039–0.0041 a question) and once as JSON. Final versions: orchestrator `v0.9.0`, data-agent `v0.4.7`, web `v0.2.0`. Deviations, from the run ledger:
- `stream_problems` needs a step only before `done`: a 404 for an unknown conversation is right with no step before it.
- An unexpected error in a streamed turn is an `error` event with status 500, and its span is marked failed.
- chat-failing counts 5xx and a 2xx with `Success == false`; `Success == false` alone would count 404s.
- `run_cases.py` takes a token per case: one sign-in per persona expired during the longest group.

**Architecture:**
- **The orchestrator streams when asked:** `POST /chat` with `Accept: text/event-stream` answers with server-sent events:
  - `step`: one per stage as it starts;
  - `lead`: the data agent's reply in a two-agent turn, the moment it arrives;
  - `done`: the same body as today's JSON reply; or `error`.
- **Unchanged without that header:** `POST /chat` answers JSON as before (evals, scripts, an old cached web app).
- **The use case reports progress through a callback** (`Progress`). The HTTP adapter turns the callbacks into events. The turn runs in its own task, so a browser that leaves doesn't cut it short.
- **The composed part arrives whole, after the number check.** The agents' A2A calls don't change: each reply is validated whole before anything shows (see Decisions).
- **The web app** reads the stream with `fetch` (the token stays in the `Authorization` header). It shows the current step, then the data agent's reply, and replaces both with the final answer.
- **`margin_change`** runs its five queries with `asyncio.gather`, each on its own connection as the user, as now.

**Tech Stack:** as today.
- **No new dependency.** `sse-starlette` 3.6.0 is already pinned in the orchestrator. The web app reads `fetch` streams. Evals uses `httpx.stream`.

**Spec:**
- **The owner (2026-11-24):** "yes write the streaming plan", after the latency fixes missed their 40 s target (D-044: warm demo median 44.3 s; composer 19–26 s, data agent 18–23 s, policy agent 12–19 s, the two agents in parallel).
- **What the owner was told:**
  - status lines from the first second;
  - the data agent's reply at about 20 s instead of 44 s;
  - parallel queries in `margin_change`;
  - the total time stays about the same, because most of it is reasoning, which can't be streamed.
- **`decisions.md`:**
  - D-011: numbers only from data;
  - D-029: the chat response contract;
  - D-033: the live gate, three runs;
  - D-040: composition and the number check;
  - D-041: conversations under the owner's oid;
  - D-043: telemetry without content, alerts;
  - D-044: answer speed, "Not yet: streaming the answer".
- **`CLAUDE.md`:**
  - every service validates every request;
  - agent output is untrusted (validate, size caps);
  - never log tokens or content;
  - tests first; pin versions.

## Global Constraints

- **Nothing shows that the final answer wouldn't stand behind.**
  - `lead` is the data agent's reply after the shared contract's validation (at most 4,000 characters), the same text today's answer leads with.
  - The composed part is shown only in `done`, after the number check and the echo strip.
- **Steps carry only fixed names:** `condense`, `route`, `data-agent`, `policy-agent`, `action-agent`, `compose`. No question text, SQL or agent text appears in a step.
- **Same token check, before the stream starts.** The middleware rejects a bad token with 401/403 as now. A bad body is still a 400/413 JSON response, never a stream.
- **`error` events reuse the JSON path's messages and statuses** (`orchestrator unavailable` 502, `conversation not found` 404, `conversations unavailable` 502, `<agent> unavailable` 502). Only errors at 500 or above mark the request failed in traces.
- **The JSON reply doesn't change**, byte for byte: every existing orchestrator test stays green.
- **Answers must not regress:**
  - the live gate passes 54/54 three runs in a row on the streamed path (D-033), plus one run on the JSON path;
  - no case wording changes in this plan.
- **Versions:**
  - data-agent `v0.4.7`;
  - orchestrator `v0.9.0` (a contract addition);
  - web `v0.2.0`;
  - evals pins orchestrator `v0.9.0`, data-agent `v0.4.7`.

## Cost

- **Live work:**
  - the three streamed gate runs plus one JSON run: about $0.90;
  - measurements: about $0.15;
  - targeted checks: about $0.10.
- **No new Azure resource.** A stream keeps the orchestrator's connection open as long as a JSON turn does today.
- **Spend so far:** $12.38 of $20 (Cost Management lags a day).

## Decisions in this plan (for the owner's review)

- **D-045: streaming progress.**
  - **Decision:** `step`, `lead`, `done` and `error` events on request (`Accept: text/event-stream`), with JSON otherwise. The composed part arrives whole, after its check. `margin_change` runs its queries at the same time.
  - **Why the composed part isn't streamed token by token:**
    - the number check (D-011, D-040) can reject text after it was written, and a rejected part must never be on screen;
    - with a reasoning model, the visible text is the last 2–3 s of the composer's 19–26 s.
  - **Why the A2A calls don't stream:**
    - each reply is validated whole (contract, size cap) before it's used;
    - the agents' visible text is likewise a few seconds of their time.
  - **Rejected:**
    - **WebSockets:** a second protocol through the ingress and CORS, for one-way events;
    - **the browser's `EventSource`:** GET only, with no `Authorization` header, so the token would have to go in the URL.
  - **Not yet:** a faster non-reasoning model for the composer (a new Foundry deployment, and a risk of wrong verdicts).
- **D-029 amended:** the streamed form of the chat response.
- **chat-failing counts failed requests, not only 5xx.** A stream that fails after its `200` headers can't change its status code, so code marks its server span as an error, and the alert counts `Success == false`.

## Review Focus

1. **The browser leaves mid-turn** (tab closed, network drop). Expected:
   - the turn finishes and is stored once;
   - no unhandled task error;
   - a draft is created at most once, as a JSON turn behaves today.
   - Test: Task 3 `test_a_turn_finishes_and_is_stored_when_the_client_leaves`.
2. **A failure after the stream started** (an agent down, the 230 s limit, an unknown conversation, a store failure). Expected:
   - one `error` event with the JSON path's message and status, then the stream ends;
   - the request is marked failed only for 5xx;
   - the web app shows the same message as today.
   - Tests:
     - Task 3 `test_a_failure_after_the_stream_starts_is_one_error_event`;
     - Task 3 `test_a_streamed_5xx_marks_the_request_failed`;
     - Task 5 `test_an_error_event_shows_the_same_message_as_a_json_error`.
3. **Network chunking:**
   - one event split across chunks;
   - two events in one chunk;
   - `\r\n` line endings;
   - `: ping` comments from `sse-starlette`;
   - a stream cut off before `done`.
   - Expected: the same events are parsed, and a cut-off stream is a network error.
   - Test: Task 5 `sse.test.ts`.
4. **A `lead` the final answer doesn't start with** (the stitched fallback writes "From the sales data: …"; `no_access` ends on the data reply). Expected: the final answer replaces the early reply; the two never show together. Test: Task 5 `test_the_final_answer_replaces_the_early_reply`.
5. **A client that doesn't ask for a stream** (evals, curl, a cached old web app). Expected: today's JSON reply. Test: Task 3 `test_without_the_stream_header_the_reply_is_json` (and the existing suite).

---

### Task 1: data-agent `v0.4.7`: `margin_change` queries at the same time

**Files:**
- Modify: `data-agent/src/data_agent/application/run_sql.py` (`SqlTool.margin_change`)
- Test: `data-agent/tests/test_margin_change.py`

**Interfaces:** unchanged. `margin_change(...) -> str` returns the same five sections in the same order. It still returns `"no sales rows for that period and filter"` when the category has no sales, and `"query failed"` when any query fails.

- [ ] **Step 1: Write the failing test** `test_the_five_queries_run_at_once`:
  - a `GatedRunner(SectionRunner)` whose `query` counts calls and waits (`asyncio.wait_for(all_in.wait(), 1)`) until five have started;
  - assert `margin_change(*ARGS)` returns the same text the sequential test expects;
  - assert the runner saw five calls.
- [ ] **Step 2: Run** `uv run pytest tests/test_margin_change.py -q`. Expected: FAIL (`TimeoutError`: the first call waits alone).
- [ ] **Step 3: Implement.**
  - `asyncio.gather` over the five queries.
  - Check "no sales" on the category result after all return.
  - `QueryFailed` from any query returns `"query failed"`.
- [ ] **Step 4: Run** the full suite and lint. Expected: all pass, including the existing `margin_change` tests (`SectionRunner` pops answers in call order, which `gather` keeps).
- [ ] **Step 5: Commit** `perf: margin_change runs its five queries at the same time (v0.4.7)`, tag `v0.4.7`, push.

### Task 2: orchestrator: progress in the use case

**Files:**
- Modify:
  - `orchestrator/src/orchestrator/application/ask.py`;
  - `orchestrator/src/orchestrator/application/conversations.py`.
- Test:
  - `orchestrator/tests/test_ask.py`;
  - `orchestrator/tests/test_conversations.py`.

**Interfaces:**
- **The type,** in `ask.py`: `Progress = Callable[[str, dict[str, str]], None]`. It's called as `progress("step", {"step": name})` or `progress("lead", {"answer": text})`. The default is a no-op.
- **`ask(..., progress: Progress = quiet) -> ChatReply`:**
  - `step route` before routing;
  - `step <agent>` for each agent in the plan, in plan order, before the calls start;
  - in a turn with more than one agent, `lead` with the data agent's answer as soon as its reply arrives (before the other agent's, if that one is slower);
  - `step compose` before the first composer call.
  - Approvals and out of scope emit only `step route`.
- **`chat(..., progress: Progress = quiet)`:** emits `step condense` before condensing a follow-up, and passes `progress` to `ask`.

- [ ] **Step 1: Write the failing tests** (`test_ask.py`, with a `Recorder` that appends `(event, data)`):
  - `test_a_composed_turn_reports_its_steps_and_the_lead`: data and policy stubs. Expected recording, in order: `("step", {"step": "route"})`, `("step", {"step": "data-agent"})`, `("step", {"step": "policy-agent"})`, `("lead", {"answer": <data answer>})`, `("step", {"step": "compose"})`.
  - `test_the_lead_comes_when_the_data_reply_arrives`: the policy stub is blocked on an `asyncio.Event`; `lead` is recorded before the event is set.
  - `test_one_agent_reports_no_lead`: data only. Expected: `route`, then `data-agent`; no `lead` and no `compose`.
  - `test_approvals_report_only_the_route`.
  - `test_conversations.py::test_a_follow_up_reports_condense_first`: `condense` comes before `route`.
- [ ] **Step 2: Run.** Expected: FAIL (unexpected keyword `progress`).
- [ ] **Step 3: Implement.** `_asked` takes a callback for the data agent's reply. The answers don't change: every existing test in `test_ask.py` stays green unchanged.
- [ ] **Step 4: Run** the full suite and lint. Expected: all pass.
- [ ] **Step 5: Commit** `feat: the turn reports its steps and the data agent's reply as they happen`. No tag yet; Task 3 tags.

### Task 3: orchestrator `v0.9.0`: `/chat` as a stream

**Files:**
- Modify:
  - `orchestrator/src/orchestrator/adapters/inbound/http_api.py`;
  - `orchestrator/README.md` (the contract).
- Test: `orchestrator/tests/test_chat_stream.py` (new); `orchestrator/tests/test_telemetry.py`.

**Interfaces:**
- **When `/chat` streams:** the request's `Accept` header contains `text/event-stream`.
  - Body checks run first and still answer JSON 400/413.
  - The response is `EventSourceResponse` (`sse-starlette`, its default ping).
- **Events:** `event: step` / `lead` / `done` / `error`; `data:` is one JSON object.
  - `done` carries exactly the JSON path's body (`answer`, `refusal`, `agents`, `citations`, `conversation_id`).
  - `error` carries `{"error": <message>, "status": <code>}`.
  - The stream ends after `done` or `error`.
- **The turn runs in an `asyncio` task** created in the handler, which copies the request context, the token and the trace.
  - Progress goes into an `asyncio.Queue` that the event generator reads.
  - The task is kept in a module-level set until done, so a client that leaves doesn't cancel it or let it be collected.
  - The same `asyncio.timeout(turn_limit)` applies.
- **Marking failures:** on an error at 500 or above, the handler's server span (`trace.get_current_span()`, captured before streaming) gets `Status(StatusCode.ERROR)`.

- [ ] **Step 1: Write the failing tests** (`test_chat_stream.py`; a helper parses `text/event-stream` bodies into `(event, data)` pairs):
  - `test_a_streamed_turn_reports_steps_then_done`:
    - data-and-policy fakes;
    - events `step route`, `step data-agent`, `step policy-agent`, `lead`, `step compose`, `done`;
    - `done`'s body equals the JSON path's body for the same question (apart from `conversation_id`).
  - `test_without_the_stream_header_the_reply_is_json`: no `Accept` header; `content-type` is `application/json`, with today's body.
  - `test_a_bad_body_is_still_a_json_400`: stream header, `{"question": ""}`. Expected: 400 JSON.
  - `test_no_token_is_401_before_any_stream`.
  - `test_a_failure_after_the_stream_starts_is_one_error_event`, parametrized over:
    - an agent raising `AgentUnavailable` (`data-agent unavailable` 502);
    - `turn_limit=0.05` with a slow agent (`orchestrator unavailable` 502);
    - an unknown `conversation_id` (`conversation not found` 404);
    - a failing store (`conversations unavailable` 502).
    - Expected: the last event is the single `error`, with that message and status.
  - `test_a_turn_finishes_and_is_stored_when_the_client_leaves`:
    - drive the ASGI app directly, with a `receive` that returns `http.disconnect` after the first body message;
    - within 1 s, `MemoryConversationStore` holds the turn, once.
  - `test_a_streamed_reply_carries_cors_headers_for_the_web_app`: an allowed `Origin`; the response has `access-control-allow-origin`.
  - `test_telemetry.py::test_a_streamed_5xx_marks_the_request_failed`:
    - `instrument_app` with `recorded_spans()`; an unavailable agent;
    - the server span's status is `ERROR`;
    - the same test with an unknown conversation (404) leaves it `UNSET`.
  - `test_telemetry.py::test_a_streamed_turn_puts_no_text_in_spans`: the existing no-text check over a streamed turn.
- [ ] **Step 2: Run.** Expected: FAIL (JSON comes back for every request).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full suite and lint. Expected: all pass, with the existing JSON tests unchanged.
- [ ] **Step 5: Docs.** In the README, the streamed form of `/chat` beside the JSON contract: the events, their order, the `Accept` header, and errors as `error` events.
- [ ] **Step 6: Commit** `feat: /chat streams its steps when asked (v0.9.0)`, tag `v0.9.0`, push. Before committing, read the current Microsoft Learn page on Container Apps ingress (request timeout, streamed responses) and put its URL in the commit body.

### Task 4: infra: chat-failing counts failed requests

**Files:**
- Modify:
  - `infra/bicep/monitoring/alerts/chat-failing.kql`;
  - `infra/scripts/alert-rules-test.py`.

**Interfaces:**
- **The query:** `failed = countif(toint(ResultCode) >= 500 or Success == false)`, keeping the 401/403 exclusion and the thresholds.
- **The test helper:** `turn(..., ok=None)`. `ok` defaults to `code.startswith("2")`.

- [ ] **Step 1: Add the scenario** `("chat-failing", "two streamed turns that failed after their 200 headers among four", [turn("a"), turn("b"), turn("c", ok=False), turn("d", ok=False)], [], True)`.
- [ ] **Step 2: Run** `scripts/alert-rules-test.py`. Expected: the new scenario FAILs (`failed` counts only 5xx).
- [ ] **Step 3: Change the query.**
- [ ] **Step 4: Run again.** Expected: every scenario passes, the existing chat-failing ones included.
- [ ] **Step 5: Deploy monitoring** with `scripts/deploy-monitoring.sh`. Commit `alerts: chat-failing counts streamed turns that failed after their headers`, push.

### Task 5: web `v0.2.0`: the streamed chat

**Files:**
- Create: `web/src/sse.ts`, `web/src/sse.test.ts`
- Modify:
  - `web/src/api.ts`, `web/src/api.test.ts`;
  - `web/src/Chat.tsx`, `web/src/Chat.test.tsx`;
  - `web/src/messages.ts` (step labels);
  - `web/README.md`;
  - `web/package.json` version.

**Interfaces:**
- **`readEvents(body: ReadableStream<Uint8Array>): AsyncGenerator<{ event: string; data: string }>`** in `sse.ts`:
  - lines split on `\r\n`, `\n` or `\r`;
  - a blank line dispatches;
  - `event:` sets the name (default `message`);
  - `data:` lines join with `\n`;
  - `:` lines are ignored.
- **`export type Progress = { step: string } | { lead: string }`.**
- **`Api.chat(question, conversationId?, onProgress?: (p: Progress) => void): Promise<ChatReply>`:**
  - it sends `Accept: text/event-stream`;
  - a non-OK response is today's JSON error (`ApiError(status, error)`);
  - a response that isn't `text/event-stream` is read as today's JSON;
  - a `step` with a text `step` calls `onProgress({ step })`;
  - a `lead` whose `answer` is text of at most 4,000 characters calls `onProgress({ lead: answer })`;
  - `done` must pass `isChatReply`, and is returned;
  - `error` throws `ApiError(data.status, data.error)`;
  - a stream that ends without `done` or `error`, or a read that fails, throws `ApiError(0, "network")`.
- **`STEP_LABELS`** in `messages.ts`:
  - `condense`: "Reading your follow-up…"
  - `route`: "Reading the question…"
  - `data-agent`: "Checking the sales data…"
  - `policy-agent`: "Checking the policies…"
  - `action-agent`: "Preparing the draft…"
  - `compose`: "Putting the answer together…"
  - An unknown step keeps the last label.
- **`Chat.tsx`, while busy:** the waiting bubble shows today's text until the first step, then the latest step's label.
  - A `lead` shows as an assistant message above it, as text.
  - `done` replaces the early reply and the bubble with the final `Answer`.

- [ ] **Step 1: Write the failing tests:**
  - `sse.test.ts`, each case on a `ReadableStream` that yields the given chunks:
    - `test_an_event_split_across_chunks_is_read_once`;
    - `test_two_events_in_one_chunk_are_both_read`;
    - `test_crlf_line_endings_are_read`;
    - `test_comment_lines_are_ignored`;
    - `test_a_stream_without_a_final_blank_line_ends_without_the_partial_event`.
  - `api.test.ts`:
    - `test_chat_asks_for_a_stream_and_returns_done`;
    - `test_steps_and_the_lead_reach_on_progress`;
    - `test_a_lead_longer_than_4000_characters_is_dropped`;
    - `test_an_error_event_becomes_an_api_error` (`ApiError(404, "conversation not found")`);
    - `test_a_cut_off_stream_is_a_network_error`;
    - `test_a_json_reply_still_works` (an orchestrator before `v0.9.0`);
    - `test_a_done_that_fails_the_shape_check_is_unexpected`.
  - `Chat.test.tsx`, with a fake `chat` that calls `onProgress`:
    - `test_the_step_label_replaces_the_waiting_text`;
    - `test_the_early_reply_shows_before_the_answer`;
    - `test_the_final_answer_replaces_the_early_reply`: `lead` is "X", `done` is "From the sales data: X…", and "X" appears once;
    - `test_an_early_reply_is_shown_as_text_never_as_html`;
    - `test_an_error_event_shows_the_same_message_as_a_json_error`: the conversation-ended text for `ApiError(404, "conversation not found")`.
- [ ] **Step 2: Run** `npx vitest run`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `npx vitest run`, `npx tsc --noEmit` and `npm run build`. Expected: all pass.
- [ ] **Step 5: Docs.** README: the chat shows its steps and the data agent's reply as they come.
- [ ] **Step 6: Commit** `feat: the chat shows its steps and the data agent's reply as they come (v0.2.0)`, tag `v0.2.0`, push. Deploy with `infra/scripts/deploy-web.sh` in Task 7, after the orchestrator.

### Task 6: evals: the streamed path

**Files:**
- Modify:
  - `evals/src/margin_evals/live.py`;
  - `evals/src/margin_evals/judge.py`;
  - `evals/live/run_cases.py`, `evals/live/ask.py`;
  - `evals/pyproject.toml`, `uv.lock` (pins).
- Test: `evals/tests/test_live.py`, `evals/tests/test_judge.py`

**Interfaces:**
- **`sse_events(lines: Iterable[str]) -> Iterator[tuple[str, str]]`:** `(event, data)`, with the same rules as the web parser.
- **`chat_stream(env, token, question, conversation_id=None, trace_id=None) -> tuple[int, dict | None, list[tuple[str, float]]]`:**
  - returns the HTTP status;
  - the `done` body, or the `error` data, or the JSON error body;
  - each event's name with its seconds since the request.
  - `httpx.stream` with `TIMEOUT`; a transport error returns `(0, {"error": "no response: <type>"}, events)`.
- **`stream_problems(events: Sequence[str]) -> list[str]`** in `judge.py`:
  - the last event is `done` or `error`, and there's exactly one of them;
  - at least one `step` comes before it;
  - at most one `lead`.
- **`run_cases.py --stream`:**
  - judges `done` with `judge` plus `stream_problems`;
  - after each answer it prints `      stream: first step <s> s, lead <s> s, done <s> s` (a lead only when there was one).
- **`ask.py --stream`:** prints each event's name and time, then the answer.
- **Pins:** orchestrator `v0.9.0`, data-agent `v0.4.7`.

- [ ] **Step 1: Write the failing tests:**
  - `test_live.py::test_sse_events_reads_split_and_commented_streams`;
  - `test_judge.py::test_a_stream_ending_in_done_after_a_step_is_fine`;
  - `test_judge.py::test_a_stream_without_done_or_error_is_a_problem`;
  - `test_judge.py::test_two_leads_are_a_problem`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement**, update the pins, `uv lock`.
- [ ] **Step 4: Run** `uv run pytest -q`, `uv lock --check` and lint. Expected: all pass.
- [ ] **Step 5: Commit** `feat: the live suite can run on the streamed path`, push.

### Task 7: Deploy, check the stream live, the gate, measure

- [ ] **Step 1: Deploy:**
  - wait for the orchestrator and data-agent builds;
  - `infra/scripts/deploy-spike.sh deploy apps`, `sql-allow-apps.sh`;
  - wait for the revisions;
  - then `infra/scripts/deploy-web.sh`.
- [ ] **Step 2: Is the stream live?** Warm the system, then run `uv run live/ask.py --stream north.mgr "Why did dairy margin drop in the North in October 2026?"`. Expected:
  - the first `step` within 3 s;
  - `lead` well before `done`.
  - If every event arrives together at the end, the ingress buffers the stream: stop and record it. Don't work around it in this plan.
- [ ] **Step 3: The gate:**
  - `uv run live/run_cases.py --stream` three times, then `uv run live/run_cases.py` once (JSON), then `clear_drafts.py`;
  - read the answers, not only the PASS lines (echoes, leaked fields, repeated replies).
  - Expected: 54/54 on all four runs, with no stream problems.
- [ ] **Step 4: Measure**, on a warm system:
  - `ask.py --stream`: the demo question ×3, "What was dairy margin in the North in October 2026?" ×2, "Can I raise UHT milk 1 L by 3.6% in the North?" ×2;
  - plus the trace report.
  - **Expected:**
    - the first step within 3 s;
    - the demo's `lead` median at most 26 s;
    - the demo's `done` median no worse than D-044's 44.3 s by more than 3 s;
    - the data agent's step on the demo a little shorter than D-044's 18–23 s (parallel queries).
  - Every figure goes in the ledger as measured, met or not.
- [ ] **Step 5: The owner's look:** in the web app as `north.mgr`, the demo question shows the steps from the start and the data reply before the rest, and the final answer replaces it without a duplicate.

### Task 8: `docs` and the vault

- [ ] **Step 1: docs:**
  - D-045 and the summary table;
  - D-029 amended (the streamed form);
  - D-044's "Not yet" points at D-045;
  - the security model, a "Streaming" section:
    - the same token check before the stream;
    - the token in the header, never the URL;
    - no new data (the lead is the validated reply the answer leads with; steps are fixed names);
    - errors only as the JSON path's messages;
  - `research/2026-11-latency-baseline.md`, a "Streaming (2026-11-2x)" section with the measured times to the first step, the lead and done;
  - the roadmap line after the latency fixes; README status; this plan's outcome note.
  - Scan for real IDs. Commit, push.
- [ ] **Step 2: Vault:**
  - repo pages: orchestrator, data-agent, web, evals, infra;
  - Home;
  - the decisions index;
  - the release note "Answers as they come";
  - the chat-failing runbook (it now counts streamed turns that failed after their headers).
