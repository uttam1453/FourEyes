# FourEyes

**Maker–checker governance for autonomous AI agents in invoice-to-payment processing.**

FourEyes is a governed multi-agent finance-operations platform. A team of four
LLM agents reads an invoice, scores its fraud risk, decides whether it can be
paid and posts the payment to a double-entry ledger. Around the agents sit six
independent governance layers — Identity, Data, Model, Policy, Agent Runtime
and Operations — that limit what each agent may do, bring a human in for the
decisions that need one (the *four-eyes* principle), stop the system on demand
and keep a tamper-evident record of everything that happened.

The full build specification is in [`INSTRUCTIONS.md`](INSTRUCTIONS.md); the
twenty reproducible governance scenarios are in
[`docs/scenarios/`](docs/scenarios/README.md).

---

## Contents

1. [How it works](#1-how-it-works)
2. [Repository layout](#2-repository-layout)
3. [Requirements](#3-requirements)
4. [Setup, step by step](#4-setup-step-by-step)
5. [Using the system](#5-using-the-system)
6. [Day-to-day commands](#6-day-to-day-commands)
7. [Troubleshooting](#7-troubleshooting)
8. [Security notes](#8-security-notes)

---

## 1. How it works

### The agent workflow

```
invoice text / image
        │
        ▼
 ┌─────────────┐    ┌──────────────┐    ┌───────────┐    ┌───────────────────┐
 │ Extraction  │───▶│ Risk-Scoring │───▶│ Approval  │───▶│ Payment-Execution │──▶ settled
 └─────────────┘    └──────────────┘    └───────────┘    └───────────────────┘
   guardrail           vendor lookup      confidence gate    manifest + Cedar
   PII scan            > $5,000 → strong  critic (2nd LLM)   ledger dry-run
   registered prompt   model              Cedar + rate limit 20 s hold
   typed output        high risk → human  low conf → human   kill-switch re-check
                                                              idempotent commit
                              │                 │
                              └────────┬────────┘
                                       ▼
                               human_review (interrupt)
                               controller / CFO approves or rejects in the console
```

The four agents are nodes of one **LangGraph** graph inside `foureyes-backend`
(FastAPI). Every run is checkpointed in PostgreSQL, so a run can pause for a
human and resume later. **Instructor** forces every model answer into a
validated Pydantic schema.

### The six governance layers

| Layer | What it does | Built with |
|---|---|---|
| **Identity** | Human roles (`ap-clerk`, `controller`, `cfo-approver`); a cryptographic workload identity for the backend; secrets brokered at call time instead of stored | Keycloak, SPIFFE/SPIRE, Infisical |
| **Data** | Detects and redacts PII before anything is written to the audit trail; tags the invoice, vendor and payment tables as `RestrictedFinancial`; validates loaded data | Presidio, OpenMetadata, Great Expectations |
| **Model** | One gateway for all LLM calls with a separate key and daily budget per agent; prompts live in a registry and are promoted only after passing an evaluation gate | LiteLLM, MLflow Prompt Registry, DeepEval |
| **Policy** | A default-deny Policy Decision Point: who may approve what, up to which amount, how often, and who may write to the ledger | Cedar (via `cedarpy`), a temporal rate-limit rule |
| **Agent Runtime** | Capability manifests per agent, a guardrail model on untrusted text, a critic on a second provider, a confidence threshold, a ledger dry-run, a settlement hold, heartbeats, a sandboxed OCR worker | custom services, Docker, Linux Landlock |
| **Operations** | A graduated kill switch (agent / thread / tool / global) with automatic triggers; a SHA-256 hash-chained audit log on write-once storage; traces, metrics and dashboards | control-plane, audit-log, MinIO Object Lock, OpenTelemetry → Langfuse, Prometheus, Grafana |

### LLM routes

All model calls go through LiteLLM. Three named routes are configured in
[`infra/litellm/config.yaml`](infra/litellm/config.yaml):

| Route | Model | Used by |
|---|---|---|
| `foureyes-reasoning` | OpenAI `gpt-5.6-sol` | Approval agent; Risk-Scoring above USD 5,000 |
| `foureyes-routine` | Groq `openai/gpt-oss-120b` | Extraction, Risk-Scoring, the critic |
| `foureyes-guardrail` | Groq `openai/gpt-oss-safeguard-20b` | Guardrail check on every untrusted text |

There is **no offline or mocked model path**: both provider keys are required.

---

## 2. Repository layout

```
.
├── foureyes-backend/        FastAPI + LangGraph: the four agents and the human-review interrupt
│   └── app/
│       ├── graph.py             the workflow and its routing rules
│       ├── nodes/               extraction.py, risk_scoring.py, approval.py, payment_execution.py
│       ├── capability-manifests/  what each agent is allowed to do
│       └── *.py                 clients for the policy service, ledger, control plane, LiteLLM, SPIRE
├── foureyes-console/        Next.js web console (submit, approvals, audit log, ledger, kill switch, policies)
├── foureyes-ledger/         double-entry ledger with dry-run, vendors and payment history
├── foureyes-control-plane/  kill switch, heartbeats, automatic watchdog
├── foureyes-audit-log/      hash-chained audit log (MinIO Object Lock + PostgreSQL mirror) and tamper watchdog
├── foureyes-sandbox-runner/ starts one locked-down OCR container per uploaded image
├── foureyes-sandbox-ocr/    the OCR container image (Tesseract + Landlock)
├── foureyes-data-loader/    loads SROIE, CORD and USAspending data with Great Expectations checks
├── policies/                Cedar policies 01–05, the Cedar schema and the temporal rule
├── infra/
│   ├── compose/             one docker-compose file per layer (base, identity, data, model, app, observability)
│   ├── scripts/             bootstrap and provisioning scripts (all plain #!/bin/sh or Python 3)
│   ├── policy-service/      the Policy Decision Point (Cedar + temporal + kill-switch check)
│   ├── litellm/  mlflow/  deepeval/  keycloak/  spire/  minio-init/  postgres-init/  prometheus/  grafana/
├── docs/
│   ├── scenarios/           20 reproducible governance scenarios with expected and observed output
│   ├── sample-invoices/     generator for test invoices
│   └── testing-your-own-invoice.md
├── INSTRUCTIONS.md          the full specification this build satisfies
├── CREDENTIALS.md           URLs and demo logins for every browser-facing UI (local use only)
├── SECRETS GEN GUIDE.md     how the local secrets in .env.example were generated
├── FourEyes.excalidraw      architecture diagram with screenshots
└── .env.example             template for .env — copy it, add two API keys, never commit .env
```

---

## 3. Requirements

### Hardware

| Resource | Minimum | Notes |
|---|---|---|
| RAM for Docker | **20 GB** | Steady state is about 9–10 GB; headroom is needed for image builds and the OpenMetadata JVM start-up |
| Disk | **25 GB free** | Container images alone |
| CPU | 6 cores (8 recommended) | |

On Windows, raise the WSL2 limits in `%UserProfile%\.wslconfig`, then run
`wsl --shutdown` and restart Docker Desktop:

```ini
[wsl2]
memory=20GB
processors=8
```

### Software

| Tool | Version | Purpose |
|---|---|---|
| Docker Desktop (or Docker Engine + Compose v2) | recent stable; WSL2 backend on Windows | runs every service |
| A POSIX shell (`sh`) | Git Bash works on Windows | the scripts in `infra/scripts/` |
| Python 3 | 3.10 or newer | four host-side scripts (see below) |
| `curl` | any | health checks |

Host-side Python packages (only for the scripts you run on your machine, not
for the services — those build their own images):

```sh
pip install requests cedarpy
```

`provision-infisical-identities.py` and `provision-litellm-keys.py` use only
the standard library; `register-openmetadata-catalog.py` needs `requests`;
`validate-cedar-policies.py` needs `cedarpy`.

### Accounts and keys

| Provider | Where to create the key | Used for |
|---|---|---|
| OpenAI | https://platform.openai.com/api-keys | `foureyes-reasoning` route |
| Groq | https://console.groq.com/keys | `foureyes-routine` and `foureyes-guardrail` routes |

Standard chat-completions access is enough; the demo workload is small, and
LiteLLM caps each agent at USD 2–5 per day.

### Network

The first start downloads container images, Python packages, the Tesseract
OCR data and the public datasets (SROIE and CORD from Hugging Face, awards from
the USAspending API). Allow a few GB of download.

---

## 4. Setup, step by step

Run every command from the repository root. The order matters: each step
produces values the next one needs.

### Step 0 — one-time preparation

```sh
cp .env.example .env
```

`.env.example` already contains a generated random value for every
**local-only** secret (database passwords, MinIO root, Keycloak admin, and so
on). Open `.env` and change only these two lines:

```
OPENAI_API_KEY=sk-...
GROQ_API_KEY=gsk_...
```

`.env` is git-ignored. Never commit it, and never paste its contents anywhere.

```sh
docker network create foureyes-net
sh infra/scripts/render-keycloak-realm.sh
```

The first command creates the private Docker network all containers share. The
second writes `infra/keycloak/realm-foureyes.json` from the template, with the
client secrets from your `.env` filled in, so Keycloak starts fully configured.

### Step 1 — foundations

```sh
sh infra/scripts/compose.sh up -d postgres minio
```

Starts the shared PostgreSQL instance (one database and one user per service)
and MinIO object storage.

### Step 2 — Identity layer

```sh
sh infra/scripts/compose.sh up -d keycloak spire-server infisical-redis infisical
sh infra/scripts/register-spire-entries.sh
sh infra/scripts/setup-spire.sh
sh infra/scripts/compose.sh up -d --force-recreate spire-agent
sh infra/scripts/bootstrap-infisical.sh
python3 infra/scripts/provision-infisical-identities.py
```

What each line does:

| Command | Effect |
|---|---|
| `compose.sh up -d keycloak …` | Starts Keycloak (human login, realm `foureyes`), the SPIRE server (workload identity) and Infisical (secrets vault) |
| `register-spire-entries.sh` | Registers the backend and the four agents with SPIRE under the trust domain `foureyes.local` |
| `setup-spire.sh` | Generates the one-time join token for the SPIRE agent and writes it to `.env` |
| `compose.sh up -d --force-recreate spire-agent` | Restarts the SPIRE agent so it picks up the token and attests |
| `bootstrap-infisical.sh` | Creates the Infisical admin account |
| `provision-infisical-identities.py` | Creates one machine identity per service and stores the ledger credential in the vault |

**The last script prints three values. Copy them into `.env` now:**
`INFISICAL_PROJECT_ID`, `PAYMENT_EXECUTION_CLIENT_ID`,
`PAYMENT_EXECUTION_CLIENT_SECRET`.

### Step 3 — Data layer

```sh
sh infra/scripts/compose.sh up -d om-postgres om-elasticsearch om-migrate om-server om-ingestion presidio-analyzer presidio-anonymizer
sh infra/scripts/compose.sh up data-loader
python3 infra/scripts/register-openmetadata-catalog.py
```

* Starts OpenMetadata (data catalogue) and the two Presidio services (PII
  detection and anonymisation). OpenMetadata takes a few minutes to become
  healthy.
* `data-loader` downloads 500 receipts from SROIE and CORD and up to 300
  FY2024 contract awards from USAspending, validates them with a Great
  Expectations checkpoint and loads them into PostgreSQL. It runs in the
  foreground and exits when done.
* The catalogue script tags the invoice, vendor and payment tables as
  `RestrictedFinancial`.

### Step 4 — Model layer

```sh
sh infra/scripts/compose.sh up -d litellm-redis litellm mlflow
curl http://localhost:4000/health/liveliness
python3 infra/scripts/provision-litellm-keys.py
sh infra/scripts/compose.sh up deepeval-gate
```

* LiteLLM runs its database migration on first start. If `curl` returns an
  empty response, wait a few seconds and repeat it until you get a reply.
* `provision-litellm-keys.py` creates one virtual key per agent, each limited
  to its allowed routes and to a 24-hour budget. **It prints values to copy
  into `.env`.**
* `deepeval-gate` scores two versions of the extraction prompt against 60
  held-out SROIE records. Version 1 passes the 0.6 threshold and is promoted
  to the `production` alias in MLflow; version 2 scores 0.000 and is blocked.
  This takes a few minutes and makes real LLM calls.

### Step 5 — Policy layer

```sh
python3 infra/scripts/validate-cedar-policies.py
```

Parses the Cedar policies against the schema and runs the authorisation test
cases. Expected output ends with `ACCEPTED` and no errors.

### Step 6 — Application and Operations layers

```sh
sh infra/scripts/compose.sh up -d
docker build -t foureyes-sandbox-ocr:latest foureyes-sandbox-ocr/
```

* The first command starts everything that is not yet running: the backend,
  ledger, policy service, control plane, audit log, sandbox runner, console,
  Langfuse, Prometheus and Grafana.
* The second builds the locked-down OCR image. The sandbox runner starts a
  fresh container from this image for each uploaded invoice image. Without
  it, pasting invoice text works but uploading an image does not.

### Step 7 — confirm everything is up

```sh
sh infra/scripts/compose.sh ps --format "table {{.Name}}\t{{.Status}}"
curl http://localhost:8000/health
```

Every container should show `Up` (and `healthy` where a health check is
defined). Then open http://localhost:3000 and sign in with one of the demo
users listed in [`CREDENTIALS.md`](CREDENTIALS.md).

---

## 5. Using the system

### Browser-facing pages

All ports are bound to `127.0.0.1` only. Logins are in `CREDENTIALS.md`.

| Page | URL |
|---|---|
| **FourEyes console** — submit invoices, approval queue, audit log, ledger, kill switch, policies | http://localhost:3000 |
| Keycloak admin — realm, roles, demo users | http://localhost:8180/admin |
| Infisical — secrets vault | http://localhost:8443 |
| MinIO console — audit-log bucket | http://localhost:9001 |
| LiteLLM UI — spend and keys per agent | http://localhost:4000/ui |
| MLflow — prompt versions and gate results | http://localhost:5500 |
| OpenMetadata — sensitivity tags | http://localhost:8585 |
| Langfuse — traces and cost per LLM call | http://localhost:3010 |
| Prometheus — raw metrics | http://localhost:9095 |
| Grafana — governance dashboard and alerts | http://localhost:3020 |

### Demo roles

| Role | Can do |
|---|---|
| `ap-clerk` | Submit invoices and watch runs |
| `controller` | Everything above, plus approve or reject runs waiting for human review |
| `cfo-approver` | Same as controller, at the highest approval-authority tier |

### Running an invoice

1. Sign in to the console and open **Submit Invoice**.
2. Paste invoice text, or upload an image (the image goes through the
   sandboxed OCR worker first; see
   [`docs/testing-your-own-invoice.md`](docs/testing-your-own-invoice.md)).
3. Watch the pipeline view. A low-risk invoice from a known vendor settles on
   its own after the 20-second settlement hold. A high-risk, low-confidence
   or policy-denied invoice appears in the **Approvals** queue.
4. As `controller` or `cfo-approver`, approve or reject it from the queue.
5. Check the **Audit log** page and press **Verify** to re-compute the hash
   chain, the **Ledger** page for balances, and Langfuse or the LiteLLM UI
   for the cost of the run.

### Reproducing the governance scenarios

Each file in `docs/scenarios/` describes one control, the exact commands to
trigger it and the output observed in this build — for example a poisoned
invoice stopped by the guardrail (08), a 429 from the gateway when an agent's
budget is spent (12), a kill switch tripped during the settlement hold (19) or
an edited audit entry caught by the watchdog (15). Start with
[`docs/scenarios/README.md`](docs/scenarios/README.md).

---

## 6. Day-to-day commands

`infra/scripts/compose.sh` is a thin wrapper that passes the six compose
files and the `.env` file to `docker compose`, so any compose sub-command works:

```sh
sh infra/scripts/compose.sh ps                          # status
sh infra/scripts/compose.sh logs -f foureyes-backend    # follow one service
sh infra/scripts/compose.sh restart foureyes-backend    # restart one service
sh infra/scripts/compose.sh up -d --build foureyes-backend   # rebuild after a code change
sh infra/scripts/compose.sh stop                        # stop, keep data
sh infra/scripts/compose.sh down                        # stop and remove containers, keep volumes
sh infra/scripts/compose.sh down -v                     # full reset: removes all data (re-run setup from Step 1)
```

Each compose file also works on its own, so a single layer can be started and
demonstrated independently, e.g.
`docker compose --env-file .env -f infra/compose/docker-compose.base.yml -f infra/compose/docker-compose.identity.yml up -d`.

After editing a Cedar policy, run `python3 infra/scripts/validate-cedar-policies.py`
and restart `policy-service`. Scenarios 06 and 07 show an accepted and a
rejected policy change.

---

## 7. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `curl http://localhost:4000/health/liveliness` returns nothing | LiteLLM is still migrating its database. Wait and retry. |
| `foureyes-backend` exits at start with an identity error | The SPIRE agent has not attested. Re-run `setup-spire.sh`, then `compose.sh up -d --force-recreate spire-agent`, then start the backend again. The backend refuses to start without an X.509 SVID by design. |
| Image upload fails, pasted text works | Build the OCR image: `docker build -t foureyes-sandbox-ocr:latest foureyes-sandbox-ocr/`. |
| OpenMetadata containers restart repeatedly | Not enough memory. Give Docker 20 GB. |
| A run ends as `failed` immediately after submission | The guardrail flagged the text as unsafe (see scenario 08), or an agent's LiteLLM key is missing from `.env` (re-run `provision-litellm-keys.py`). |
| HTTP 423 when submitting or resuming | The kill switch is tripped for that thread, agent or globally. Reset it from the console's Kill switch page. |
| HTTP 429 from the gateway | That agent's 24-hour budget is spent (scenario 12). Raise the budget in `provision-litellm-keys.py` or wait. |
| `provision-infisical-identities.py` fails | `bootstrap-infisical.sh` has not run, or Infisical is not yet healthy. Check `compose.sh ps`. |
| Ports already in use | Another service on the host uses 3000, 4000, 5500, 8000, 8180 or similar. Stop it or change the host port in the compose file. |

---

## 8. Security notes

* The values in `.env.example` and the logins in `CREDENTIALS.md` are for a
  **local demonstration stack only**. They bind to `127.0.0.1` and must never
  be used on a shared or internet-facing host. Regenerate them (see
  `SECRETS GEN GUIDE.md`) before any other use.
* Never commit `.env`, `infra/keycloak/realm-foureyes.json` or the
  `.infisical-*.json` files; `.gitignore` already excludes them.
* The sandbox runner needs access to the Docker socket to start OCR
  containers. On a shared machine, run it behind a socket proxy or a rootless
  Docker daemon.
* Known limitations of this reference build — such as the unauthenticated
  backend resume endpoint, in-memory kill-switch state and agent steps not
  yet written to the audit chain — are documented in the dissertation outline
  that accompanies this repository and are the subject of the hardening work
  planned on top of it.
