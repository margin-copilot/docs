# Run it yourself

How to build the whole system on your own Azure subscription and GitHub organization, from an empty account to a push that deploys itself. Every account-specific value is a setting (D-026); nothing in the code names the owner's account.

The infra repo is private (D-016): it holds no secrets, but it isn't published. These steps name its scripts so you can follow what they do.

## What you need

- An Azure subscription (the free account works; nothing here needs a paid tier) and a Microsoft Entra tenant where you can create users, groups and app registrations.
- The Azure CLI signed in to that subscription (`az login`), with Bicep (`az bicep install`).
- The GitHub CLI signed in (`gh auth login`) with admin rights on your organization: `deploy.sh` reads the organization's and the repos' IDs, and `github-secrets.sh` sets secrets.
- The eleven repos in your organization, cloned side by side in one folder (see [roadmap.md](../roadmap.md)). Container images are published to `ghcr.io/<your-org>/` and must be public, so Container Apps pulls them without a credential.
- `uv` and Python 3.12; Node 24 for the web app.

## 1. Settings: `.env`

In the infra repo, copy `.env.example` to `.env` and fill it in. `.env` is gitignored; every setting is listed, with its default, in `.env.example`. The main ones:

- `ALERT_EMAIL`: where the budget and monitoring alerts go (required on a new account);
- `BUDGET_AMOUNT`: the monthly budget in the subscription's billing currency (default 20; alerts at 50% and 90%);
- `RESOURCE_GROUP`, `NAME_PREFIX`, `AZURE_LOCATION` (default `francecentral`), `WEB_LOCATION` (default `eastus2`);
- `GITHUB_ORG`: your organization;
- `TEST_USERS`, `TEST_GROUPS`, `ADMIN_USERS`: the test users, their groups, and the work account that administers the database.

## 2. Test users and groups: `entra-seed.sh`

```bash
scripts/entra-seed.sh     # users and groups from .env; safe to run again
scripts/entra-check.sh    # lists anything missing
```

Temporary passwords go to a private file under your home folder, never to the terminal. Sign in once as each user to set a password and MFA.

## 3. App registrations: `entra-apps.sh`

```bash
scripts/entra-apps.sh          # one app registration per service, the web app, the CLI apps; consent grants
scripts/entra-apps-check.sh
```

The apps' federated credentials trust the services' managed identities, which the next step creates. On a new account, run `entra-apps.sh` again after the first `create` below; that run also adds the web app's redirect URI.

## 4. Everything in Azure: `deploy.sh`

```bash
scripts/deploy.sh what-if   # what would change
scripts/deploy.sh create    # one subscription deployment named after NAME_PREFIX
```

`create` builds the resource group, the budget, identities, monitoring, storage, search, models, the database, the web app's site, the container apps, the deploy identities and the alerts. It then lets the data agent through the SQL firewall (`sql-allow-apps.sh`). Things to know:

- `gh` must be signed in: `deploy.sh` reads GitHub's IDs for the deploy identities and, for an app that doesn't exist yet, the commit on its repo's `main`. That commit's image must exist: push each service's `main` once first, so its `build` workflow publishes `ghcr.io/<your-org>/<repo>:sha-<7>`. Its deploy job fails until step 6; the image is published anyway.
- An app that already exists keeps the image it runs, so an infra deploy never rolls back a pushed one.
- The SQL firewall rule `laptop` follows your current public IP. If your IP changes (error 40615), run `create` again.
- The what-if always lists some noise: properties the services fill in themselves, and values passed from one module to another, shown as `reference(...)`.
- The other scripts read this deployment's outputs (`scripts/outputs.sh`). While a `create` runs, or after a failed one, those outputs are empty: don't run `entra-apps.sh` then, or the web app's redirect URIs shrink to localhost. Run `create` again until it succeeds.

## 5. The data

```bash
scripts/data-env.sh                   # prints the account-specific lines for data/.env
cd ../data
cp .env.example .env                  # then add the lines data-env.sh printed
uv run riad-data load                 # browser sign-in as the database admin
uv run riad-data verify
uv run riad-data policies             # the policy clauses, into AI Search
```

The loader creates the database users and the reader role, then the tables, rows and region security in one transaction.

## 6. GitHub secrets: `github-secrets.sh`

```bash
scripts/github-secrets.sh
```

It sets, on each of the six deployable repos, `AZURE_CLIENT_ID` (that repo's own deploy identity), `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` and `AZURE_RESOURCE_GROUP`; `CONTAINER_APP_NAME` on the five services; `STATIC_WEB_APP_NAME` and the six `VITE_*` build settings on web. The IDs aren't credentials, but secrets are masked in public logs (D-046). Values go to `gh` on stdin.

## 7. A push

Push a commit to `main` in any service repo. Its `build` workflow runs:

1. the repo's tests;
2. the image, `ghcr.io/<your-org>/<repo>:sha-<7>`;
3. for the orchestrator and the data agent, the evals gate: the CI suite against that commit;
4. the deploy, through GitHub OIDC as the repo's deploy identity;
5. a wait until the new revision is ready and serves all traffic (a revision that never becomes ready fails the run, and the old one keeps serving);
6. for the orchestrator and proposals-api, a smoke check without a user token.

A push to web's `main` tests, builds with the CSP's exact API hosts, deploys the site and checks it. From a laptop, the infra repo's `scripts/deploy-web.sh` does the same build and upload.

## 8. Check it

```bash
cd ../evals
../infra/scripts/spike-env.sh > .env
grep -E '^SQL_(SERVER|DATABASE)=' ../data/.env >> .env
uv run live/ask.py north.mgr "What was dairy margin in the North in October 2026?"   # 21.3%
uv run live/run_cases.py --stream                                                   # every live case
```

Each test user signs in through the browser once; later runs are silent. Then open the site, sign in as `north.mgr`, ask the same question, and open Approvals.

## Tear down

Deleting the resource group removes every Azure resource but the budget (subscription scope). The Foundry account is soft-deleted: purge it (`az cognitiveservices account purge`) before reusing its name. App registrations, test users and groups are tenant objects and stay until you delete them; GitHub secrets stay in the repos.
