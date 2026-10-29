# Lab 5 Submission: A weekly report, built by events

## 1. Commit Link
* **GitHub Commit**: [https://github.com/natalish28/Peach/commit/526ac50](https://github.com/natalish28/Peach/commit/526ac50)
* **Included components**:
  * Report logic: `backend/app/reports/weekly.py`
  * Builder Lambda handler: `backend/app/reports/lambda_handler.py`
  * Mailer Lambda handler: `backend/app/reports/mailer.py`
  * CloudFormation infrastructure template: `infra/reports.yaml`
  * Deployment automation and targets: `scripts/deploy-reports.sh`, `Makefile`

---

## 2. Screenshot of the SES Delivered Email
*(Attach the screenshot of the email received from `shymanska.pn@ucu.edu.ua` via Amazon SES with subject `Weekly Report: 2026-W40` and attached `2026-W40.csv`)*

---

## 3. Output of S3 Reports Bucket Listing
Command:
```bash
aws s3 ls s3://peach-reports-757159686525/reports/ --recursive
```

Output:
```text
2026-10-15 11:57:34        559 reports/2026-W40.csv
2026-10-15 11:55:16        606 reports/2026-W41.csv
```

---

## 4. CloudWatch Log Lines for Each Trigger

### 1. Trigger: Schedule (`trigger=schedule`)
* Function: `peach-report-builder`
```text
2026-10-15 08:57:33,245 [INFO] report-builder triggered: trigger=schedule week=2026-W40 event_source=direct
```

### 2. Trigger: SQS Message (`trigger=sqs`)
* Function: `peach-report-builder`
```text
2026-10-15 08:55:14,524 [INFO] report-builder triggered: trigger=sqs week=2026-W41 event_source=sqs
```

### 3. Trigger: S3 Object Upload (`trigger=s3`)
* Function: `peach-report-mailer`
```text
2026-10-15 08:56:17,083 [INFO] report-mailer triggered: trigger=s3 bucket=peach-reports-757159686525 key=reports/2026-W41.csv
```

---

## 5. Answers to Part 3, Step 7 Questions

### Question 0
> **Send the same week twice. How many emails do you get? Write down why.**

**Answer:**
We receive **two separate emails**. 
Amazon S3 publishes a new `ObjectCreated:Put` event every time an object is uploaded or overwritten in the bucket. The Mailer Lambda executes statelessly on every incoming notification and does not track whether an email for this report key has previously been dispatched.

---

### Question 1
> **The mailer got the same ObjectCreated event twice, and the person got two identical emails. Where would you store "this report was already sent", and what would the key be?**

**Answer:**
* **Where to store:** In **Amazon DynamoDB** (leveraging conditional expressions like `attribute_not_exists(report_id)` for atomic idempotency, along with TTL to auto-expire records after 90 days) or alternatively in S3 Object Metadata/Tags (`status=sent`). DynamoDB is the preferred choice for fast, atomic lock-checking.
* **Key definition:** The primary key could be `<bucket_name>#<object_key>` (e.g. `peach-reports-757159686525#reports/2026-W41.csv`) or include the S3 version/ETag (`<object_key>#<eTag>`).

---

### Question 2
> **The builder in the VPC could not reach SES. List three ways to fix that, with their monthly cost: a NAT gateway, a VPC interface endpoint for SES, and the split you built. Which would you choose with ten more emails a week? With a million?**

**Answer:**
1. **AWS NAT Gateway:**
   * **Monthly Cost:** ~$32.85/month per Availability Zone ($0.045/hour) + $0.045/GB data processing fees.
2. **VPC Interface Endpoint (AWS PrivateLink) for SES:**
   * **Monthly Cost:** ~$7.30/month per AZ ($0.01/hour) + $0.01/GB data processing fees.
3. **Architectural Split (Split Lambda Pattern — our implementation):**
   * Builder writes to S3 via a free Gateway VPC Endpoint ($0/month), and Mailer runs outside the VPC with direct internet access to SES.
   * **Monthly Cost:** **$0/month** fixed baseline (only standard per-invocation Lambda execution and $0.10 per 1,000 SES emails).

* **Choice for 10 more emails a week:**
  * **Architectural Split (Split Lambda)**. Paying $7–$33/month in fixed VPC networking fees for ~40 emails/month is economically unjustifiable when the serverless split costs fractions of a cent.
* **Choice for 1,000,000 emails a week:**
  * **VPC Interface Endpoint for SES** (or dedicated background worker cluster). At enterprise scale, paying ~$7–$14/month for high-throughput, private, low-latency AWS backbone connectivity with a predictable SLA is negligible and provides superior reliability.

---

### Question 3
> **You could send a presigned S3 link instead of an attachment. A presigned URL signed with a Lambda role's temporary credentials stops working when those credentials expire, often within hours. How would you send a link that works for a week?**

**Answer:**
Temporary security credentials from AWS STS (which Lambda execution roles use) expire within a maximum of 12 hours (typically 1 hour), causing any S3 presigned URL signed by them to stop working upon credential expiration regardless of the `ExpiresIn` parameter.

To provide a link valid for 7 days:
1. **Amazon CloudFront Signed URLs (Recommended):** Distribute report files through a CloudFront distribution using CloudFront Signed URLs with an RSA key pair / Key Group. CloudFront signatures are independent of IAM STS token expiration and can be set to any arbitrary expiration timestamp (e.g., exactly 7 days).
2. **Dedicated IAM User static credentials (Alternative):** Generate the presigned S3 URL using the permanent access keys (`AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`) of a dedicated, restricted IAM service account. IAM User signatures support the full SigV4 expiration limit of up to 7 days (604,800 seconds).

