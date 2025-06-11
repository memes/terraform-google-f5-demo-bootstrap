terraform {
  required_version = ">= 1.5"
  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 6.3"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 6.9"
    }
  }
}

# Bootstrapping should enable the minimal set of services required to complete
# bootstrap and permit additional actions to be executed.
resource "google_project_service" "apis" {
  for_each = { for api in setunion([
    "cloudbuild.googleapis.com",
    "clouddeploy.googleapis.com",
    "iam.googleapis.com",
    "storage-api.googleapis.com",
  ], var.bootstrap_apis) : api => true }
  project                    = var.project_id
  service                    = each.key
  disable_on_destroy         = var.options.services_disable_on_destroy
  disable_dependent_services = var.options.disable_dependent_services
}

# Ensure the Cloud Build service identity is known
resource "google_project_service_identity" "build" {
  project = var.project_id
  service = "cloudbuild.googleapis.com"

  depends_on = [
    google_project_service.apis,
  ]
}

# Ensure the Cloud Deploy service identity is known
resource "google_project_service_identity" "deploy" {
  project = var.project_id
  service = "clouddeploy.googleapis.com"

  depends_on = [
    google_project_service.apis,
  ]
}

# This creates the Cloud Deploy execution service account, which can also be used as the Cloud Deploy automation service
# account.
resource "google_service_account" "sa" {
  project      = var.project_id
  account_id   = format("%s-deploy", var.name)
  display_name = "Cloud Deploy execution service account"
  description  = <<-EOD
  Cloud Deploy execution service account that will be used for pipelines associated with this repo.
  EOD

  depends_on = [
    google_project_service.apis,
    google_project_service_identity.sa,
  ]
}

# Bind the Cloud Deploy execution service account to job runner role at the project level, which includes access to
# buckets in the project.
resource "google_project_iam_member" "sa" {
  project = var.project_id
  role    = "roles/clouddeploy.jobRunner"
  member  = google_service_account.sa.member

  depends_on = [
    google_project_service.apis,
    google_service_account.sa,
  ]
}

# Ensure the Cloud Deploy execution service account can view and create objects in the bootstrapped bucket, if it is
# provided.
resource "google_storage_bucket_iam_member" "sa" {
  for_each = coalesce(var.bucket_name, "unspecified") == "unspecified" ? {} : { for role in ["roles/storage.objectViewer", "roles/storage.objectCreator"] : role => var.bucket_name }
  bucket   = each.value
  role     = each.key
  member   = google_service_account.sa.member

  depends_on = [
    google_project_service.apis,
    google_service_account.sa,
  ]
}
