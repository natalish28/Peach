locals {
  # Created by gcp/bootstrap, so Terraform needs no right to create service accounts.
  api_service_account = "${var.project_name}-api@${var.project_id}.iam.gserviceaccount.com"
  hosting_origins     = ["https://${var.hosting_site_id}.web.app", "https://${var.hosting_site_id}.firebaseapp.com"]
}

resource "google_artifact_registry_repository" "images" {
  repository_id = var.project_name
  location      = var.region
  format        = "DOCKER"

  # 0.5 GB is free. Keep the two newest images, delete the rest after a day.
  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "keep-newest"
    action = "KEEP"
    most_recent_versions {
      keep_count = 2
    }
  }

  cleanup_policies {
    id     = "delete-older"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "86400s"
    }
  }

  depends_on = [google_project_service.this]
}

# The same image as Docker Compose (target "runtime"): uvicorn on $PORT, migrations on start.
# No Lambda adapter. Terraform owns the shape of the service; make deploy-gcp-backend owns which
# image runs, the same split as the Lambda functions in infra/ (ADR 0007).
resource "google_cloud_run_v2_service" "api" {
  name                = "${var.project_name}-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = local.api_service_account

    scaling {
      min_instance_count = 0 # scales to zero
      max_instance_count = var.api_max_instances
    }

    max_instance_request_concurrency = 80

    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      # Placeholder for the first apply, before any image is pushed. It listens on $PORT too.
      image = "us-docker.pkg.dev/cloudrun/container/hello"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        cpu_idle          = true # request-based billing: no CPU charge between requests
        startup_cpu_boost = true
      }

      env {
        name  = "APP_ENV"
        value = "production"
      }
      env {
        name  = "CORS_ORIGINS"
        value = join(",", local.hosting_origins)
      }
      env {
        name  = "COGNITO_REGION"
        value = var.cognito_region
      }
      env {
        name  = "COGNITO_USER_POOL_ID"
        value = var.cognito_user_pool_id
      }
      env {
        name  = "COGNITO_CLIENT_ID"
        value = var.cognito_client_id
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }

      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

  depends_on = [
    google_project_service.this,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_iam_member.api_reads_database_url,
  ]
}

# Public: every /api/v1 route checks the Cognito token itself (app/api/router.py).
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = google_cloud_run_v2_service.api.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
