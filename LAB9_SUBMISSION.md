# Lab 9 — The same system on another cloud: Peach on Google Cloud

> **I took the route without a Google Cloud account:** no billing account was opened, so the
> `gcp/` configuration is validated (not applied), the Cloud Run image runs locally, and the Part 4
> demos are done in the Colab notebook and a public Looker Studio dashboard.

The core of Peach (the static frontend, the FastAPI API and PostgreSQL) runs on Google Cloud. It is
designed to run on Google Cloud and described in [`gcp/`](gcp/), with its own HCP Terraform workspace `peach-gcp`. Sign-in
(Cognito), the weekly report and the agenda parser stay on AWS. Service choices:
[ADR 0008](docs/adr/0008-google-cloud.md). How to deploy and stop it: README section 15.

## 1. Commit and ADR

- `gcp/` Terraform, bootstrap, deploy scripts, Makefile, README, ADR: commit
  [`e2f7ab4`](https://github.com/natalish28/Peach/commit/e2f7ab41ffd8755d740788f4e41e76513adc7d8c)
- The route without an account (`make gcp-local`, validate output, screenshot): commit
  [`49cdc4d`](https://github.com/natalish28/Peach/commit/49cdc4d0eacaf0ae1467ff09591a326d4560fc2e)
- Branch: [`lab9`](https://github.com/natalish28/Peach/tree/lab9)
- ADR: [`docs/adr/0008-google-cloud.md`](docs/adr/0008-google-cloud.md)

### `terraform init` and `terraform validate` in `gcp/`

Both run without Google credentials. `-backend=false` skips the HCP Terraform `cloud` block, which
would need a token and an existing workspace. `terraform plan` needs a project, so it is skipped.
Full output: [`lab9/terraform-validate.txt`](lab9/terraform-validate.txt).

```text
$ cd gcp && terraform init -backend=false
Initializing provider plugins...
- Reusing version 7.46.2 of hashicorp/google-beta from the dependency lock file
- Reusing version 3.9.1 of hashicorp/random from the dependency lock file
- Reusing version 7.46.2 of hashicorp/google from the dependency lock file
Terraform has been successfully initialized!

$ terraform validate
Success! The configuration is valid.

$ cd bootstrap && terraform init -backend=false && terraform validate
Terraform has been successfully initialized!
Success! The configuration is valid.
```

## 2. Peach, ready for Cloud Run, running locally

`make gcp-local` ([`scripts/run-cloudrun-local.sh`](scripts/run-cloudrun-local.sh)) runs the core
the way Cloud Run would run it:

- The **backend image is the Dockerfile `runtime` target**, the same image
  `make deploy-gcp-backend` pushes to Artifact Registry. It has no Mangum and no Lambda adapter
  (those exist only in the `lambda` target). It is started as Cloud Run starts it:
  `docker run -e PORT=8080 -p 8080:8080 -e K_SERVICE=peach-api …`. The entrypoint runs
  `alembic upgrade head` and then uvicorn on `$PORT`.
- **PostgreSQL 17** in a container next to it stands in for Cloud SQL (`postgres:17-alpine`, the
  same major version as `gcp/database.tf`).
- The **frontend** is built with the API URL baked in and served on `:3000`.
- **Sign-in** stays on AWS Cognito, as in the GCP design; `http://localhost:3000` is an allowed
  callback.

On my laptop the host port 8080 was taken by Lab 8's Redpanda Console, so I ran it with
`API_HOST_PORT=8081 make gcp-local`. The container still listens on `PORT=8080`; only the host
side of `-p` differs.

```text
[entrypoint] applying migrations...
INFO  [alembic.runtime.migration] Running upgrade  -> 0001, create items table
…
INFO  [alembic.runtime.migration] Running upgrade 0003 -> 0004, add agendas table
[entrypoint] starting uvicorn...
INFO:     Uvicorn running on http://0.0.0.0:8080 (Press CTRL+C to quit)
```

- Screenshot: [`lab9/screenshots/local-cloudrun.png`](lab9/screenshots/local-cloudrun.png). The
  board after sign-in (Google through Cognito) with two tasks, loaded by `GET /api/v1/items`, which
  reads PostgreSQL. The tasks stay after a reload. The API log and the table behind it:

```text
"POST /api/v1/items HTTP/1.1" 201 Created
"GET /api/v1/items?limit=100 HTTP/1.1" 200 OK

peach=# select name, status from items;
 name | status
------+--------
 дз   | todo
 lab  | todo
```
- Data: **migrations run against the empty database** (the container entrypoint, as it would on
  Cloud Run). On Google Cloud there would be no `pg_dump` from Aurora either, because Aurora is in a
  private subnet with IAM authentication.

### Part 0 — the project, without keys (as designed in `gcp/bootstrap/`)

| | |
| --- | --- |
| Project | `peach-natalish-2026` (designed, not created), budget alert $5/month at 50/90/100 % (alerts only) |
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

Done without billing, in my copy of the course notebook *Lab 9. Part 4 without a Google Cloud
bill* (on the free T4 GPU runtime; no account, card or API key), and in Looker Studio.

- **Notebook** (Anyone with the link can view, outputs saved; Runtime → Run all on a fresh
  runtime finishes without errors): 
  <https://colab.research.google.com/drive/1H8P5eb2qH-WC_PkeHolUr6UCx_Mnzc1z3>
- **Looker Studio** (public, over Our World in Data `owid-co2-data.csv`: a line chart, a geo
  chart, a top-10 bar chart and a country drop-down):
  <https://datastudio.google.com/reporting/6600d200-212c-4707-82d5-478b53bb8690>. The line chart
  uses a calculated field `year_date = PARSE_DATE("%Y", CAST(year AS TEXT))`, because a time
  series needs a date and the CSV has the year as a number.
  Data source: [`lab9/looker/owid-co2-countries.csv`](lab9/looker/owid-co2-countries.csv), the
  OWID file reduced to countries only (rows with an ISO code, without the `OWID_*` aggregates such
  as World or Asia, which would otherwise fill the top 10), from 1950, and 9 columns: 16,948 rows,
  0.9 MB.

| Demo | Instead of | What was done | Result |
| --- | --- | --- | --- |
| SQL over a public dataset | BigQuery | DuckDB in Colab | output saved in the notebook |
| OCR | Vision API | Tesseract and EasyOCR on the notebook's image | output saved in the notebook |
| Document → Markdown | Document AI | Qwen3-VL 2B through Ollama on the scanned invoice | output saved in the notebook |
| Invoice → JSON | — | My prompt ([`lab9/colab/my_prompt.txt`](lab9/colab/my_prompt.txt)), with the same model and the `Invoice` JSON schema, on the Markdown (A) and on the image (B), checked against the right answer | **A: 8 of 9, B: 8 of 9**; both miss only `seller` |
| Dashboard | Looker Studio over BigQuery | Looker Studio (now Data Studio) over the OWID CSV | link above |

How the prompt got there. The first version asked for the seller and buyer as a name only, and
scored 7 of 9 on both inputs: the right answer keeps the name, street and city on one line. With
that spelled out it scored 8 of 9 on both. The one field left is a misread street name, not a
format problem: both answers say `2a Kozelnyska St` for `2a Kozelnytska St`. Writing the street
name into the prompt would only copy the answer into it, so the prompt stops there.

```text
A, Markdown: 8 of 9 fields match; wrong: seller
   seller: expected 'Spry Analytics LLC, 2a Kozelnytska St, Lviv', got 'Spry Analytics LLC, 2a Kozelnyska St, Lviv'
B, image: 8 of 9 fields match; wrong: seller
   seller: expected 'Spry Analytics LLC, 2a Kozelnytska St, Lviv', got 'Spry Analytics LLC, 2a Kozelnyska St, Lviv'
```

**Three sentences.** The Markdown and the image scored the same (8 of 9) and failed on the same
letter, because the Markdown was itself produced by the same Qwen3-VL model reading the same
image: a misreading in that step is passed on, so the Markdown gives the model cleaner text but no
information the image does not already have. Run all took about 3 minutes on the free T4 GPU, most of it installing
Ollama and pulling the model; the prompt cell itself took 3 s on the Markdown and 4 s on the image
(the course measured about 3.5 minutes for it on CPU). I would pay for
Document AI instead once the documents arrive in volume and someone relies on each field: at
$1.50 per 1,000 pages for OCR it costs less than the GPU hours a self-hosted model needs, it
returns every field with a position and a confidence in the same shape every time, and it has no
model, Ollama server or prompt to keep running and re-test.

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

Nothing was created on Google Cloud, so there is nothing to stop or bill. Locally,
`make gcp-local-down` removes the containers, network and database volume that `make gcp-local`
started. If the same setup is later applied for real: `make gcp-db-stop` after each session,
`terraform destroy` in the `peach-gcp` workspace at the end, and check Billing → Reports a day
later.
