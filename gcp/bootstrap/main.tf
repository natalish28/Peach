# One-time bootstrap for Google Cloud (Lab 9): the identities, and the trust that lets HCP Terraform
# act as one of them without a key. Applied locally, with your own Google account and a local state;
# everything else in gcp/ is applied by HCP Terraform.
#
#   gcloud auth application-default login
#   cd gcp/bootstrap
#   terraform init
#   terraform apply -var project_id=<your project id>
#
# Then copy the outputs into the peach-gcp workspace's environment variables (README, section 15).
# No service account key is created anywhere.

terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

variable "project_id" {
  type        = string
  description = "The Google Cloud project (created by hand, with billing linked)."
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "project_name" {
  type    = string
  default = "peach"
}

variable "tfc_organization_id" {
  type        = string
  default     = "org-vbn4yqGz8LNpCgpr"
  description = "HCP Terraform organization ID (not the name: a name can be re-registered)."
}

variable "tfc_workspace" {
  type        = string
  default     = "peach-gcp"
  description = "The one workspace of that organization allowed to act as the Terraform service account."
}

# Stretch (CI): numeric IDs, from `gh api repos/<owner>/<repo> --jq '.id, .owner.id'`.
# Empty means no GitHub provider is created.
variable "github_repository_id" {
  type    = string
  default = ""
}

variable "github_owner_id" {
  type    = string
  default = ""
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "this" {}

# What the bootstrap itself needs. The application's APIs are enabled by gcp/ (apis.tf).
resource "google_project_service" "bootstrap" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "serviceusage.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# --- service accounts: one per program ---------------------------------------------------------

resource "google_service_account" "terraform" {
  account_id   = "hcp-terraform"
  display_name = "HCP Terraform (workspace ${var.tfc_workspace})"
  depends_on   = [google_project_service.bootstrap]
}

resource "google_service_account" "api" {
  account_id   = "${var.project_name}-api"
  display_name = "Peach API on Cloud Run"
  depends_on   = [google_project_service.bootstrap]
}

# Only the roles gcp/ needs; no Owner, no Editor.
resource "google_project_iam_member" "terraform" {
  for_each = toset([
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/artifactregistry.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/firebase.admin", # adds Firebase to the project and creates the Hosting site
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

# Service Account User on the API's account only, not on the project: Terraform may deploy a
# Cloud Run service that runs as peach-api, and as nothing else.
resource "google_service_account_iam_member" "terraform_acts_as_api" {
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.terraform.email}"
}

# The API reaches Cloud SQL through the connector. Its access to the database secret is granted on
# the secret itself, in gcp/database.tf.
resource "google_project_iam_member" "api_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.api.email}"
}

# --- Workload Identity Federation: HCP Terraform -----------------------------------------------

resource "google_iam_workload_identity_pool" "ci" {
  workload_identity_pool_id = "peach-ci"
  display_name              = "CI and HCP Terraform"
  depends_on                = [google_project_service.bootstrap]
}

resource "google_iam_workload_identity_pool_provider" "tfc" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci.workload_identity_pool_id
  workload_identity_pool_provider_id = "hcp-terraform"
  display_name                       = "HCP Terraform"

  oidc {
    issuer_uri = "https://app.terraform.io"
  }

  attribute_mapping = {
    "google.subject"                      = "assertion.sub"
    "attribute.terraform_organization_id" = "assertion.terraform_organization_id"
    "attribute.terraform_workspace_name"  = "assertion.terraform_workspace_name"
    "attribute.terraform_run_phase"       = "assertion.terraform_run_phase"
  }

  # Only this organization (by ID) and this one workspace in it. Workspace names are unique inside
  # an organization, and the organization ID cannot be taken over.
  attribute_condition = "assertion.terraform_organization_id == \"${var.tfc_organization_id}\" && assertion.terraform_workspace_name == \"${var.tfc_workspace}\""
}

resource "google_service_account_iam_member" "tfc_impersonates_terraform" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.terraform_workspace_name/${var.tfc_workspace}"
}

# --- Workload Identity Federation: GitHub Actions (stretch) ------------------------------------

locals {
  github_enabled = var.github_repository_id != "" && var.github_owner_id != ""
}

resource "google_iam_workload_identity_pool_provider" "github" {
  count = local.github_enabled ? 1 : 0

  workload_identity_pool_id          = google_iam_workload_identity_pool.ci.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Actions"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"                = "assertion.sub"
    "attribute.repository_id"       = "assertion.repository_id"
    "attribute.repository_owner_id" = "assertion.repository_owner_id"
    "attribute.ref"                 = "assertion.ref"
  }

  # Numeric IDs: a repository or owner name can be deleted and registered again by someone else.
  attribute_condition = "assertion.repository_id == \"${var.github_repository_id}\" && assertion.repository_owner_id == \"${var.github_owner_id}\""
}

# CI pushes an image and rolls the service; it does not change infrastructure.
resource "google_service_account" "github_deploy" {
  count        = local.github_enabled ? 1 : 0
  account_id   = "github-deploy"
  display_name = "GitHub Actions: deploy the API image"
}

resource "google_project_iam_member" "github_deploy" {
  for_each = local.github_enabled ? toset(["roles/artifactregistry.writer", "roles/run.developer"]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_deploy[0].email}"
}

resource "google_service_account_iam_member" "github_deploy_acts_as_api" {
  count              = local.github_enabled ? 1 : 0
  service_account_id = google_service_account.api.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.github_deploy[0].email}"
}

resource "google_service_account_iam_member" "github_impersonates_deploy" {
  count              = local.github_enabled ? 1 : 0
  service_account_id = google_service_account.github_deploy[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/attribute.repository_id/${var.github_repository_id}"
}

# --- outputs: the peach-gcp workspace's environment variables ----------------------------------

output "TFC_GCP_PROVIDER_AUTH" {
  value = "true"
}

output "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL" {
  value = google_service_account.terraform.email
}

output "TFC_GCP_WORKLOAD_PROVIDER_NAME" {
  value = google_iam_workload_identity_pool_provider.tfc.name
}

output "api_service_account" {
  value = google_service_account.api.email
}

output "github_workload_provider" {
  value = local.github_enabled ? google_iam_workload_identity_pool_provider.github[0].name : null
}

output "github_deploy_service_account" {
  value = local.github_enabled ? google_service_account.github_deploy[0].email : null
}
