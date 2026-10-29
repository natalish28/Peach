# Everything the Makefile and the deploy scripts used to read from CloudFormation outputs.

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "cognito_domain" {
  value = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}

output "reports_bucket_name" {
  value = aws_s3_bucket.reports.bucket
}

output "report_requests_queue_url" {
  value = aws_sqs_queue.report_requests.url
}

output "report_requests_queue_arn" {
  value = aws_sqs_queue.report_requests.arn
}

output "report_builder_function_name" {
  value = aws_lambda_function.builder.function_name
}

output "report_mailer_function_name" {
  value = aws_lambda_function.mailer.function_name
}

output "parser_url" {
  description = "Function URL of the agenda parser, with no trailing slash."
  value       = trimsuffix(aws_lambda_function_url.parser.function_url, "/")
}

output "parser_function_name" {
  value = aws_lambda_function.parser.function_name
}
