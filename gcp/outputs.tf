output "project_id" {
  value = var.project_id
}

output "region" {
  value = var.region
}

output "api_service" {
  value = google_cloud_run_v2_service.api.name
}

output "api_url" {
  value = google_cloud_run_v2_service.api.uri
}

output "image_repository" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "hosting_site_id" {
  value = google_firebase_hosting_site.web.site_id
}

output "hosting_url" {
  value = google_firebase_hosting_site.web.default_url
}

output "sql_instance" {
  value = google_sql_database_instance.main.name
}

output "sql_connection_name" {
  value = google_sql_database_instance.main.connection_name
}
