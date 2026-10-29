# Lab 7 — The cloud as code: from CloudFormation to Terraform

Cognito (Lab 4), the weekly reports (Lab 5) and the agenda parser (Lab 6) moved from three
CloudFormation stacks to one Terraform root module in `infra/`, with the state and the runs in
HCP Terraform (`miunafw/peach-dev`). Nothing in AWS was deleted or re-created: the user pool kept
its 3 accounts and the reports bucket its reports.

## 1. Commit

- Terraform code, imports, Makefile, README, ADR: https://github.com/natalish28/Peach/commit/ee61ca1
- CloudFormation templates removed: https://github.com/natalish28/Peach/commit/095c16a
- Import blocks removed after the apply: https://github.com/natalish28/Peach/commit/b1e7ce7
- ADR: [`docs/adr/0007-terraform.md`](docs/adr/0007-terraform.md); README section 12.

## 2. HCP Terraform run (screenshot attached)

Run `run-U4naK3U3ayRCz3U7` in workspace `peach-dev`, started by the push of commit `095c16a` to
`main` (configuration source: GitHub), not from a laptop:
**Apply finished — Resources: 38 imported, 0 added, 19 changed, 0 destroyed.**

The 19 in-place changes were the new `ManagedBy = terraform` tag on 15 resources, the mailer's code
moving from an inline CloudFormation `ZipFile` to a Terraform-built zip of the same source, and
`publish = false` (the default) on three functions.

## 3. `terraform plan` after the migration

The next push (commit `b1e7ce7`, run `run-3rsXbRz2s6jrx9DK`) planned and finished with no changes.
The same check from the CLI (a speculative plan that runs in HCP Terraform):

```
Running plan in HCP Terraform. Output will stream here. Pressing Ctrl-C
will stop streaming the logs, but will not stop the plan running remotely.

Preparing the remote plan...

The remote workspace is configured to work with configuration at
infra relative to the target repository.

Terraform will upload the contents of the following directory,
excluding files or directories as defined by a .terraformignore file
at /Users/miunafw/Desktop/ооад/.terraformignore (if it is present),
in order to capture the filesystem context the remote workspace expects:
    /Users/miunafw/Desktop/ооад

To view this run in a browser, visit:
https://app.terraform.io/app/miunafw/peach-dev/runs/run-QYLpmrvR6DX6qRyC

Waiting for the plan to start...

Terraform v1.17.1
on linux_amd64

Initializing plugins and modules...
data.archive_file.mailer: Refreshing...
data.archive_file.mailer: Refresh complete after 0s [id=fc024d659b7d3e91b9b368649efa3f7a9e499502]
aws_vpc_endpoint.s3: Refreshing state... [id=vpce-01c06a486bbe47328]
data.aws_iam_policy_document.lambda_assume: Refreshing...
aws_cloudwatch_log_group.mailer: Refreshing state... [id=/aws/lambda/peach-report-mailer]
aws_iam_role.scheduler: Refreshing state... [id=peach-reports-SchedulerRole-VnrGYA5r94Ve]
aws_cognito_user_pool.main: Refreshing state... [id=us-east-1_RT89WsrUH]
aws_cloudwatch_log_group.builder: Refreshing state... [id=/aws/lambda/peach-report-builder]
aws_budgets_budget.monthly: Refreshing state... [id=757159686525:peach-monthly]
data.aws_caller_identity.current: Refreshing...
aws_cloudwatch_log_group.parser: Refreshing state... [id=/aws/lambda/peach-agenda-parser]
aws_sqs_queue.report_requests_dlq: Refreshing state... [id=https://sqs.us-east-1.amazonaws.com/757159686525/peach-report-requests-dlq]
data.aws_iam_policy_document.lambda_assume: Refresh complete after 0s [id=2690255455]
data.aws_caller_identity.current: Refresh complete after 0s [id=757159686525]
data.aws_lambda_function.backend: Refreshing...
aws_iam_role.builder: Refreshing state... [id=peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld]
aws_iam_role.mailer: Refreshing state... [id=peach-reports-MailerExecutionRole-XERzmccBtnGO]
aws_iam_role.parser: Refreshing state... [id=peach-ai-ExecutionRole-fOxutsIw89Kn]
aws_sqs_queue.report_requests: Refreshing state... [id=https://sqs.us-east-1.amazonaws.com/757159686525/peach-report-requests]
aws_s3_bucket.reports: Refreshing state... [id=peach-reports-757159686525]
data.aws_lambda_function.backend: Refresh complete after 0s [id=peach-backend]
aws_iam_role_policy.scheduler_send: Refreshing state... [id=peach-reports-SchedulerRole-VnrGYA5r94Ve:SendReportMessageToSQS]
aws_scheduler_schedule.weekly_report: Refreshing state... [id=default/peach-weekly-report]
aws_iam_role_policy.mailer_s3_read: Refreshing state... [id=peach-reports-MailerExecutionRole-XERzmccBtnGO:S3ReportsRead]
aws_lambda_function.mailer: Refreshing state... [id=peach-report-mailer]
aws_iam_role_policy_attachment.mailer_basic: Refreshing state... [id=peach-reports-MailerExecutionRole-XERzmccBtnGO/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole]
aws_iam_role_policy.mailer_ses: Refreshing state... [id=peach-reports-MailerExecutionRole-XERzmccBtnGO:SESSendEmail]
aws_iam_role_policy_attachment.parser_basic: Refreshing state... [id=peach-ai-ExecutionRole-fOxutsIw89Kn/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole]
aws_cognito_identity_provider.google[0]: Refreshing state... [id=us-east-1_RT89WsrUH:Google]
aws_iam_role_policy.parser_bedrock: Refreshing state... [id=peach-ai-ExecutionRole-fOxutsIw89Kn:BedrockInvoke]
aws_iam_role_policy.builder_s3_write: Refreshing state... [id=peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld:S3ReportsWrite]
aws_iam_role_policy.builder_rds_connect: Refreshing state... [id=peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld:RdsDbConnect]
aws_cognito_user_pool_domain.main: Refreshing state... [id=peach-auth-757159686525]
aws_iam_role_policy.builder_sqs_poll: Refreshing state... [id=peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld:SQSPollReports]
aws_iam_role_policy_attachment.builder_vpc_access: Refreshing state... [id=peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole]
aws_cognito_user_pool_client.web: Refreshing state... [id=5f96rjbr4ctcqv1248m5tunj8o]
aws_lambda_permission.mailer_from_s3: Refreshing state... [id=peach-reports-MailerPermissionForS3-cGwRfkbRBR3u]
aws_s3_bucket_lifecycle_configuration.reports: Refreshing state... [id=peach-reports-757159686525]
aws_s3_bucket_public_access_block.reports: Refreshing state... [id=peach-reports-757159686525]
aws_s3_bucket_notification.reports: Refreshing state... [id=peach-reports-757159686525]
aws_lambda_function.parser: Refreshing state... [id=peach-agenda-parser]
aws_lambda_function.builder: Refreshing state... [id=peach-report-builder]
aws_lambda_event_source_mapping.builder_from_sqs: Refreshing state... [id=3f4fb773-6997-43a3-aef3-c26a709eac81]
aws_lambda_permission.parser_url: Refreshing state... [id=peach-ai-FunctionUrlPermission-PplMXQu0Hg49]
aws_lambda_function_url.parser: Refreshing state... [id=peach-agenda-parser]
aws_lambda_permission.parser_url_invoke: Refreshing state... [id=peach-ai-FunctionUrlInvokePermission-qVpsEjW0TtXc]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.

─────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
```

