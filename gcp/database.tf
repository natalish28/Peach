# Cloud SQL for PostgreSQL: the smallest shared-core tier. Unlike Aurora it does not pause: it bills
# by the hour until it is stopped (make gcp-db-stop). Storage bills while stopped too.
resource "google_sql_database_instance" "main" {
  name             = "${var.project_name}-db"
  database_version = "POSTGRES_17" # the version Compose runs locally
  region           = var.region

  # terraform destroy must be able to remove it: this is a lab environment (ADR 0008).
  deletion_protection = false

  settings {
    # Shared-core tiers exist only in the Enterprise edition; PostgreSQL 16+ defaults to Plus.
    edition           = "ENTERPRISE"
    tier              = var.db_tier
    availability_type = "ZONAL"

    disk_type       = "PD_SSD"
    disk_size       = var.db_disk_gb
    disk_autoresize = false # a disk that grows never shrinks back, and bills by the GB

    activation_policy           = "ALWAYS"
    deletion_protection_enabled = false

    # The data is re-created by the migrations; backups would be a second storage line.
    backup_configuration {
      enabled = false
    }

    # A public IP with no authorized networks: nothing can connect directly. Cloud Run connects
    # through the Cloud SQL connector, which authorizes with IAM (roles/cloudsql.client).
    ip_configuration {
      ipv4_enabled = true
      ssl_mode     = "ENCRYPTED_ONLY"
    }
  }

  lifecycle {
    # make gcp-db-stop / gcp-db-start switch this; the next apply must not undo it.
    ignore_changes = [settings[0].activation_policy]
  }

  depends_on = [google_project_service.this]
}

resource "google_sql_database" "app" {
  name     = var.project_name
  instance = google_sql_database_instance.main.name
}

# Generated here, never in the repository. It is in the workspace state (ADR 0008, Consequences).
resource "random_password" "db" {
  length  = 32
  special = false # it goes into a URL
}

resource "google_sql_user" "app" {
  name     = var.project_name
  instance = google_sql_database_instance.main.name
  password = random_password.db.result
}

# The whole URL is the secret, so the application reads one variable, as it does everywhere else.
# The host is the connector's Unix socket that Cloud Run mounts under /cloudsql.
resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.project_name}-database-url"

  replication {
    auto {}
  }

  depends_on = [google_project_service.this]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret      = google_secret_manager_secret.database_url.id
  secret_data = "postgresql+asyncpg://${google_sql_user.app.name}:${random_password.db.result}@/${google_sql_database.app.name}?host=/cloudsql/${google_sql_database_instance.main.connection_name}"
}

resource "google_secret_manager_secret_iam_member" "api_reads_database_url" {
  secret_id = google_secret_manager_secret.database_url.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${local.api_service_account}"
}
