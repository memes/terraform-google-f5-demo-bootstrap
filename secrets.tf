# Working with NGINX+ images usually requires a JWT from F5 for retrieval and for activation. If provided, create a
# a secret with the JWT value that can be accessed by others with the correct IAM role outside the scope of this module.
resource "google_secret_manager_secret" "nginx_jwt" {
  for_each  = local.has_nginx_jwt_secret ? { nginx-jwt = true } : {}
  project   = var.project_id
  secret_id = format("%s-%s", var.name, each.key)
  labels    = var.labels
  replication {
    auto {
    }
  }
}

resource "google_secret_manager_secret_version" "nginx_jwt" {
  for_each    = google_secret_manager_secret.nginx_jwt
  secret      = each.value.id
  secret_data = var.nginx_jwt
}

# If NGINX JWT was provided, store the password 'none' for use by remote Artifact Registry; upstream registries are
# required to have a password field that takes a secret id, not a plaintext value.
resource "google_secret_manager_secret" "upstream_oci_password_nginx" {
  for_each  = local.has_nginx_jwt_secret ? { upstream-oci-nginx = true } : {}
  project   = var.project_id
  secret_id = format("%s-%s", var.name, each.key)
  labels    = var.labels
  replication {
    auto {
    }
  }
}

resource "google_secret_manager_secret_version" "upstream_oci_password_nginx" {
  for_each    = google_secret_manager_secret.upstream_oci_password_nginx
  secret      = each.value.id
  secret_data = "none"
}

resource "google_secret_manager_secret_iam_member" "upstream_oci_password_nginx" {
  for_each  = google_secret_manager_secret.upstream_oci_password_nginx
  project   = each.value.project
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_project_service_identity.ids["artifactregistry.googleapis.com"].member

  depends_on = [
    google_project_service_identity.ids,
    google_secret_manager_secret.upstream_oci_password_nginx,
  ]
}

# If harbor credentials for F5 AI repositories are provided, add the password as a secret that can be used by a remote
# Artifact Registry. No other access will be granted but can be added outside the scope of this module.
resource "google_secret_manager_secret" "upstream_oci_password_f5_ai" {
  for_each  = local.has_f5_ai_repo_credentials_secret ? { upstream-oci-password-f5-ai = true } : {}
  project   = var.project_id
  secret_id = format("%s-%s", var.name, each.key)
  labels    = var.labels
  replication {
    auto {
    }
  }
}

resource "google_secret_manager_secret_version" "upstream_oci_password_f5_ai" {
  for_each    = google_secret_manager_secret.upstream_oci_password_f5_ai
  secret      = each.value.id
  secret_data = var.f5_ai_repo_credentials.password
}

resource "google_secret_manager_secret_iam_member" "upstream_oci_password_f5_ai" {
  for_each  = google_secret_manager_secret.upstream_oci_password_f5_ai
  project   = each.value.project
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_project_service_identity.ids["artifactregistry.googleapis.com"].member

  depends_on = [
    google_project_service_identity.ids,
    google_secret_manager_secret.upstream_oci_password_f5_ai,
  ]
}

# F5 AI Guardrails and Red Team deployments need the license token; if provided, create a secret containing the token
# but do not automatically assign accessors. Consumers of the module can add appropriate access to IAM principals as
# needed.
resource "google_secret_manager_secret" "f5_ai_license" {
  for_each  = local.has_f5_ai_license_secret ? { f5-ai-license = true } : {}
  project   = var.project_id
  secret_id = format("%s-%s", var.name, each.key)
  labels    = var.labels
  replication {
    auto {
    }
  }
}

resource "google_secret_manager_secret_version" "f5_ai_license" {
  for_each    = google_secret_manager_secret.f5_ai_license
  secret      = each.value.id
  secret_data = var.f5_ai_license
}
