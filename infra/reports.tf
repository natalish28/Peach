# Was infra/reports.yaml (Lab 5): S3 reports bucket, SQS queue + DLQ, EventBridge Scheduler,
# the report-builder Lambda (SQS -> CSV in S3) and the report-mailer Lambda (S3 -> SES).

locals {
  reports_bucket = "${var.project_name}-reports-${data.aws_caller_identity.current.account_id}"

  # The backend stack stays on CloudFormation. Its Lambda already holds the database URL
  # and the Cognito keys, so read them instead of keeping a second copy by hand.
  backend_env = data.aws_lambda_function.backend.environment[0].variables
}

data "aws_lambda_function" "backend" {
  function_name = "${var.project_name}-backend"
}

# --- S3 -----------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.route_table_ids
}

resource "aws_s3_bucket" "reports" {
  bucket = local.reports_bucket

  # Deleting the bucket deletes every report.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "DeleteReportsAfter90Days"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

# The bucket, the permission and the notification are three resources, so Lab 5's circular
# dependency (the bucket needs the permission, the permission needs the bucket's ARN) is gone.
resource "aws_s3_bucket_notification" "reports" {
  bucket = aws_s3_bucket.reports.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.mailer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "reports/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.mailer_from_s3]
}

# --- SQS ------------------------------------------------------------------------

resource "aws_sqs_queue" "report_requests_dlq" {
  name                      = "${var.project_name}-report-requests-dlq"
  message_retention_seconds = 1209600 # 14 days
  max_message_size          = 1048576 # SQS default, set so the plan matches the real queue
}

resource "aws_sqs_queue" "report_requests" {
  name             = "${var.project_name}-report-requests"
  max_message_size = 1048576

  # At least 6 times the builder's timeout (60 s * 6)
  visibility_timeout_seconds = 360

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.report_requests_dlq.arn
    maxReceiveCount     = 3
  })
}

# --- report builder -----------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "builder" {
  name               = "peach-reports-BuilderExecutionRole-3iu4ipjSw3Ld" # name CloudFormation generated
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "builder_vpc_access" {
  role       = aws_iam_role.builder.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "builder_s3_write" {
  name = "S3ReportsWrite"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = ["arn:aws:s3:::${local.reports_bucket}/*"]
    }]
  })
}

resource "aws_iam_role_policy" "builder_sqs_poll" {
  name = "SQSPollReports"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = [aws_sqs_queue.report_requests.arn]
    }]
  })
}

resource "aws_iam_role_policy" "builder_rds_connect" {
  name = "RdsDbConnect"
  role = aws_iam_role.builder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds-db:connect"]
      Resource = "*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "builder" {
  name              = "/aws/lambda/${var.project_name}-report-builder"
  retention_in_days = 7
}

resource "aws_lambda_function" "builder" {
  function_name = "${var.project_name}-report-builder"
  description   = "Builds weekly report CSV and uploads to S3"
  package_type  = "Image"
  image_uri     = var.report_builder_image_uri
  architectures = ["arm64"]
  memory_size   = 512
  timeout       = 60
  role          = aws_iam_role.builder.arn

  image_config {
    command = ["app.reports.lambda_handler.handler"]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.builder.name
  }

  environment {
    variables = {
      APP_ENV              = "production"
      LOG_LEVEL            = "info"
      DB_POOLING           = "false"
      DATABASE_URL         = local.backend_env["DATABASE_URL"]
      REPORTS_BUCKET       = local.reports_bucket
      COGNITO_REGION       = var.region
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
      COGNITO_JWKS         = local.backend_env["COGNITO_JWKS"]
    }
  }

  # The deploy script pushes a new image and calls update-function-code. Terraform owns
  # the shape of the function, not which build is running.
  lifecycle {
    ignore_changes = [image_uri]
  }

  depends_on = [aws_cloudwatch_log_group.builder]
}

resource "aws_lambda_event_source_mapping" "builder_from_sqs" {
  event_source_arn = aws_sqs_queue.report_requests.arn
  function_name    = aws_lambda_function.builder.arn
  batch_size       = 1
  enabled          = true
}

# --- EventBridge Scheduler (every Monday 07:00 Kyiv time) ----------------------

resource "aws_iam_role" "scheduler" {
  name = "peach-reports-SchedulerRole-VnrGYA5r94Ve"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_send" {
  name = "SendReportMessageToSQS"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = [aws_sqs_queue.report_requests.arn]
    }]
  })
}

resource "aws_scheduler_schedule" "weekly_report" {
  name                         = "${var.project_name}-weekly-report"
  description                  = "Triggers weekly report generation every Monday at 07:00 Kyiv time"
  schedule_expression          = "cron(0 7 ? * MON *)"
  schedule_expression_timezone = "Europe/Kyiv"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_sqs_queue.report_requests.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = "{\"week\": null, \"source\": \"schedule\"}"
  }
}

# --- report mailer ------------------------------------------------------------

resource "aws_iam_role" "mailer" {
  name               = "peach-reports-MailerExecutionRole-XERzmccBtnGO"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "mailer_basic" {
  role       = aws_iam_role.mailer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "mailer_s3_read" {
  name = "S3ReportsRead"
  role = aws_iam_role.mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = ["arn:aws:s3:::${local.reports_bucket}/*"]
    }]
  })
}

resource "aws_iam_role_policy" "mailer_ses" {
  name = "SESSendEmail"
  role = aws_iam_role.mailer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
    }]
  })
}

resource "aws_cloudwatch_log_group" "mailer" {
  name              = "/aws/lambda/${var.project_name}-report-mailer"
  retention_in_days = 7
}

data "archive_file" "mailer" {
  type        = "zip"
  source_file = "${path.module}/lambda/mailer/index.py"
  output_path = "${path.module}/.build/mailer.zip"
}

resource "aws_lambda_function" "mailer" {
  function_name    = "${var.project_name}-report-mailer"
  description      = "Sends weekly report emails with CSV attachment via Amazon SES"
  runtime          = "python3.12"
  handler          = "index.handler"
  memory_size      = 256
  timeout          = 30
  role             = aws_iam_role.mailer.arn
  filename         = data.archive_file.mailer.output_path
  source_code_hash = data.archive_file.mailer.output_base64sha256

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.mailer.name
  }

  environment {
    variables = {
      REPORTS_FROM_EMAIL = var.reports_from_email
      REPORTS_TO_EMAIL   = var.reports_to_email
    }
  }

  depends_on = [aws_cloudwatch_log_group.mailer]
}

resource "aws_lambda_permission" "mailer_from_s3" {
  statement_id   = "peach-reports-MailerPermissionForS3-cGwRfkbRBR3u"
  function_name  = aws_lambda_function.mailer.function_name
  action         = "lambda:InvokeFunction"
  principal      = "s3.amazonaws.com"
  source_arn     = "arn:aws:s3:::${local.reports_bucket}"
  source_account = data.aws_caller_identity.current.account_id
}
