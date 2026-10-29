# Was infra/ai.yml (Lab 6): the agenda-parser Lambda (outside the VPC) behind its own function
# URL, and a monthly AWS Budget alarm.

resource "aws_iam_role" "parser" {
  name               = "peach-ai-ExecutionRole-fOxutsIw89Kn"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "parser_basic" {
  role       = aws_iam_role.parser.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "parser_bedrock" {
  name = "BedrockInvoke"
  role = aws_iam_role.parser.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "bedrock-mantle:CreateInference", # Claude, Anthropic Messages API
        "bedrock:InvokeModel",            # Converse API (Amazon Nova, ...)
      ]
      Resource = "*" # TODO narrow to the model's ARN
    }]
  })
}

resource "aws_cloudwatch_log_group" "parser" {
  name              = "/aws/lambda/${var.project_name}-agenda-parser"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "parser" {
  function_name = "${var.project_name}-agenda-parser"
  description   = "${var.project_name} agenda parser (pasted text -> JSON via Bedrock)"
  package_type  = "Image"
  image_uri     = var.agenda_parser_image_uri
  architectures = ["arm64"]
  memory_size   = 512
  timeout       = 30
  role          = aws_iam_role.parser.arn

  image_config {
    command = ["app.ai.agenda_lambda.handler"]
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.parser.name
  }

  environment {
    variables = {
      APP_ENV              = "production"
      PARSER_MODEL         = var.parser_model
      BEDROCK_REGION       = var.region
      COGNITO_REGION       = var.region
      COGNITO_USER_POOL_ID = aws_cognito_user_pool.main.id
      COGNITO_CLIENT_ID    = aws_cognito_user_pool_client.web.id
      # COGNITO_JWKS is left unset: outside the VPC the keys are fetched from the issuer.
    }
  }

  lifecycle {
    ignore_changes = [image_uri]
  }

  depends_on = [aws_cloudwatch_log_group.parser]
}

resource "aws_lambda_function_url" "parser" {
  function_name      = aws_lambda_function.parser.function_name
  authorization_type = "NONE" # the handler verifies the Cognito token itself

  cors {
    allow_origins = var.parser_allowed_origins
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 600
  }
}

resource "aws_lambda_permission" "parser_url" {
  statement_id           = "peach-ai-FunctionUrlPermission-PplMXQu0Hg49"
  function_name          = aws_lambda_function.parser.function_name
  action                 = "lambda:InvokeFunctionUrl"
  principal              = "*"
  function_url_auth_type = "NONE"
}

resource "aws_lambda_permission" "parser_url_invoke" {
  statement_id             = "peach-ai-FunctionUrlInvokePermission-qVpsEjW0TtXc"
  function_name            = aws_lambda_function.parser.function_name
  action                   = "lambda:InvokeFunction"
  principal                = "*"
  invoked_via_function_url = true
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    notification_type          = "FORECASTED"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_email]
  }
}
