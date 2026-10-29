# Step 3 of the migration: hand the resources that CloudFormation retained to Terraform.
# Delete this file after the first successful apply.

# --- auth ---
import {
  to = aws_cognito_user_pool.main
  id = "us-east-1_RT89WsrUH"
}
import {
  to = aws_cognito_identity_provider.google[0]
  id = "us-east-1_RT89WsrUH:Google"
}
import {
  to = aws_cognito_user_pool_client.web
  id = "us-east-1_RT89WsrUH/5f96rjbr4ctcqv1248m5tunj8o"
}
import {
  to = aws_cognito_user_pool_domain.main
  id = "peach-auth-757159686525"
}

# --- reports ---
import {
  to = aws_vpc_endpoint.s3
  id = "vpce-01c06a486bbe47328"
}
import {
  to = aws_s3_bucket.reports
  id = "peach-reports-757159686525"
}
import {
  to = aws_s3_bucket_public_access_block.reports
  id = "peach-reports-757159686525"
}
import {
  to = aws_s3_bucket_lifecycle_configuration.reports
  id = "peach-reports-757159686525"
}
import {
  to = aws_s3_bucket_notification.reports
  id = "peach-reports-757159686525"
}
import {
  to = aws_sqs_queue.report_requests_dlq
  id = "https://sqs.us-east-1.amazonaws.com/757159686525/peach-report-requests-dlq"
}
import {
  to = aws_sqs_queue.report_requests
  id = "https://sqs.us-east-1.amazonaws.com/757159686525/peach-report-requests"
}
import {
  to = aws_iam_role.builder
  id = "peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld"
}
import {
  to = aws_iam_role_policy_attachment.builder_vpc_access
  id = "peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
import {
  to = aws_iam_role_policy.builder_s3_write
  id = "peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld:S3ReportsWrite"
}
import {
  to = aws_iam_role_policy.builder_sqs_poll
  id = "peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld:SQSPollReports"
}
import {
  to = aws_iam_role_policy.builder_rds_connect
  id = "peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld:RdsDbConnect"
}
import {
  to = aws_cloudwatch_log_group.builder
  id = "/aws/lambda/peach-report-builder"
}
import {
  to = aws_lambda_function.builder
  id = "peach-report-builder"
}
import {
  to = aws_lambda_event_source_mapping.builder_from_sqs
  id = "3f4fb773-6997-43a3-aef3-c26a709eac81"
}
import {
  to = aws_iam_role.scheduler
  id = "peach-reports-SchedulerRole-VnrGYA5r94Ve"
}
import {
  to = aws_iam_role_policy.scheduler_send
  id = "peach-reports-SchedulerRole-VnrGYA5r94Ve:SendReportMessageToSQS"
}
import {
  to = aws_scheduler_schedule.weekly_report
  id = "default/peach-weekly-report"
}
import {
  to = aws_iam_role.mailer
  id = "peach-reports-MailerExecutionRole-XERzmccBtnGO"
}
import {
  to = aws_iam_role_policy_attachment.mailer_basic
  id = "peach-reports-MailerExecutionRole-XERzmccBtnGO/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
import {
  to = aws_iam_role_policy.mailer_s3_read
  id = "peach-reports-MailerExecutionRole-XERzmccBtnGO:S3ReportsRead"
}
import {
  to = aws_iam_role_policy.mailer_ses
  id = "peach-reports-MailerExecutionRole-XERzmccBtnGO:SESSendEmail"
}
import {
  to = aws_cloudwatch_log_group.mailer
  id = "/aws/lambda/peach-report-mailer"
}
import {
  to = aws_lambda_function.mailer
  id = "peach-report-mailer"
}
import {
  to = aws_lambda_permission.mailer_from_s3
  id = "peach-report-mailer/peach-reports-MailerPermissionForS3-cGwRfkbRBR3u"
}

# --- agenda parser ---
import {
  to = aws_iam_role.parser
  id = "peach-ai-ExecutionRole-fOxutsIw89Kn"
}
import {
  to = aws_iam_role_policy_attachment.parser_basic
  id = "peach-ai-ExecutionRole-fOxutsIw89Kn/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
import {
  to = aws_iam_role_policy.parser_bedrock
  id = "peach-ai-ExecutionRole-fOxutsIw89Kn:BedrockInvoke"
}
import {
  to = aws_cloudwatch_log_group.parser
  id = "/aws/lambda/peach-agenda-parser"
}
import {
  to = aws_lambda_function.parser
  id = "peach-agenda-parser"
}
import {
  to = aws_lambda_function_url.parser
  id = "peach-agenda-parser"
}
import {
  to = aws_lambda_permission.parser_url
  id = "peach-agenda-parser/peach-ai-FunctionUrlPermission-PplMXQu0Hg49"
}
import {
  to = aws_lambda_permission.parser_url_invoke
  id = "peach-agenda-parser/peach-ai-FunctionUrlInvokePermission-qVpsEjW0TtXc"
}
import {
  to = aws_budgets_budget.monthly
  id = "757159686525:peach-monthly"
}
