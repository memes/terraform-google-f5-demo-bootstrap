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
        docker_config = {
          immutable_tags = true
        }
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

resource "google_project_service_identity" "ar" {
  provider = google-beta
  for_each = length(local.ar_repos) > 0 || local.has_nginx_jwt_secret || local.has_f5_ai_harbor_credentials_secret ? { ar = true } : {}
  project  = var.project_id
  service  = "artifactregistry.googleapis.com"
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

  dynamic "docker_config" {
    for_each = try(each.value.docker_config, {})
    content {
      immutable_tags = try(docker_config.value.immutable_tags, true)
    }
  }

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

# Allow OIDC principals with attribute 'artifact_registry="reader"' read-only access to Artifact Registry
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
  for_each     = length(google_artifact_registry_repository.automation) > 0 ? { ar = true } : {}
  project      = var.project_id
  account_id   = format("%s-ar", var.name)
  display_name = "Artifact Registry automation service account"
  description  = <<-EOD
  Service account that may be used by various automation providers that need to write to Artifact Registry.
  EOD

  depends_on = [
    google_project_service.apis,
    google_artifact_registry_repository.automation,
  ]
}

# For each repository, bind the AR service account as a writer.
resource "google_artifact_registry_repository_iam_member" "ar" {
  for_each = { for i, pair in setproduct([for k, v in google_artifact_registry_repository.automation : k], [for k, v in google_service_account.ar : v.member]) : tostring(i) => {
    project    = google_artifact_registry_repository.automation[pair[0]].project
    location   = google_artifact_registry_repository.automation[pair[0]].location
    repository = google_artifact_registry_repository.automation[pair[0]].name
    member     = pair[1]
    }
  }
  project    = each.value.project
  location   = each.value.location
  repository = each.value.repository
  role       = "roles/artifactregistry.writer"
  member     = each.value.member

  depends_on = [
    google_project_service.apis,
    google_service_account.ar,
    google_artifact_registry_repository.automation,
    google_iam_workload_identity_pool.bots,
  ]
}

# Bind the workload identity user role on Artifact Registry service account for principals that satisfy the condition
# that their respective provider has the custom 'ar_sa' attribute set to true.
resource "google_service_account_iam_member" "ar" {
  for_each           = google_service_account.ar
  service_account_id = each.value.name
  member             = format("principalSet://iam.googleapis.com/%s/attribute.ar_sa/enabled", google_iam_workload_identity_pool.bots.name)
  role               = "roles/iam.workloadIdentityUser"

  depends_on = [
    google_project_service.apis,
    google_service_account.ar,
    google_iam_workload_identity_pool.bots,
  ]
}

resource "google_artifact_registry_repository" "upstream_nginx" {
  for_each      = local.has_nginx_jwt_secret ? { nginx = true } : {}
  project       = var.project_id
  repository_id = format("%s-%s", var.name, each.key)
  format        = "DOCKER"
  location      = try(var.gcp_options.ar.location, "us")
  description   = format("Upstream NGINX private Docker repository for %s", var.name)
  labels        = var.labels
  mode          = "REMOTE_REPOSITORY"
  remote_repository_config {
    description                 = "F5 NGINX+ private Docker repository"
    disable_upstream_validation = true
    docker_repository {
      custom_repository {
        uri = "https://private-registry.nginx.com"
      }
    }
    upstream_credentials {
      username_password_credentials {
        username = format("%s:none", var.nginx_jwt)
      }
    }
  }

  depends_on = [
    google_project_service.apis,
  ]
}

resource "google_artifact_registry_repository" "upstream_f5_ai" {
  for_each      = local.has_f5_ai_harbor_credentials_secret ? { "f5-ai" = true } : {}
  project       = var.project_id
  repository_id = format("%s-%s", var.name, each.key)
  format        = "DOCKER"
  location      = try(var.gcp_options.ar.location, "us")
  description   = format("Upstream F5 AI private Docker repository for %s", var.name)
  labels        = var.labels
  mode          = "REMOTE_REPOSITORY"
  remote_repository_config {
    description                 = "F5 AI private Harbor repository"
    disable_upstream_validation = true
    docker_repository {
      custom_repository {
        uri = "https://harbor.calypsoai.app"
      }
    }
    upstream_credentials {
      username_password_credentials {
        username                = var.f5_ai_harbor_credentials.username
        password_secret_version = format("%s/versions/latest", one([for k, v in module.f5_ai_harbor_password : v.id]))
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    module.f5_ai_harbor_password,
  ]
}

resource "google_artifact_registry_repository" "virtual" {
  for_each      = try(var.gcp_options.ar.oci, true) || local.has_nginx_jwt_secret || local.has_f5_ai_harbor_credentials_secret ? { oci-virt = true } : {}
  project       = var.project_id
  repository_id = format("%s-%s", var.name, each.key)
  format        = "DOCKER"
  location      = try(var.gcp_options.ar.location, "us")
  description   = format("Virtual Docker repository for %s", var.name)
  labels        = var.labels
  mode          = "VIRTUAL_REPOSITORY"
  virtual_repository_config {
    dynamic "upstream_policies" {
      for_each = { for k, v in google_artifact_registry_repository.automation : k => v if k == "oci" }
      content {
        id         = upstream_policies.value.repository_id
        repository = upstream_policies.value.id
        priority   = 100
      }
    }
    dynamic "upstream_policies" {
      for_each = google_artifact_registry_repository.upstream_nginx
      content {
        id         = upstream_policies.value.repository_id
        repository = upstream_policies.value.id
        priority   = 500
      }
    }
    dynamic "upstream_policies" {
      for_each = google_artifact_registry_repository.upstream_f5_ai
      content {
        id         = upstream_policies.value.repository_id
        repository = upstream_policies.value.id
        priority   = 500
      }
    }
  }
}
