# Milestone 10: Full Bicep and Deploys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One Bicep deployment builds the whole system, and a push to `main` in a service repo tests it, runs its evals, deploys it through GitHub OIDC and smoke-tests it, with no stored credential anywhere.

**Outcome (2026-11-27):** done. One subscription-scope Bicep deployment builds the whole system; `deploy.sh what-if|create` keeps every live image and replaced the eight deploy scripts. The five services and the web app deploy on a push to `main` through GitHub OIDC, each with its own deploy identity, and no credential is stored anywhere. The live gate passed 54/54 three runs in a row (17.0 and 16.7 s, $0.0040 a question; the second run's cost report hit a network timeout). Final versions: orchestrator `v0.9.3`, data-agent `v0.4.8`, policy-agent `v0.1.9`, action-agent `v0.1.3`, proposals-api `v0.3.0`, shared `v0.5.0`, web `v0.3.1`. Decision: D-046. Deviations, from the run ledger:
- The deployment is named after `NAME_PREFIX`, not `margin`, so two prefixes can share a subscription.
- `deploy.sh` reads every live image with one `az containerapp list`; a list that can't be read stops the script instead of guessing. The SQL firewall rule `laptop` moves to the machine's current IP, as `deploy-data.sh` did. The alerts wait on the apps by `dependsOn`, and web deploys before the apps (they need its hostname).
- Each service's deploy identity has a second "Container Apps Contributor" assignment, on the environment: writing an app checks the environment's join permission. That makes two assignments per service and one for web. Task 6 Step 3's custom role wasn't needed.
- The wait also requires the new revision to be the app's latest ready revision, and fails on `ActivationFailed`. The planned criteria (`Provisioned`, 100% of traffic) passed a revision that never became ready, shown live with an image that never listens on port 8000.
- A missing image fails at the deploy step, not the wait: Azure checks the image manifest before it creates a revision. The old revision kept serving.
- Entra refused the branch with AADSTS700213 (the plan said AADSTS70021; same meaning).
- The deploy action is pinned to its v2 tag's commit SHA (no v2.x.y tags exist), with telemetry off.
- Concurrency is workflow-level, per ref, instead of a job-level `deploy` group: the job-level group ordered deploys by when each deploy job queued, not by push order. A newer waiting run replaces an older waiting one, so a middle push of three quick ones never deploys. The deploy job has a 15-minute limit.
- Tags: orchestrator `v0.9.2` stays on its first commit, whose lint run failed on a test comment (same code). `v0.9.3` adds "a blank `STREAM_SHUTDOWN_GRACE_SECONDS` means the default", and evals pins it. Web `v0.3.0` was tagged on an incomplete commit (a failed `git add`); `v0.3.1` holds the full change. Neither old tag was moved: no force push.
- Web's smoke reads the site's hostname with `az staticwebapp show` after signing in, instead of a new secret. Two `@emnapi` entries were added to web's lock file (`npm ci` had failed on Linux).
- The gate's first run got 48/54: six cases never connected, because the laptop's network failed in bursts. The live runner now retries only a connection that never opened (D-033), and the gate restarted from run 1.
- Task 8's baseline replaced infra's `ci.yml`, which dropped the Bicep build and script tests Task 2 had added there (found in the final review; to be restored as a separate `check.yml`).
- The owner skipped Task 7 Step 6 (the browser look): the CSP is checked by the deploy's smoke, not yet in a browser.
- Budget (owner, 2026-11-27): the $200 free credit, until it runs out or the trial ends, replaces $20 (D-024).

**Architecture:**
- **One deployment instead of eight:** `infra/bicep/main.bicep` (subscription scope) creates the resource group and the budget and calls `resources.bicep`, which composes today's modules in dependency order: identities, monitoring, storage, search, models, data, apps, alerts, web, deploy identities. The "apps, monitoring, apps again" order disappears: the restart alerts move to their own module after the apps.
- **`infra/scripts/deploy.sh what-if|create`** replaces the eight `deploy-*.sh` Bicep scripts. It reads `.env`, resolves IDs at run time (app registrations, groups, the laptop's IP, the GitHub IDs) and **keeps each app's live image**, so an infra deploy never rolls back a pushed one. Infra still deploys from the laptop.
- **One deploy identity per deployable repo** (five services and web): a user-assigned managed identity with one federated credential for that repo's `main` branch, allowed to update only its own app.
- **Per-repo workflow:** test → image → evals gate (orchestrator, data-agent) → deploy → smoke. A new revision takes traffic only when it is ready; a broken one leaves the old revision serving.
- **The web app** deploys the same way; its build writes the CSP with the two APIs' exact hosts.

**Tech Stack:** Bicep CLI 0.49.2; `Microsoft.App/containerApps@2026-07-01`; GitHub Actions: `azure/login` v3.1.0, `Azure/container-apps-deploy-action` v2, `actions/checkout` v7, `actions/setup-node` v7, `astral-sh/setup-uv` v10.3.3 (v10.4.0 is under 14 days old), gitleaks 8.30.1, `@azure/static-web-apps-cli` 2.1.0 (still the latest).

**Spec:**
- **The owner (2026-11-25):** "go", after choosing "Milestone 10 first" over more latency work, with cold starts left to the sign-in warm-up.
- **What the owner was told:**
  - full Bicep for everything;
  - a GitHub Actions deploy per repo through OIDC, gated by evals;
  - the carried items: stop grace against the 25 s stream grace, exact CSP hosts, the deploy script's lookup by display name, the gitleaks SHA-256 pin, the deploy order;
  - pinned versions re-checked; no paid resource.
- **`roadmap.md` row 10:** "Full Bicep + per-repo GitHub Actions deploys (OIDC) — A push to main deploys that service; evals gate it."
- **`decisions.md`:**
  - D-007: OBO at every hop, no secrets;
  - D-016: public service repos, private infra without secrets;
  - D-019: CI can't sign in as test users (MFA);
  - D-026: everything account-specific is configuration;
  - D-027: app registrations by script;
  - D-033: the live gate, three runs; "Revisit at milestone 10";
  - D-042: the CSP's accepted risk, "GitHub OIDC deploys come with milestone 10";
  - D-043: the deploy order; D-045: the stream grace.
- **Carried minors:** M0 #5 (gitleaks pin), M1 #4 (lookup by display name), M8 #5 (CSP hosts), M9 (deploy order), streaming (`terminationGracePeriodSeconds`).

## Global Constraints

- No secrets in any repo, image or log. Prefer keyless: GitHub OIDC and managed identities.
- No owner-specific values in code or docs: tenant, subscription, org and repo IDs, names and URLs are read at run time or set in a gitignored `.env`, every setting listed in `.env.example`.
- Agent services keep internal ingress. The environment keeps peer-to-peer encryption on.
- Every service still validates every request with `shared`; nothing in this plan changes a token check.
- Pin exact versions (actions by their exact release tag, at least 14 days old).
- Before writing Azure or GitHub Actions code, read the current Learn or GitHub page and put its URL in the commit body.
- Tests first: every script change has a test that fails first; workflow changes are proven by a run whose result is read.
- Never create a paid Azure resource. Managed identities, federated credentials and role assignments are free.
- The milestone gate (D-033): 54/54 live cases, three full runs in a row, on the final versions.
- Commit and push as the tasks list; the owner's approval of this plan covers those pushes.

## Cost

- **Azure:** nothing new that bills. Six managed identities, six federated credentials, six role assignments: free. A deploy runs a second revision until the old one stops (at most 4 minutes for the orchestrator), inside the Container Apps free grant.
- **GitHub:** Actions on public repos are free; infra's CI (Bicep build and shell tests, about 1 minute a run) uses its $12 monthly included credit.
- **Model calls:** the gate's three live runs, about $0.65.

## Decisions in this plan (for the owner's review)

1. **What "evals gate it" means without a test-user sign-in in CI** (D-019, D-033):
   - before deploying: the repo's own tests, then, for orchestrator and data-agent, the evals CI suite (fake adapters) against the pushed commit;
   - after deploying: smoke checks that need no user token. External apps answer `401` without a token and a CORS preflight from the web origin. Every app's new revision becomes ready, or the workflow fails and the old revision keeps serving;
   - the live suite stays the owner's laptop gate per milestone, as D-033 says.
   - **Rejected:** test-user passwords in Key Vault (password sign-in fails with MFA, D-019); a self-hosted runner holding the owner's test-user tokens (a public repo's workflow running on the owner's laptop).
2. **One deploy identity per repo, scoped to its own app:**
   - a managed identity `id-<prefix>-gh-<repo>` with one federated credential for `repo:<org>@<org-id>/<repo>@<repo-id>:ref:refs/heads/main` (GitHub's immutable subject for repositories created after 15 July 2026);
   - "Container Apps Contributor" on its app only; web gets "Contributor" on the Static Web App only, to read its deployment token at deploy time.
   - Created in Bicep: a federated credential on a managed identity needs no Graph call, unlike D-027's app registrations.
   - **Rejected:** one identity for every repo (one compromised repo could redeploy every app).
3. **Infra deploys from the laptop**, with the owner's `az` sign-in. An infra deploy assigns roles, so doing it from GitHub would need an Owner-level identity in CI. infra's CI builds the Bicep and runs the script tests.
4. **IDs go in GitHub secrets, not variables:** tenant, subscription and client IDs aren't credentials, but a public repo's logs are public, and secrets are masked in them.
5. **Single revision mode stays,** with a TCP readiness probe on port 8000: a new revision gets traffic only once ready. **Rejected:** multiple revisions with a 0% label, because the agents' internal ingress can't be reached from GitHub to test the label.
6. **Stop grace** (`terminationGracePeriodSeconds`): orchestrator 240 s (the turn limit is 230 s) with its stream grace at 235 s; the agents 120 s; proposals-api the default 30 s. A deploy no longer cuts a long streamed turn.
7. **A full infra deploy keeps the live images:** `deploy.sh` reads each app's current image and passes it to Bicep. A brand-new app falls back to `sha-<7>` of the repo's `main` on GitHub.
8. **The CSP lists the exact hosts:** the web build writes `connect-src` with the orchestrator's and proposals-api's origins instead of `*.azurecontainerapps.io` (D-042's accepted risk).

## Review Focus

1. **A pull request, a fork or any branch except `main` gets no Azure token and deploys nothing.** The deploy job runs only on a push to `main`, and the federated credential's subject matches only `main`. Test: Task 6 Step 5 (a branch run's `azure/login` fails with AADSTS70021).
2. **A revision that never becomes ready** (a missing image, a crash at start) **fails the workflow and leaves the old revision serving.** Test: Task 6 Step 6 (deploy a tag that doesn't exist; the old revision keeps answering).
3. **A full infra deploy doesn't roll back an image a push deployed.** Test: Task 2 `deploy-images.test.sh` (`deploy.sh` passes the live image), and the what-if in Task 2 Step 6 shows no image change.
4. **Two pushes close together deploy in order,** and the later commit ends up live. Test: Task 6 `concurrency` group with `cancel-in-progress: false`, checked in Step 7 by two pushes a minute apart.
5. **Public deploy logs show no tenant, subscription or client ID and no token.** Test: Task 6 Step 8 and Task 7 Step 7 (`gh run view --log` grepped for each ID: no match).

---

### Task 1: infra: one app lookup that refuses ambiguity

**Files:**
- Modify: `infra/scripts/config.sh` (add `check_prefix`, `app_id`)
- Modify: `infra/scripts/entra-apps.sh:20`, `deploy-spike.sh:14`, `spike-env.sh:8`, `web-env.sh:9`, `data-env.sh:22` (use `app_id`)
- Create: `infra/tests/app-lookup.test.sh` (fake `az`, in the style of `sql-allow-apps.test.sh`)

**Interfaces:**
- Produces: `check_prefix` (exits 1 unless `NAME_PREFIX` matches `^[a-z][a-z0-9-]{1,19}$`); `app_id <display-name>` prints the one matching appId; exits 1 with `"<name>: N app registrations"` when there are none or several. `entra-apps.sh`'s `ensure_app` creates the app on 0 matches and stops on 2 or more.

- [ ] **Step 1: Write `app-lookup.test.sh`:** a fake `az ad app list` returning 0, 1 or 2 appIds by display name. It asserts:
  - one match prints the appId;
  - none and two exit 1 with the message;
  - `NAME_PREFIX="x' or 1 eq 1"` exits 1 before any `az` call;
  - `ensure_app` creates on none and stops on two.
- [ ] **Step 2: Run it.** Expected: FAIL (no `app_id` in `config.sh`).
- [ ] **Step 3: Implement** `check_prefix` and `app_id` in `config.sh`; call `check_prefix` where scripts read `NAME_PREFIX`; replace the five lookups.
- [ ] **Step 4: Run** `bash infra/tests/app-lookup.test.sh && bash infra/tests/sql-allow-apps.test.sh && infra/scripts/entra-apps-check.sh`. Expected: PASS, PASS, the check passes against the live tenant.
- [ ] **Step 5: Commit** (infra) "fix: an app lookup by name must find exactly one app (M1 minor 4)"; push.

### Task 2: infra: one Bicep deployment that keeps the live images

**Files:**
- Create: `infra/bicep/main.bicep` (subscription scope: resource group, budget, `resources` module)
- Create: `infra/bicep/resources.bicep` (resource-group scope: the modules in order)
- Create: `infra/bicep/identities.bicep` (the five service identities, moved out of `spike/main.bicep`)
- Move: `infra/bicep/spike/` → `infra/bicep/apps/` (environment and apps; identities by `existing`)
- Modify: `infra/bicep/monitoring/main.bicep` (no `alerts` module call; outputs what alerts need)
- Create: `infra/scripts/deploy.sh`, `infra/scripts/outputs.sh` (`output <name>` from the `margin` deployment)
- Modify: `spike-env.sh`, `web-env.sh`, `data-env.sh`, `sql-allow-apps.sh`, `deploy-web.sh` (read `outputs.sh`; `deploy-web.sh` keeps only `site`)
- Delete: `deploy-spike.sh`, `deploy-data.sh`, `deploy-models.sh`, `deploy-search.sh`, `deploy-storage.sh`, `deploy-monitoring.sh`, `deploy-budget.sh`
- Create: `infra/tests/deploy-images.test.sh`
- Modify: `infra/.github/workflows/ci.yml` (job `check`: `az bicep build --file bicep/main.bicep`, then every `tests/*.test.sh`)
- Modify: `infra/.env.example`, `infra/README.md`

**Interfaces:**
- Produces: deployment `margin` (subscription scope) with outputs `resourceGroup`, `orchestratorUrl`, `proposalsApiUrl`, `dataAgentFqdn`, `sqlServer`, `databaseName`, `projectEndpoint`, `chatModel`, `searchEndpoint`, `tableEndpoint`, `connectionString`, `workspaceId`, `workspaceCustomerId`, `webHostname`, `webName`, and (from Task 3) `deployClientIds` (object: repo → client ID).
- `deploy.sh what-if|create`: every parameter today's scripts pass, plus the five `*Image` values. Each image is the app's live `properties.template.containers[0].image`, or, for an app that doesn't exist yet, `ghcr.io/<org>/<repo>:sha-<7>` of `gh api repos/<org>/<repo>/commits/main`. After `create` it runs `sql-allow-apps.sh`.

- [ ] **Step 1: Write `deploy-images.test.sh`:** a fake `az` where `containerapp show` returns `ghcr.io/o/orchestrator:sha-live123` for the orchestrator and fails for policy-agent, and a fake `gh` returning `abcdef1234` for policy-agent's `main`. It asserts that `deploy.sh what-if` passes `orchestratorImage=ghcr.io/o/orchestrator:sha-live123` and `policyAgentImage=ghcr.io/o/policy-agent:sha-abcdef1`.
- [ ] **Step 2: Run it.** Expected: FAIL (no `deploy.sh`).
- [ ] **Step 3: Write the Bicep.**
  - Read the Learn pages for `Microsoft.App/containerApps` (2026-07-01) and Bicep modules first.
  - `resources.bicep` order: identities → monitoring → storage, search, models, data (each `dependsOn` identities) → apps (gets `connectionString` and `workspaceId` from monitoring) → `monitoring/alerts.bicep` (gets the apps' IDs) → web.
  - Resource names and properties stay exactly as deployed today. Image tags become full image references (`*Image`).
- [ ] **Step 4: Write `deploy.sh` and `outputs.sh`;** move the extra logic from the deleted scripts:
  - the laptop IP;
  - the budget's existing start date;
  - the alert email fallback to the budget contact;
  - the region-group lookup.
- [ ] **Step 5: Run** `bash infra/tests/deploy-images.test.sh` and `az bicep build --file infra/bicep/main.bicep`. Expected: PASS; builds with no warnings.
- [ ] **Step 6: What-if against the live account:** `infra/scripts/deploy.sh what-if`.
  - Expected: no `Delete` and no replacement; no image change on any app. Allowed: nested deployment records, and property noise the what-if reports on unchanged resources.
  - Anything else gets a ledgered ruling before Step 7.
- [ ] **Step 7: Create:** `infra/scripts/deploy.sh create`, then `infra/scripts/monitoring-check.sh` and `uv run live/ask.py north.mgr "What was dairy margin in the North in October 2026?"` (evals). Expected: deployment `Succeeded`; the monitoring check passes; 21.3% in the answer.
- [ ] **Step 8: Commit** (infra) "feat: one Bicep deployment for the whole system; deploys keep the live images", with the Learn URLs; push. CI's `check` job passes.

### Task 3: infra: deploy identities, stop grace, readiness, GitHub secrets

**Files:**
- Create: `infra/bicep/deploy/main.bicep` (per repo: identity, federated credential, role assignment)
- Modify: `infra/bicep/resources.bicep` (call it; output `deployClientIds`), `infra/bicep/apps/main.bicep` (grace, probes, `STREAM_SHUTDOWN_GRACE_SECONDS`)
- Create: `infra/scripts/github-secrets.sh`, `infra/tests/github-secrets.test.sh`
- Modify: `infra/scripts/deploy.sh` (reads `gh api repos/<org>/<repo> --jq '.id'` and `.owner.id`)

**Interfaces:**
- Consumes: Task 2's `deploy.sh` and outputs.
- Produces:
  - identities `id-<prefix>-gh-<repo>` for `orchestrator`, `data-agent`, `policy-agent`, `action-agent`, `proposals-api`, `web`;
  - each with one federated credential: issuer `https://token.actions.githubusercontent.com`, audience `api://AzureADTokenExchange`, subject `repo:<org>@<org-id>/<repo>@<repo-id>:ref:refs/heads/main`;
  - roles: "Container Apps Contributor" (`358470bc-b998-42bd-ab17-a7e34c199c0f`) on `<prefix>-<repo>`; web: "Contributor" on the Static Web App.
- Apps:
  - orchestrator: `terminationGracePeriodSeconds: 240`, env `STREAM_SHUTDOWN_GRACE_SECONDS=235`;
  - the three agents: `terminationGracePeriodSeconds: 120`;
  - all five apps: a TCP readiness probe on 8000.
- `github-secrets.sh` sets, with `gh secret set --repo <org>/<repo>`:
  - every deployable repo: `AZURE_CLIENT_ID` (its own deploy identity), `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`;
  - services: `CONTAINER_APP_NAME`;
  - web: `STATIC_WEB_APP_NAME` and the six `VITE_*` values `web-env.sh` writes today.

- [ ] **Step 1: Write `github-secrets.test.sh`** with a fake `gh` that records calls. Assert:
  - each repo gets only its own `AZURE_CLIENT_ID`;
  - web gets the six `VITE_*` names;
  - no value is ever passed on the command line (values go in on stdin, so they never show in `ps`).
- [ ] **Step 2: Run it.** Expected: FAIL (no script).
- [ ] **Step 3: Write the Bicep and the script.** Read the Learn pages on federated credentials for user-assigned identities and on Container Apps health probes first.
- [ ] **Step 4: Run** the test and `az bicep build`. Expected: PASS; builds.
- [ ] **Step 5:** `deploy.sh what-if`, then `create`, then `github-secrets.sh`.
  - The what-if should show only: the six identities, the federated credentials and role assignments; grace, probe and env changes on the apps.
  - `az role assignment list --assignee <each deploy identity> --all` should show exactly one assignment each, scoped to its own app or the Static Web App.
- [ ] **Step 6: Commit** (infra) "feat: a deploy identity per repo, stop grace and readiness probes", with the Learn URLs; push.

### Task 4: orchestrator `v0.9.2`: the stream grace from settings

**Files:**
- Modify: `orchestrator/src/orchestrator/adapters/inbound/http_api.py` (`create_http_app(..., stream_grace: float = SHUTDOWN_GRACE_SECONDS)`), `orchestrator/src/orchestrator/main.py` (reads `STREAM_SHUTDOWN_GRACE_SECONDS`), `README.md`, `.env.example`
- Test: `orchestrator/tests/test_chat_stream.py`, `orchestrator/tests/test_main.py`

**Interfaces:** `create_http_app` gains `stream_grace: float`, passed to `EventSourceResponse(shutdown_grace_period=stream_grace)`. The setting is a non-negative number of seconds, default 25.

- [ ] **Step 1: Write the tests.**
  - `test_the_stream_grace_comes_from_the_app` (an app built with `stream_grace=0.01` gives up on a gated turn after a shutdown);
  - `test_a_bad_stream_grace_is_refused` (`"-1"` and `"soon"` fail at start with the setting's name).
- [ ] **Step 2: Run them.** Expected: FAIL (unexpected keyword `stream_grace`).
- [ ] **Step 3: Implement;** README: the setting and its Bicep value.
- [ ] **Step 4: Run** `uv run pytest -q`, `ruff check`, `ruff format --check`. Expected: all pass (147 + 3).
- [ ] **Step 5: Commit** "feat: the stream's shutdown grace is a setting (v0.9.2)"; tag `v0.9.2`; push. Bump evals' pin in Task 9.

### Task 5: evals: a gate other repos can call

**Files:**
- Create: `evals/scripts/gate.sh` (`gate.sh <service> <sha>`), `evals/.github/workflows/gate.yml`
- Modify: `evals/README.md`

**Interfaces:**
- Produces: a reusable workflow `margin-copilot/evals/.github/workflows/gate.yml@main`, `on: workflow_call` with inputs `service` (`orchestrator` | `data-agent`) and `sha` (40 hex).
- It runs `scripts/gate.sh`:
  1. `uv sync --locked`;
  2. `uv pip install "<service> @ git+https://github.com/margin-copilot/<service>@<sha>"`;
  3. `uv run --no-sync pytest -q -rxX`.
- `gate.sh` exits 2 on any other service name or a malformed sha, before installing anything.

- [ ] **Step 1: Run the gate before it exists:** `scripts/gate.sh orchestrator <v0.9.1's sha>`. Expected: FAIL (no such file).
- [ ] **Step 2: Write `gate.sh`.**
- [ ] **Step 3: Run it four times:**
  - with `orchestrator <v0.9.1's sha>`: passes (111 passed, 54 skipped, 1 xfailed);
  - with `orchestrator 0000000000000000000000000000000000000000`: exits non-zero at install;
  - with `policy-agent <any sha>`: exits 2;
  - with `orchestrator main`: exits 2.
- [ ] **Step 4: Write `gate.yml`** (read GitHub's reusable-workflows page first; `permissions: contents: read`).
- [ ] **Step 5: Commit** "feat: a reusable gate that runs the CI suite against another repo's commit", with the GitHub docs URL; push.

### Task 6: the five services deploy on push

**Files (each of orchestrator, data-agent, policy-agent, action-agent, proposals-api):**
- Modify: `.github/workflows/build.yml` (jobs `gate` for orchestrator and data-agent, then `deploy`)
- Modify: `README.md` ("Deploy" section)

**Interfaces:**
- Consumes: Task 3's secrets, Task 5's `gate.yml`.
- `deploy` job:
  - `needs: [image]` (plus `gate` where it exists);
  - `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`;
  - `permissions: id-token: write, contents: read`;
  - `concurrency: { group: deploy, cancel-in-progress: false }`.
- `deploy` steps:
  1. `azure/login` (exact v3.1.0 tag) with the three ID secrets;
  2. `Azure/container-apps-deploy-action` (exact v2 tag) with `imageToDeploy: ghcr.io/${{ github.repository }}:sha-<7>`, `containerAppName`, `resourceGroup`;
  3. a wait, up to 5 minutes, until the new revision's `provisioningState` is `Provisioned` and it holds 100% of the traffic. It fails on `Failed` or at the limit. The readiness probe means traffic moves only to a revision that is listening;
  4. smoke for the two external apps:
     - orchestrator: `POST /chat` with no token → `401`, and `OPTIONS /chat` from the web origin → `200` with `access-control-allow-origin`;
     - proposals-api: `GET /proposals` with no token → `401`.

- [ ] **Step 1:** Read the Learn page for GitHub Actions with Container Apps and the `azure/login` README.
- [ ] **Step 2: Orchestrator first:** add `gate` and `deploy`; push.
  - Expected: test, image, gate and deploy are all green.
  - The app's image is `sha-<the pushed 7>`.
  - `ask.py north.mgr "What was dairy margin in the North in October 2026?"` still answers 21.3%.
- [ ] **Step 3: If "Container Apps Contributor" can't update the app** (an authorization error on `containerApps/write`), add a custom role in `deploy/main.bicep` with exactly `Microsoft.App/containerApps/read`, `write`, `revisions/read` and `Microsoft.App/managedEnvironments/join/action`, then redeploy infra. Ledger the ruling.
- [ ] **Step 4: Data-agent** (with `gate`), then policy-agent, action-agent and proposals-api: the same job, one push each. Expected: green runs; images match the pushed SHAs.
- [ ] **Step 5: A branch gets no token:** push a branch `try-oidc` whose workflow runs `azure/login` without the `main` condition, then delete the branch. Expected: AADSTS70021 (no matching federated identity), nothing deployed.
- [ ] **Step 6: A revision that never becomes ready keeps the old one.**
  1. Add a temporary `workflow_dispatch` trigger with an `image` input to the orchestrator's `deploy` job. Its subject is still `main`.
  2. Run it with `image: ghcr.io/margin-copilot/orchestrator:sha-0000000`.

  Expected:
  - the workflow fails at the wait;
  - `az containerapp revision list` shows the old revision at 100%;
  - `ask.py` still answers.

  Then remove the trigger.
- [ ] **Step 7: Two pushes a minute apart** (orchestrator README typo fix, then another). Expected: the second deploy waits for the first; the live image is the second SHA.
- [ ] **Step 8: Logs:** `gh run view <id> --log` for one deploy per repo, grepped for the tenant, subscription and client IDs. Expected: no match (masked as `***`).
- [ ] **Step 9: Commit** each repo "feat: a push to main deploys this service through GitHub OIDC", with the Learn and GitHub URLs; push.

### Task 7: web `v0.3.0`: exact CSP hosts and a deploy on push

**Files:**
- Create: `web/scripts/write-config.mjs`, `web/src/config.test.ts`
- Move: `web/public/staticwebapp.config.json` → `web/staticwebapp.config.template.json` (`connect-src` placeholder `__API_ORIGINS__`)
- Modify: `web/package.json` (`build` runs `write-config.mjs` after `vite build`; version 0.3.0)
- Create: `web/.github/workflows/build.yml` (test and deploy jobs); `web/.github/workflows/ci.yml` becomes the baseline secret scan
- Modify: `infra/scripts/deploy-web.sh` (the same build), `web/README.md`

**Interfaces:**
- `writeConfig(template: string, urls: string[]): string` replaces `__API_ORIGINS__` with each URL's origin, space-separated. It throws on a non-`https:` URL or one with a path, query or fragment.
- The deploy job:
  1. `azure/login` with the web identity;
  2. `az staticwebapp secrets list -n <name> --query properties.apiKey -o tsv`, masked with `::add-mask::`;
  3. `npx --no-install swa deploy dist --env production`.
- Smoke: `curl -sI https://<webHostname>` → `200`, and a `content-security-policy` header that contains the two exact origins and no `*.azurecontainerapps.io`.

- [ ] **Step 1: Write `config.test.ts`:**
  - two https URLs become two origins in `connect-src`;
  - `http://x` throws;
  - `https://x/path` throws;
  - the result has no `*`.
- [ ] **Step 2: Run it.** Expected: FAIL (no module).
- [ ] **Step 3: Implement `writeConfig` and the template;** move the test job out of `ci.yml`.
- [ ] **Step 4: Run** `npx vitest run`, typecheck, `npm run build` (with the `VITE_*` values in the environment). Expected: 52 + 4 passed; `dist/staticwebapp.config.json` has the exact origins.
- [ ] **Step 5: Push.** Expected: green test and deploy runs; the smoke passes.
- [ ] **Step 6: The owner's look:** sign in at the site as north.mgr, ask the data question, and open Approvals. Expected: both work. That shows the CSP allows both APIs, which only a browser enforces. Asked in the final message if the plan runs unattended.
- [ ] **Step 7: Logs:** as Task 6 Step 8, for the web run and the deployment token. Expected: no match.
- [ ] **Step 8: Commit** "feat: exact API hosts in the CSP, and a deploy on push through GitHub OIDC (v0.3.0)"; tag `v0.3.0`; push.

### Task 8: every repo pins gitleaks by its SHA-256

**Files:**
- Modify: `docs/templates/repo-baseline/ci.yml`, `docs/templates/test-apply-baseline.sh`
- Apply: `docs/templates/apply-baseline.sh` to the eleven repos

**Interfaces:** the baseline `ci.yml` downloads only `gitleaks_8.30.1_linux_x64.tar.gz` and checks it with `echo "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb  gitleaks_8.30.1_linux_x64.tar.gz" | sha256sum --check`. It no longer downloads the checksums file.

- [ ] **Step 1: Extend `test-apply-baseline.sh`:** the applied `ci.yml` contains that hash and no `checksums.txt`.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Update the template; apply** to the eleven repos.
- [ ] **Step 4: Run** the test, then push each repo. Expected: PASS; every repo's secret-scan run is green.
- [ ] **Step 5: Commit** each "ci: pin gitleaks by its SHA-256 (M0 minor 5)".

### Task 9: the gate

- [ ] **Step 1: Pin evals** to orchestrator `v0.9.2` (data-agent stays `v0.4.8`); `uv lock`; `uv run pytest -q`. Expected: 111 passed, 54 skipped, 1 xfailed. Commit, push.
- [ ] **Step 2: Three runs:** `uv run live/run_cases.py --stream` three times, then `live/clear_drafts.py`.
  - Expected: 54/54 on each run, with no stream problems.
  - Read the answers: no echoes, no leaked fields.
- [ ] **Step 3: Check the deploy state:** every app's image equals its repo's `main` SHA. `infra/scripts/deploy.sh what-if` shows no change.

### Task 10: `docs` and the vault

- [ ] **Step 1: docs:**
  - D-046 "Deploys: one Bicep deployment, a deploy identity per repo through GitHub OIDC; evals gate before, smoke after", with Decisions 1–8 above;
  - D-033: "Revisit at milestone 10" answered by D-046;
  - D-042: the CSP's exact hosts and the deployment token read through OIDC;
  - D-027: GitHub's federated credentials live on managed identities in Bicep;
  - D-043: the deploy order is gone;
  - the security model: a "Deploys" section (what each identity can touch; what CI can't do; the logs);
  - a new `guides/run-it-yourself.md`: `.env`, `entra-seed.sh`, `entra-apps.sh`, `deploy.sh`, the data load, `github-secrets.sh`, a push;
  - `CLAUDE.md`'s pinned versions: the GitHub Actions and Bicep versions above;
  - the roadmap row 10; README status; this plan's outcome note.
  - Scan for real IDs. Commit, push.
- [ ] **Step 2: Vault:**
  - repo pages: infra, the five services, web, evals;
  - Home; the decisions index;
  - milestone page M10;
  - release note "Every push deploys itself";
  - runbooks: "Deploy the M1 spike" replaced by "Deploy everything"; "Run the live checks".