## How the migration was done

| Step | What happened |
| --- | --- |
| Bootstrap | `infra/bootstrap` (local state) created the IAM OIDC provider for `app.terraform.io` and the role `hcp-terraform-miunafw`, trusted only by workspace `peach-dev` of organization `miunafw`. The workspace uses `TFC_AWS_PROVIDER_AUTH` / `TFC_AWS_RUN_ROLE_ARN`: no AWS keys. |
| Translate | `auth.tf`, `reports.tf`, `ai.tf`, `variables.tf`, `outputs.tf`. Names unchanged (pool, client, domain prefix, bucket, queues, functions, and the role names CloudFormation generated). Lab 5's circular dependency is gone: bucket, `aws_lambda_permission` and `aws_s3_bucket_notification` are separate resources. |
| Check the plan before touching anything | A local plan with a temporary local state found `aws_cognito_user_pool_client.web must be replaced` because `generate_secret = false` forces replacement of an imported client. That would have changed the client ID and broken sign-in. Fixed in the HCL (attribute left unset), plus `ignore_changes = [schema]` on the pool and the Cognito-filled Google provider details. Result: 38 to import, 0 to add, 0 to destroy. |
| 3a. Let go | `DeletionPolicy` / `UpdateReplacePolicy: Retain` on all 25 resources (4 + 14 + 7), stacks updated with the same parameters, Retain verified in each deployed template, stacks deleted. Pool (3 users), bucket (4 reports), queues, functions, schedule, parser URL and budget checked afterwards. |
| 3b/3c. Take over | `imports.tf` with 38 import blocks (CloudFormation's inline policies and managed-policy attachments are separate Terraform resources, so 25 became 38). Push to `main`, plan in HCP Terraform, Confirm & Apply. |
| Clean up | `imports.tf` and the three templates deleted. `prevent_destroy` on the pool and the bucket. |

**Re-created resources: none.** Every resource was imported. The only real change was the mailer's
code package (same Python source, now zipped by Terraform), an in-place update.

## Pipeline after the migration

- Infrastructure: pull request → speculative plan as a check; merge/push to `main` → plan in HCP
  Terraform → Confirm & Apply. The Makefile has `infra-init`, `infra-fmt`, `infra-validate`,
  `infra-plan`, `infra-env` and no apply target.
- Application code: unchanged road. `make deploy-ai` / `make deploy-reports` build the image and
  call `update-function-code`; Terraform ignores `image_uri`, so the two roads do not fight. When a
  change needs both (a new environment variable that new code reads), the Terraform change goes
  first, then the code.
- Secrets: `google_client_id` / `google_client_secret` are sensitive workspace variables;
  `budget_email` is a workspace variable, not in the public repository.
