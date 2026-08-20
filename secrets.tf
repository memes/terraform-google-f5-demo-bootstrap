# Working with NGINX+ images usually requires a JWT from F5 for retrieval and for activation. If provided, create a
# a secret with the JWT value that can be accessed by others with the correct IAM role outside the scope of this module.
module "nginx_jwt" {
  for_each   = local.has_nginx_jwt_secret ? { nginx-jwt = var.nginx_jwt } : {}
  source     = "memes/secret-manager/google"
  version    = "2.2.2"
  project_id = var.project_id
  id         = format("%s-%s", var.name, each.key)
  secret     = each.value
  accessors  = []
}

# If NGINX JWT was provided, store the password 'none' for use by remote Artifact Registry; upstream registries are
# required to have a password field that takes a secret id, not a plaintext value.
module "nginx_upstream_password" {
  for_each   = local.has_nginx_jwt_secret ? { nginx-upstream = "none" } : {}
  source     = "memes/secret-manager/google"
  version    = "2.2.2"
  project_id = var.project_id
  id         = format("%s-%s", var.name, each.key)
  secret     = each.value
  accessors  = [for k, v in google_project_service_identity.ids : v.member if k == "artifactregistry.googleapis.com"]

  depends_on = [
    google_project_service_identity.ids,
  ]
}

# If harbor credentials for F5 AI repositories are provided, add the password as a secret that can be used by a remote
# Artifact Registry. No other access will be granted but can be added outside the scope of this module.
module "f5_ai_harbor_upstream_password" {
  for_each   = local.has_f5_ai_harbor_credentials_secret ? { f5-ai-upstream = var.f5_ai_harbor_credentials.password } : {}
  source     = "memes/secret-manager/google"
  version    = "2.2.2"
  project_id = var.project_id
  id         = format("%s-%s", var.name, each.key)
  secret     = each.value
  accessors  = [for k, v in google_project_service_identity.ids : v.member if k == "artifactregistry.googleapis.com"]

  depends_on = [
    google_project_service_identity.ids,
  ]
}

# F5 AI Guardrails and Red Team deployments need the license token; if provided, create a secret containing the token
# but do not automatically assign accessors. Consumers of the module can add appropriate access to IAM principals as
# needed.
module "f5_ai_license" {
  for_each   = local.has_f5_ai_license_secret ? { f5-ai-license = var.f5_ai_license } : {}
  source     = "memes/secret-manager/google"
  version    = "2.2.2"
  project_id = var.project_id
  id         = format("%s-%s", var.name, each.key)
  secret     = each.value
  accessors  = []
}
