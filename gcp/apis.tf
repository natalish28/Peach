# APIs are off in a new project. Enabling them here makes a fresh project reproducible.
# disable_on_destroy = false: switching an API off on destroy can break other things in the
# project, and an enabled API costs nothing by itself.
resource "google_project_service" "this" {
  for_each = toset([
    "run.googleapis.com",
    "sqladmin.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "firebase.googleapis.com",
    "firebasehosting.googleapis.com",
    "logging.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}
