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

# Allow OIDC principals with attribute 'artifact_registry="reader"' read-only access to automation Artifact Registries
resource "google_artifact_registry_repository_iam_member" "automation_reader" {
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

# Allow OIDC principals with attribute 'artifact_registry="writer"' push access to automation Artifact Registries
resource "google_artifact_registry_repository_iam_member" "automation_writer" {
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

# Add any upstream OCI repositories as remote Artifact Registries

resource "google_artifact_registry_repository" "upstream_oci_nginx" {
  for_each      = local.has_nginx_jwt_secret ? { oci-nginx = true } : {}
  project       = var.project_id
  repository_id = format("%s-%s", var.name, each.key)
  format        = "DOCKER"
  location      = try(var.gcp_options.ar.location, "us")
  description   = format("Upstream NGINX private Docker repository for %s", var.name)
  labels        = var.labels
  mode          = "REMOTE_REPOSITORY"
  remote_repository_config {
    description                 = "F5 NGINX+ private Docker repository"
    disable_upstream_validation = false
    docker_repository {
      custom_repository {
        uri = "https://private-registry.nginx.com"
      }
    }
    upstream_credentials {
      username_password_credentials {
        username                = var.nginx_jwt
        password_secret_version = format("%s/versions/latest", one([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.id]))
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_iam_member.upstream_oci_password_nginx,
  ]
}

# Create a remote repository for F5 AI containers and charts.
resource "google_artifact_registry_repository" "upstream_oci_f5_ai" {
  for_each      = local.has_f5_ai_repo_credentials_secret ? { "oci-f5-ai" = true } : {}
  project       = var.project_id
  repository_id = format("%s-%s", var.name, each.key)
  format        = "DOCKER"
  location      = try(var.gcp_options.ar.location, "us")
  description   = format("Upstream F5 AI private Docker repository for %s", var.name)
  labels        = var.labels
  mode          = "REMOTE_REPOSITORY"
  remote_repository_config {
    description                 = "F5 AI private Harbor repository"
    disable_upstream_validation = false
    docker_repository {
      custom_repository {
        uri = "https://harbor.calypsoai.app"
      }
    }
    upstream_credentials {
      username_password_credentials {
        username                = var.f5_ai_repo_credentials.username
        password_secret_version = format("%s/versions/latest", one([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.id]))
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_iam_member.upstream_oci_password_f5_ai,
  ]
}

# Create a remote repository for public docker hub artifacts.
resource "google_artifact_registry_repository" "upstream_oci_docker_hub" {
  for_each      = try(var.gcp_options.ar.docker_hub, false) ? { "oci-docker-hub" = true } : {}
  project       = var.project_id
  repository_id = format("%s-%s", var.name, each.key)
  format        = "DOCKER"
  location      = try(var.gcp_options.ar.location, "us")
  description   = format("Upstream public Docker Hub repository for %s", var.name)
  labels        = var.labels
  mode          = "REMOTE_REPOSITORY"
  remote_repository_config {
    description                 = "Upstream public Docker Hub repository"
    disable_upstream_validation = true
    docker_repository {
      public_repository = "DOCKER_HUB"
    }
  }

  depends_on = [
    google_project_service.apis,
  ]
}

# Grant the service identity for Artifact Registry access to each local and upstream registry if a virtual registry will
# be created.
resource "google_artifact_registry_repository_iam_member" "identity_automation" {
  for_each   = local.enable_virtual_oci_registry ? google_artifact_registry_repository.automation : {}
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.reader"
  member     = google_project_service_identity.ids["artifactregistry.googleapis.com"].member

  depends_on = [
    google_project_service_identity.ids,
    google_artifact_registry_repository.automation,
  ]
}

resource "google_artifact_registry_repository_iam_member" "identity_upstream_oci_nginx" {
  for_each   = local.enable_virtual_oci_registry ? google_artifact_registry_repository.upstream_oci_nginx : {}
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.reader"
  member     = google_project_service_identity.ids["artifactregistry.googleapis.com"].member

  depends_on = [
    google_project_service_identity.ids,
    google_artifact_registry_repository.upstream_oci_nginx,
  ]
}

resource "google_artifact_registry_repository_iam_member" "identity_upstream_oci_f5_ai" {
  for_each   = local.enable_virtual_oci_registry ? google_artifact_registry_repository.upstream_oci_f5_ai : {}
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.reader"
  member     = google_project_service_identity.ids["artifactregistry.googleapis.com"].member

  depends_on = [
    google_project_service_identity.ids,
    google_artifact_registry_repository.upstream_oci_nginx,
  ]
}

resource "google_artifact_registry_repository_iam_member" "identity_upstream_oci_docker_hub" {
  for_each   = local.enable_virtual_oci_registry ? google_artifact_registry_repository.upstream_oci_docker_hub : {}
  project    = each.value.project
  location   = each.value.location
  repository = each.value.name
  role       = "roles/artifactregistry.reader"
  member     = google_project_service_identity.ids["artifactregistry.googleapis.com"].member

  depends_on = [
    google_project_service_identity.ids,
    google_artifact_registry_repository.upstream_oci_nginx,
  ]
}

# Create a virtual OCI repository, if requested. The project local, and any remote registries will be added to give a
# single image repository.
resource "google_artifact_registry_repository" "oci_virt" {
  for_each      = local.enable_virtual_oci_registry ? { oci-virt = true } : {}
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
        priority   = 1000
      }
    }
    dynamic "upstream_policies" {
      for_each = google_artifact_registry_repository.upstream_oci_docker_hub
      content {
        id         = upstream_policies.value.repository_id
        repository = upstream_policies.value.id
        priority   = 100
      }
    }
    dynamic "upstream_policies" {
      for_each = google_artifact_registry_repository.upstream_oci_nginx
      content {
        id         = upstream_policies.value.repository_id
        repository = upstream_policies.value.id
        priority   = 500
      }
    }
    dynamic "upstream_policies" {
      for_each = google_artifact_registry_repository.upstream_oci_f5_ai
      content {
        id         = upstream_policies.value.repository_id
        repository = upstream_policies.value.id
        priority   = 400
      }
    }
  }
}

# Allow OIDC principals with attribute 'artifact_registry="reader"' read-only access to virtual Artifact Registries
resource "google_artifact_registry_repository_iam_member" "virtual_reader" {
  for_each   = google_artifact_registry_repository.oci_virt
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
