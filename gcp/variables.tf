variable "project_id" {
  type        = string
  description = "Google Cloud project ID (permanent and globally unique)."
}

variable "project_name" {
  type        = string
  default     = "peach"
  description = "Prefix for resource names."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "hosting_site_id" {
  type        = string
  description = "Firebase Hosting site; the frontend is served at https://<id>.web.app."
}

# --- database ----------------------------------------------------------------------------------

variable "db_tier" {
  type        = string
  default     = "db-f1-micro"
  description = "Shared-core tier, 0.6 GB. db-g1-small is the next step up."
}

variable "db_disk_gb" {
  type    = number
  default = 10
}

# --- API ---------------------------------------------------------------------------------------

variable "api_max_instances" {
  type        = number
  default     = 1
  description = "Upper bound on Cloud Run instances: a cost cap, and db-f1-micro allows only ~25 connections."
}

# Sign-in stays on AWS for now: the API verifies Cognito ID tokens and downloads the pool's
# public keys itself (Cloud Run, unlike the Lambda in the VPC, has a route to the internet).
# Both IDs are public: they are compiled into the frontend bundle anyway.
variable "cognito_region" {
  type    = string
  default = "us-east-1"
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_client_id" {
  type = string
}
