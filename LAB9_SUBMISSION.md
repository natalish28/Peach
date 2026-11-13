# Lab 9 — The same system on another cloud: Peach on Google Cloud

The core of Peach (the static frontend, the FastAPI API and PostgreSQL) runs on Google Cloud. It
is described in [`gcp/`](gcp/), with its own HCP Terraform workspace `peach-gcp`. Sign-in
(Cognito), the weekly report and the agenda parser stay on AWS. Service choices:
[ADR 0008](docs/adr/0008-google-cloud.md). How to deploy and stop it: README section 15.

> Fill in before submitting: every **TODO** below.

## 1. Commit and ADR

- `gcp/` Terraform, bootstrap, scripts, Makefile, README, ADR: **TODO commit / PR link**
- ADR: [`docs/adr/0008-google-cloud.md`](docs/adr/0008-google-cloud.md)

## 2. Peach running on Google Cloud

- Frontend: **TODO** `https://peach-natalish-2026-web.web.app`
- API (Cloud Run): **TODO** `https://peach-api-….us-central1.run.app`
- Call that reads from the database: sign in, open `/items`. That page calls `GET /api/v1/items`
  through the Firebase rewrite to Cloud Run, which reads Cloud SQL. `GET /api/v1/health/ready`
  (with the same bearer token: every `/api/v1` route requires one) runs `SELECT 1` against Cloud
  SQL as well; the public `GET /health` only shows that the container is up.
- Data: **migrations run against the empty database** (the container entrypoint runs
  `alembic upgrade head` on start). There was no `pg_dump` from Aurora, because Aurora is in a
  private subnet with IAM authentication. Users who sign in with the same Cognito account get a
  fresh row in `users`.

### Part 0 — the project, without keys

| | |
| --- | --- |
| Project | `peach-natalish-2026`, budget alert $5/month at 50/90/100 % (alerts only) |
| Service accounts | `hcp-terraform` (Terraform), `peach-api` (Cloud Run runs as it), optional `github-deploy` (CI). No default compute account, no Owner/Editor |
| Roles of `hcp-terraform` | Cloud Run Admin, Cloud SQL Admin, Artifact Registry Administrator, Secret Manager Admin, Service Usage Admin, Firebase Admin; Service Account User **on `peach-api` only** |
| Roles of `peach-api` | Cloud SQL Client (project); Secret Manager Secret Accessor **on the one secret** |
| HCP Terraform → GCP | Workload identity pool `peach-ci`, OIDC provider for `app.terraform.io`, condition `terraform_organization_id == "org-vbn4yqGz8LNpCgpr" && terraform_workspace_name == "peach-gcp"` |
| GitHub → GCP (stretch) | Provider for `token.actions.githubusercontent.com`, condition on the numeric `repository_id` and `repository_owner_id` |
| Keys | none created; the laptop uses `gcloud auth application-default login` |

## 3. What it costs

On-demand list prices in USD, AWS us-east-1 and Google Cloud us-central1, 730 h a month, no tax.
Google Cloud has Cloud SQL (ADR 0008), not Firestore.

### The minimal setup, nobody using it

| Piece | AWS (Lab 4) | Google Cloud (this lab) |
| --- | --- | --- |
| Frontend + CDN + HTTPS | CloudFront Free plan → $0 | Firebase Hosting, free quota → $0 |
| API | Lambda, idle → $0 | Cloud Run, min 0 instances → $0 |
| Database compute | Aurora paused → $0 | Cloud SQL db-f1-micro, $0.0105/h × 730 → **$7.67** (stopped: $0) |
| Database storage | ~1 GB × $0.10 → $0.10 | 10 GB SSD × $0.17 → $1.70 (also while stopped) |
| Registry, secrets, logs | a few cents | Artifact Registry ≤ 0.5 GB, 1 secret version, logs: free |
| **Total** | **≈ $0.30** | **≈ $9.40** running, **≈ $1.70** stopped |

