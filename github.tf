# Bootstraps a new GitHub repository with the required settings for automation.
resource "github_repository" "automation" {
  name               = coalesce(try(var.github_options.name, ""), var.name)
  description        = coalesce(try(var.github_options.description, ""), "Bootstrapped automation repository")
  visibility         = try(var.github_options.private_repo, false) ? "private" : "public"
  archive_on_destroy = try(var.github_options.archive_on_destroy, true)
  dynamic "template" {
    for_each = coalesce(try(var.github_options.template, "memes/terraform-google-f5-demo-bootstrap-template"), "unspecified") == "unspecified" ? {} : { template = { owner = reverse(split("/", try(var.github_options.template, "memes/terraform-google-f5-demo-bootstrap-template")))[1], name = reverse(split("/", try(var.github_options.template, "memes/terraform-google-f5-demo-bootstrap-template")))[0] } }
    content {
      owner                = template.value.owner
      repository           = template.value.name
      include_all_branches = false
    }
  }
}

# Invite collaborators to the new repo
resource "github_repository_collaborator" "collaborators" {
  for_each   = try(length(var.github_options.collaborators), 0) > 0 ? var.github_options.collaborators : toset([])
  repository = github_repository.automation.name
  permission = "push"
  username   = each.value
}

# Create a deploy key
resource "tls_private_key" "automation" {
  for_each    = try(var.github_options.ssh_deploy_key, false) ? { key = true } : {}
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "github_repository_deploy_key" "automation" {
  for_each   = tls_private_key.automation
  repository = github_repository.automation.name
  title      = "Automation deploy key"
  key        = each.value.public_key_openssh
  read_only  = false
}

# Bind the new repo as an OIDC provider for automation.
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.bots.workload_identity_pool_id
  workload_identity_pool_provider_id = format("%s-gh", var.name)
  display_name                       = "GitHub OIDC provider"
  description                        = <<-EOD
  Defines an OIDC provider that authenticates a GitHub token as a valid automation user.
  EOD
  attribute_mapping = {
    "attribute.actor"            = "assertion.actor"
    "attribute.aud"              = "assertion.aud"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "google.subject"             = "assertion.sub"
    "attribute.ar_sa"            = try(length(google_service_account.ar), 0) > 0 ? "'enabled'" : "'disabled'"
    "attribute.infra_manager"    = try(var.gcp_options.enable_infra_manager, true) ? "'enabled'" : "'disabled'"
    "attribute.cloud_deploy"     = try(var.gcp_options.enable_cloud_deploy, true) ? "'enabled'" : "'disabled'"
  }
  # Only allow integration with the bootstrapped repo
  attribute_condition = format("attribute.repository_owner == '%s' && attribute.repository == '%s'", split("/", github_repository.automation.full_name)[0], github_repository.automation.full_name)
  oidc {
    # TODO @memes - the effect of an empty list is to impose a match against the
    # fully-qualified workload identity pool name. This should be sufficient but
    # review.
    allowed_audiences = []
    issuer_uri        = "https://token.actions.githubusercontent.com"
  }
  depends_on = [
    google_project_service.apis,
    google_service_account.ar,
    google_iam_workload_identity_pool.bots,
  ]
}

resource "github_actions_secret" "provider_id" {
  repository  = github_repository.automation.name
  secret_name = "WORKLOAD_IDENTITY_PROVIDER_ID"
  value       = google_iam_workload_identity_pool_provider.github.name
}

resource "github_actions_secret" "iac_sa" {
  repository  = github_repository.automation.name
  secret_name = "IAC_SERVICE_ACCOUNT"
  value       = google_service_account.iac.email

  depends_on = [
    google_project_service.apis,
    google_service_account.iac,
  ]
}

resource "github_actions_secret" "ar_sa" {
  for_each    = google_service_account.ar
  repository  = github_repository.automation.name
  secret_name = "AR_SERVICE_ACCOUNT"
  value       = each.value.email

  depends_on = [
    google_project_service.apis,
    google_service_account.ar,
  ]
}

resource "github_actions_secret" "deploy_sa" {
  for_each    = google_service_account.deploy
  repository  = github_repository.automation.name
  secret_name = "DEPLOY_SERVICE_ACCOUNT"
  value       = each.value.email

  depends_on = [
    google_project_service.apis,
    google_service_account.deploy,
  ]
}

resource "github_actions_variable" "project_id" {
  repository    = github_repository.automation.name
  variable_name = "PROJECT_ID"
  value         = var.project_id
}

resource "github_actions_variable" "registry" {
  for_each      = { for k, v in google_artifact_registry_repository.automation : format("%s_REGISTRY", upper(k)) => local.ar_repos[k].identifier }
  repository    = github_repository.automation.name
  variable_name = each.key
  value         = each.value
}

resource "github_actions_variable" "nginx_jwt" {
  for_each      = { for secret in module.nginx_jwt : "NGINX_JWT_SECRET" => secret.id }
  repository    = github_repository.automation.name
  variable_name = each.key
  value         = each.value
}
