# Creates an Artifact Registry instance for each repo type and assigns appropriate permissions to them.


locals {
  ar_repos = merge(
    try(var.gcp_options.ar.oci, true) ? {
      oci = {
        name        = format("%s-oci", var.name)
        format      = "DOCKER"
        description = format("OCI registry for %s", var.name)
        location    = try(var.gcp_options.ar.location, "us")
        identifier  = format("%s-docker.pkg.dev/%s/%s-oci", try(var.gcp_options.ar.location, "us"), var.project_id, var.name)
      }
    } : {},
    try(var.gcp_options.ar.deb, false) ? {
      deb = {
        name        = format("%s-deb", var.name)
        format      = "APT"
        description = format("deb package registry for %s", var.name)
        location    = try(var.gcp_options.ar.location, "us")
        identifier  = format("ar+https://%s-apt.pkg.dev/projects/%s %s-deb main", try(var.gcp_options.ar.location, "us"), var.project_id, var.name)
      }
    } : {},
    try(var.gcp_options.ar.rpm, false) ? {
      rpm = {
        name        = format("%s-rpm", var.name)
        format      = "YUM"
        description = format("rpm package registry for %s", var.name)
        location    = try(var.gcp_options.ar.location, "us")
        identifier  = format("https://%s-yum.pkg.dev/projects/%s/%s-rpm", try(var.gcp_options.ar.location, "us"), var.project_id, var.name)
      }
    } : {},
  )
}

# Create any needed artifact registry for the project
resource "google_artifact_registry_repository" "automation" {
  for_each      = local.ar_repos
  project       = var.project_id
  repository_id = each.value.name
  format        = each.value.format
  location      = try(var.gcp_options.ar.location, "us")
  description   = each.value.description
  labels        = var.labels

  depends_on = [
    google_project_service.apis,
  ]
}

# Allow the IaC automation service account admin access to the repos.
resource "google_artifact_registry_repository_iam_member" "iac" {
  for_each   = google_artifact_registry_repository.automation
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.admin"
  member     = google_service_account.iac.member

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

# Allow OIDC principals with attribute 'artifact_registry="writer"' read-only access to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "reader" {
  for_each   = google_artifact_registry_repository.automation
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.reader"
  member     = format("principalSet://iam.googleapis.com/%s/attribute.artifact_registry/reader", google_iam_workload_identity_pool.bots.name)

  depends_on = [
    google_project_service.apis,
    google_iam_workload_identity_pool.bots,
  ]
}

# Allow OIDC principals with attribute 'artifact_registry="writer"' push access to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "writer" {
  for_each   = google_artifact_registry_repository.automation
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.writer"
  member     = format("principalSet://iam.googleapis.com/%s/attribute.artifact_registry/writer", google_iam_workload_identity_pool.bots.name)

  depends_on = [
    google_project_service.apis,
    google_iam_workload_identity_pool.bots,
  ]
}

# This creates the service account that may be used by CI services that need to write to registry without requiring full
# IaC access.
resource "google_service_account" "ar" {
  project      = var.project_id
  account_id   = format("%s-ar", var.name)
  display_name = "Artifact Registry automation service account"
  description  = <<-EOD
  Service account that may be used by various automation providers that need to write to Artifact Registry.
  EOD

  depends_on = [
    google_project_service.apis,
  ]
}

# Bind the workload identity user role on Artifact Registry service account for principals that satisfy the condition
# that their respective provider has the custom 'ar_sa' attribute set to true.
resource "google_service_account_iam_member" "ar" {
  service_account_id = google_service_account.ar.name
  member             = format("principalSet://iam.googleapis.com/%s/attribute.ar_sa/enabled", google_iam_workload_identity_pool.bots.name)
  role               = "roles/iam.workloadIdentityUser"

  depends_on = [
    google_project_service.apis,
    google_service_account.ar,
    google_iam_workload_identity_pool.bots,
  ]
}

# Allow OIDC principals with attribute 'artifact_registry="writer"' push access to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "ar" {
  for_each   = google_artifact_registry_repository.automation
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.writer"
  member     = google_service_account.ar.member

  depends_on = [
    google_project_service.apis,
    google_service_account.ar,
    google_iam_workload_identity_pool.bots,
  ]
}
