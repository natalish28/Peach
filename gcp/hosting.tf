# Firebase Hosting: CDN and a managed certificate included. Terraform creates the site; the files
# and the /api/** rewrite to Cloud Run are deployed by make deploy-gcp-frontend (firebase.json).
resource "google_firebase_project" "this" {
  provider   = google-beta
  project    = var.project_id
  depends_on = [google_project_service.this]
}

resource "google_firebase_hosting_site" "web" {
  provider = google-beta
  project  = google_firebase_project.this.project
  site_id  = var.hosting_site_id
}