### Four traffic profiles

| Profile | Database awake | AWS | GCP, Cloud SQL always on | GCP, Cloud SQL started only when used |
| --- | --- | --- | --- | --- |
| Nobody | 0 h | **$0.30** | $9.40 | $1.70 |
| Class demos, 10 × 2 h | 20 h (+ pause/start tails) | **$1.56** (21 h × $0.06) | $9.40 | $1.93 (22 h × $0.0105 + $1.70) |
| Office hours, 8 h × 22 days | 176 h | $10.86 (176 h × $0.06 + $0.30) | $9.40 | **$3.55** (176 h × $0.0105 + $1.70) |
| Busy around the clock | 730 h | $44.43 (Aurora $43.80 + Lambda $0.33 + $0.30) | **$11.64** (Cloud SQL $9.40 + Cloud Run $2.24) | not applicable |

Assumptions:

- **Aurora** is at its awake minimum of 0.5 ACU × $0.12 = $0.06/h while awake, and pauses about
  5 minutes after the last connection. If load pushes it to the 1 ACU maximum, double the AWS
  database line.
- **Cloud SQL** takes a few minutes to start, so it is counted ~10 minutes early for each demo.
  Starting and stopping it is a person or a scheduler running `make gcp-db-start` /
  `gcp-db-stop`. Cloud SQL storage cannot go below 10 GB.
- **Busy** means about 1 request a second: 2.63 M requests a month at ~100 ms each, 512 MiB,
  1 vCPU.
  - Lambda: (2.63 M − 1 M free) × $0.20/M = $0.33. 131,400 GB-s is within the 400,000 free.
  - Cloud Run (request-based): 262,800 vCPU-s − 180,000 free = 82,800 × $0.000024 = $1.99.
    131,400 GiB-s is within the 360,000 free. (2.63 M − 2 M) requests × $0.40/M = $0.25.
    Total $2.24.
  - db-f1-micro handles 1 request a second; heavier traffic needs db-g1-small
    ($0.035/h → $25.55 + $1.70).
- **Firebase**: the project has billing linked (Cloud SQL and Cloud Run need it), so Firebase is
  on pay-as-you-go with the same free quota: 10 GB stored, 360 MB a day transferred. 2.6 M API
  responses of ~1 KB is ~87 MB a day through the rewrite, so it stays within the quota.
- Every other line (Cognito, CloudFront, Secret Manager, Artifact Registry, logs) is within the free
  tier in all four profiles.

**Which cloud is cheaper, and which line decides it.** The database line decides every profile.
The API and frontend cost $0 to about $2 on both clouds.

- *Nobody, class demos*: **AWS**, because Aurora pauses and costs nothing. Even a stopped Cloud SQL
  instance still bills its 10 GB minimum of storage ($1.70 against $0.10). At 20 h of demos AWS
  wins by cents; the break-even against a started-when-used Cloud SQL is about 28 awake hours a
  month.
- *Office hours*: **GCP**. Aurora awake for 176 h ($10.56) already costs more than Cloud SQL
  running the whole month ($7.67), so even the always-on GCP setup is cheaper. A stop/start
  schedule brings it to $3.55. The break-even with always-on Cloud SQL is ~150 Aurora hours a
  month.
- *Busy*: **GCP, by about 4×.** An Aurora ACU-hour ($0.12) costs about 11× a db-f1-micro hour
  ($0.0105), even though the micro instance is far smaller. A paused database is free; one that
  stays awake is expensive.

**The equivalent trap on the GCP side.** Aurora's trap was something keeping it awake. Cloud SQL
needs nothing to keep it awake: it runs until a person stops it. The trap is forgetting
`make gcp-db-stop` after a demo, which costs $7.67 a month and appears on the bill as "nobody used
it, it still cost $9". Related traps:

- an apply that resets `activation_policy` to `ALWAYS` (ignored in `gcp/database.tf` for this
  reason);
