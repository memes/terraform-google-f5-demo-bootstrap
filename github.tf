# To support immutable subject claims in post-July 2026 repos we need to know the user id and organization id, if repo
# was created under an org.
data "github_user" "default" {
  username = ""
}

data "github_organization" "default" {
  for_each     = coalesce(try(var.github_options.org, null), "unspecified") == "unspecified" ? {} : { org = var.github_options.org }
  name         = each.value
  summary_only = true
}

locals {
  immutable_user = format("%s@%s", data.github_user.default.login, data.github_user.default.id)
  immutable_org  = one([for org in data.github_organization.default : format("%s@%s", org.login, org.id)])
}

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
  # Only allow integration with the bootstrapped repo using immutable subject matching
  attribute_condition = format("assertion.sub.startsWith('repo:%s/%s@%s:')", (local.immutable_org != null ? local.immutable_org : local.immutable_user), github_repository.automation.name, github_repository.automation.repo_id)
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
  for_each = merge(
    { for k, v in google_artifact_registry_repository.automation : format("%s_REGISTRY", replace(upper(k), "/[^A-Z0-9_]/", "_")) => local.ar_repos[k].identifier },
    { for k, v in google_artifact_registry_repository.upstream_nginx : format("%s_REGISTRY", replace(upper(k), "/[^A-Z0-9_]/", "_")) => format("%s-docker.pkg.dev/%s/%s", v.location, v.project, v.repository_id) },
    { for k, v in google_artifact_registry_repository.upstream_f5_ai : format("%s_REGISTRY", replace(upper(k), "/[^A-Z0-9_]/", "_")) => format("%s-docker.pkg.dev/%s/%s", v.location, v.project, v.repository_id) },
    { for k, v in google_artifact_registry_repository.oci_virt : format("%s_REGISTRY", replace(upper(k), "/[^A-Z0-9_]/", "_")) => format("%s-docker.pkg.dev/%s/%s", v.location, v.project, v.repository_id) },
  )
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

resource "github_actions_repository_permissions" "automation" {
  repository           = github_repository.automation.name
  enabled              = true
  sha_pinning_required = false
  allowed_actions      = "selected"
  allowed_actions_config {
    github_owned_allowed = true
    # These are the actions used in memes/terraform-google-f5-demo-bootstrap-template .github/workflow actions that are
    # not authored by GitHub.
    patterns_allowed = [
      "GoogleCloudPlatform/release-please-action@*",
      "google-github-actions/auth@*",
      "google-github-actions/create-cloud-deploy-release@*",
      "google-github-actions/setup-gcloud@*",
      "hashicorp/setup-terraform@*",
      "jaxxstorm/action-install-gh-release@*",
      "opentofu/setup-opentofu@*",
      "pre-commit/action@*",
      "terraform-linters/setup-tflint@*",
    ]
  }

  lifecycle {
    ignore_changes = [
      allowed_actions_config[0].patterns_allowed,
    ]
  }
}

resource "github_workflow_repository_permissions" "automation" {
  repository                       = github_repository.automation.name
  default_workflow_permissions     = "read"
  can_approve_pull_request_reviews = true
}


resource "github_actions_variable" "f5_ai_license" {
  for_each      = { for secret in module.f5_ai_license : "F5_AI_LICENSE_SECRET" => secret.id }
  repository    = github_repository.automation.name
  variable_name = each.key
  value         = each.value
}
