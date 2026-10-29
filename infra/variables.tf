variable "project_name" {
  type        = string
  default     = "peach"
  description = "Prefix for resource names and the PROJECT_NAME tag."
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# --- auth (Lab 4) -----------------------------------------------------------

variable "callback_urls" {
  type        = list(string)
  description = "Allowed OAuth callback URLs."
}

variable "logout_urls" {
  type        = list(string)
  description = "Allowed logout URLs."
}

variable "google_client_id" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Google OAuth client ID. Empty means email + password only."
}

variable "google_client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Google OAuth client secret. Set it in the workspace, never in a file."
}

# --- reports (Lab 5) --------------------------------------------------------

variable "vpc_id" {
  type        = string
  description = "VPC where the backend and the database live (gets an S3 gateway endpoint)."
}

variable "route_table_ids" {
  type        = list(string)
  description = "Route tables the S3 gateway endpoint is attached to."
}

variable "reports_from_email" {
  type        = string
  description = "Verified SES identity that sends the weekly report."
}

variable "reports_to_email" {
  type        = string
  description = "Verified SES identity that receives it."
}

variable "report_builder_image_uri" {
  type        = string
  description = "Image the report builder was created with. Later deploys use update-function-code."
}

# --- agenda parser (Lab 6) --------------------------------------------------

variable "parser_model" {
  type        = string
  default     = "us.amazon.nova-lite-v1:0"
  description = "Bedrock model ID. anthropic.claude-* uses the Messages API, others use Converse."
}

variable "parser_allowed_origins" {
  type        = list(string)
  default     = ["*"]
  description = "Origins the browser may call the parser from."
}

variable "agenda_parser_image_uri" {
  type        = string
  description = "Image the parser was created with. Later deploys use update-function-code."
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "budget_email" {
  type        = string
  description = "Where the monthly budget alarm is sent."
}

variable "monthly_budget_usd" {
  type    = number
  default = 5
}