- `disk_autoresize`, which grows the disk and never shrinks it (turned off);
- Cloud Run with `min_instance_count ≥ 1` or instance-based billing (`cpu_idle = false`), which
  turns an idle API into a bill of tens of dollars a month (min 0 and `cpu_idle = true` here).

On Firestore the trap would be the read count. TanStack Query refetches on window focus, and a
list page that reads every document on each refetch uses up 50,000 free reads a day quickly.

## 4. What else Google Cloud is good at

Screenshots: `lab9/screenshots/` — **TODO** add the three files.

| Demo | What was done | Result |
| --- | --- | --- |
| BigQuery | [`lab9/bigquery/01_monthly_orders.sql`](lab9/bigquery/01_monthly_orders.sql) over `bigquery-public-data.thelook_ecommerce` (orders ⨝ order_items), in the sandbox | **TODO** bytes processed: … MB (of the 1 TiB free a month) |
| Looker Studio | Line chart of `revenue_usd` and `cancelled_or_returned_pct` by `month`, data source = the saved query result | **TODO** screenshot |
| Document AI / Vision OCR | **TODO**: Enterprise OCR processor in the console on one PDF, or Vision `TEXT_DETECTION` on a photo of a handwritten page | **TODO** screenshot; within the free 1,000 pages/units |
| Vertex AI Studio (optional) | The Lab 6 agenda prompt (`SYSTEM` in `backend/app/ai/agenda.py`) with Gemini on the same pasted text | **TODO** answer and token count vs Nova Lite on Bedrock |

**When is Document AI the better tool than a general model, and when is it not?** Document AI fits
documents with a known kind and layout: receipts, invoices, forms, IDs, scanned pages. It returns
text with positions and confidence for each field. The price is fixed per page ($1.50 per 1,000 for
OCR), and the output has the same shape every time. Nothing in the document can redirect it the way
a prompt injection redirects an LLM. It is the better choice at volume and when someone has to check
the result field by field. A general model is better when the input has no fixed format and has to
be understood, not just read. Peach's agendas are free text pasted from chats and e-mails. The model
has to find the meeting, turn "next Monday after the stand-up" into a date, and handle Ukrainian
and English mixed together. A form parser cannot do that, so Lab 6 used an LLM. When the input is
a photo, as in our OCR demo, the two combine: OCR turns the page into text, and the LLM structures
that text.

**Lab 8 on Google Cloud.**

| Lab 8 on AWS | On Google Cloud |
| --- | --- |
| Raw JSON events in S3 | Cloud Storage |
| Glue crawler + Data Catalog, Athena tables, partitions | BigQuery: load the files or define an external table; schema and partitioning belong to the table, with no crawler |
| Glue job (dedup, JSON → Parquet) | Dataflow (the Cloud Storage Text to BigQuery template), or simply `CREATE TABLE … AS SELECT` with the dedup in BigQuery SQL |
| Athena SQL (dedup view, turnover, failure rate, peak hours, late events) | The same SQL in BigQuery, nearly unchanged |
| Streaming: Redpanda / Kinesis → consumer | Pub/Sub → Dataflow streaming, or a Pub/Sub subscription that writes straight into BigQuery |
| QuickSight | Looker Studio (free) |

What we would no longer manage:

- the crawler and the catalog;
- the Parquet conversion and file layout (BigQuery chooses its own storage format);
- the Athena results bucket and workgroup;
- Glue DPUs (Dataflow scales its own workers);
- the copy step that needed `--copy-props none`.

The 3 M events of Lab 8 are a few hundred MB, so every query fits easily in the free 1 TiB a
month.

## Clean up

- [ ] `make gcp-db-stop` after each session. At the end of the course: **TODO** run
  `terraform destroy` in the `peach-gcp` workspace (Settings → Destruction and Deletion).
- [ ] Delete the BigQuery tables or views and any Dataflow output. Delete the Document AI processor.
- [ ] Check Billing → Reports a day later.
