# Validate the module resources and outputs when default values are used.
mock_provider "google" {
  mock_data "google_storage_project_service_account" {
    defaults = {
      member = "serviceAccount:service-1234567890@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
  mock_resource "google_service_account" {
    defaults = {
      name   = "projects/mock-project-id/serviceAccounts/test-sa@mock-project-id.iam.gserviceaccount.com"
      email  = "test-sa@mock-project-id.iam.gserviceaccount.com"
      member = "serviceAccount:test-sa@mock-project-id.iam.gserviceaccount.com"
    }
  }
}
mock_provider "google-beta" {}
mock_provider "github" {
  mock_data "github_user" {
    defaults = {
      login = "mock_user"
      id    = "11111"
    }
  }
  mock_data "github_organization" {
    defaults = {
      login = "mock_org"
      id    = "22222"
    }
  }
  mock_resource "github_repository" {
    defaults = {
      full_name = "mock/repo"
      repo_id   = "33333"
    }
  }
}

variables {
  name       = "default-test"
  project_id = "mock-project-id"
}

# Assert resources in main.tf
run "main" {
  # API enablement
  assert {
    condition     = length(google_project_service.apis) == 10
    error_message = "Expected 10 APIs to be enabled."
  }
  assert {
    condition = alltrue([for k, v in google_project_service.apis : contains([
      # Expected APIs to be enabled
      "artifactregistry.googleapis.com",
      "containerscanning.googleapis.com",
      "iam.googleapis.com",
      "iamcredentials.googleapis.com",
      "serviceusage.googleapis.com",
      "storage-api.googleapis.com",
      "sts.googleapis.com",
      "config.googleapis.com",
      "cloudbuild.googleapis.com",
      "clouddeploy.googleapis.com",
    ], k) && !v.disable_on_destroy && !v.disable_dependent_services])
    error_message = "Expected project to have enabled expected APIs."
  }
  assert {
    condition     = google_service_account.iac.account_id == "default-test-iac"
    error_message = "Expected IaC SA to have account_id 'default-test-iac'."
  }

  # IaC impersonation
  assert {
    condition     = try(length(google_service_account_iam_member.iac_impersonation), 0) == 0
    error_message = "Expected IaC SA to have no impersonator roles bound."
  }
  assert {
    condition = alltrue([for k, v in google_service_account_iam_member.iac_impersonation : contains([
      # Expected roles
      "roles/iam.serviceAccountTokenCreator",
      "roles/iam.serviceAccountUser",
      ], v.role) && contains([
      # Expected members
    ], v.member)])
    error_message = "Expected IaC service account impersonation role bindings."
  }

  # IaC project roles
  assert {
    condition     = try(length(google_project_iam_member.iac), 0) == 1
    error_message = "Expected IaC SA to have a single project role."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 3
    error_message = "Expected project to have enabled 3 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
      "artifactregistry.googleapis.com",
      "cloudbuild.googleapis.com",
      "clouddeploy.googleapis.com",
    ] : google_project_service_identity.ids[api] != null])
    error_message = "Expected project to have enabled service identity for expected APIs."
  }

  # Cloud Deploy service account creation and role bindings (project and workload identity)
  assert {
    condition     = try(length(google_service_account.deploy), 0) == 1
    error_message = "Expected a single Cloud Deploy SA to be created."
  }
  assert {
    condition     = try(length(google_project_iam_member.deploy), 0) == 1
    error_message = "Expected Cloud Deploy SA to have a single project role."
  }
  assert {
    condition = alltrue([for k, v in google_project_iam_member.deploy : contains([
      # Expected project role bindings
      "roles/clouddeploy.jobRunner",
    ], v.role)])
    error_message = "Expected Cloud Deploy SA to have expected project roles."
  }

  # Workload Identity Pool creation and administrative role binding for IaC SA
  assert {
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "default-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'default-test-bots'."
  }
  assert {
    condition     = try(length(google_iam_workload_identity_pool_iam_member.iac), 0) == 0
    error_message = "Expected IaC SA not to have Workload Identity Pool admin role."
  }
  assert {
    condition = alltrue([for k, v in google_iam_workload_identity_pool_iam_member.iac : contains([
      # Expected Workload Identity Pool roles if admin is enabled
      "roles/iam.workloadIdentityPoolAdmin",
    ], v.role)])
    error_message = "Expected IaC SA admin role assignments on Workload Identity Pool."
  }

  # Allow the right workload identities with appropriate attributes to impersonate IaC SA
  assert {
    condition = can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.iac_sa/enabled$", google_service_account_iam_member.iac.member)
      ) && contains([
        # Expected IaC impersonation roles to bind to workload identities
        "roles/iam.workloadIdentityUser",
    ], google_service_account_iam_member.iac.role)
    error_message = "Expected IaC impersonation role bindings to workload identities matching pattern."
  }

  # Allow the right workload identities with appropriate attributes to manage Infra Manager
  assert {
    condition     = try(length(google_project_iam_member.infra_manager), 0) == 1
    error_message = "Expected a single project role bound for workload identities with infra_manager enabled attribute."
  }
  assert {
    condition = alltrue([for k, v in google_project_iam_member.infra_manager :
      can(regex("^principalSet://iam.googleapis.com/.*/attribute.infra_manager/enabled$", v.member)) &&
      contains([
        # Expected Infra Manager roles to bind to workload identities
        "roles/config.admin",
      ], v.role)
    ])
    error_message = "Expected a Infra Manager project role bindings to workload identities matching pattern."
  }

  # Allow the right workload identities with appropriate Infra Manager attributes to act as IaC SA.
  assert {
    condition     = try(length(google_service_account_iam_member.iac_infra_manager), 0) == 1
    error_message = "Expected a single service account role bound for workload identities with infra_manager enabled attribute."
  }
  assert {
    condition = alltrue([for k, v in google_service_account_iam_member.iac_infra_manager :
      can(regex("^principalSet://iam.googleapis.com/.*/attribute.infra_manager/enabled$", v.member)) &&
      contains([
        # Expected IaC SA user role
        "roles/iam.serviceAccountUser",
    ], v.role)])
    error_message = "Expected IaC Service Account user role to be bound to workload identities matching pattern."
  }

  # Allow the right workload identities with appropriate Cloud Deploy attributes to impersonate Cloud Deploy SA
  assert {
    condition     = try(length(google_service_account_iam_member.deploy), 0) == 1
    error_message = "Expected a single service account role bound for workload identities with deploy_sa enabled attribute."
  }
  assert {
    condition = alltrue([for k, v in google_service_account_iam_member.deploy : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.deploy_sa/enabled$", v.member)
      ) && contains([
        # Expected Cloud Deploy SA impersonation roles to bind to workload identities
        "roles/iam.workloadIdentityUser",
      ], v.role)
    ])
    error_message = "Expected Cloud Deploy SA impersonation role bindings to workload identities matching pattern."
  }

  # Allow the right workload identities with appropriate Cloud Deploy attributes to release deployments
  assert {
    condition     = try(length(google_project_iam_member.cloud_deploy), 0) == 1
    error_message = "Expected a single service account role bound for workload identities with deploy_sa enabled attribute."
  }
  assert {
    condition = alltrue([for k, v in google_project_iam_member.cloud_deploy : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.deploy_sa/enabled$", v.member)
      ) && contains([
        # Expected Cloud Deploy releaser roles
        "roles/clouddeploy.releaser",
      ], v.role)
    ])
    error_message = "Expected Cloud Deploy releaser role bindings to workload identities matching pattern."
  }

  # Allow the right workload identities with appropriate Cloud Deploy attributes to act as Cloud Deploy SA
  assert {
    condition     = try(length(google_service_account_iam_member.deploy_cloud_deploy), 0) == 1
    error_message = "Expected a single service account role bound for workload identities with cloud_deploy enabled attribute."
  }
  assert {
    condition = alltrue([for k, v in google_service_account_iam_member.deploy_cloud_deploy : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.cloud_deploy/enabled$", v.member)
      ) && contains([
        # Expected Cloud Deploy act as roles
        "roles/iam.serviceAccountUser",
      ], v.role)
    ])
    error_message = "Expected Cloud Deploy act as role bindings to workload identities matching pattern."
  }

  # KMS keyring
  assert {
    condition     = try(length(google_kms_key_ring.automation), 0) == 0
    error_message = "Expected no KMS key rings to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "default-test-automation" && v.location == "global"])
    error_message = "Expected KMS keyring properties to match."
  }
  assert {
    condition     = try(length(google_kms_key_ring_iam_member.iac), 0) == 0
    error_message = "Expected no role bindings for IaC SA on keyring."
  }
  assert {
    condition = alltrue([for k, v in google_kms_key_ring_iam_member.iac : contains([
      # Expected KMS roles for IaC
      "roles/cloudkms.cryptoKeyEncrypterDecrypter",
      ], v.role)
    ])
    error_message = "Expected IaC SA role bindings to KMS keyring to match."
  }

  # KMS key for SOPs
  assert {
    condition     = try(length(google_kms_crypto_key.sops), 0) == 0
    error_message = "Expected no KMS sops keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "default-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "default-test-gcs"])
    error_message = "Expected KMS GCS key properties to match."
  }
  assert {
    condition     = try(length(google_kms_crypto_key_iam_member.gcs), 0) == 0
    error_message = "Expected no role bindings for project GCS service account on GCS key."
  }
  assert {
    condition = alltrue([for k, v in google_kms_crypto_key_iam_member.gcs : contains([
      # Expected KMS roles for project GCS SA
      "roles/cloudkms.cryptoKeyEncrypterDecrypter",
      ], v.role)
    ])
    error_message = "Expected project GCS SA role bindings to KMS key to match."
  }

  # State bucket and IAM for access for Cloud Deploy
  assert {
    condition     = try(length(google_storage_bucket.state), 0) == 1
    error_message = "Expected a single GCS bucket for state."
  }
  assert {
    condition = alltrue([for k, v in google_storage_bucket.state :
      v.name == "default-test-automation" &&
      v.force_destroy &&
      v.location == "US" &&
      v.storage_class == "STANDARD" &&
      v.uniform_bucket_level_access &&
      v.versioning[0].enabled &&
      try(length(v.encryption), 0) == 0
    ])
    error_message = "Expected GCS bucket properties to match expectations."
  }
  assert {
    condition     = try(length(google_storage_bucket_iam_member.deploy), 0) == 2
    error_message = "Expected GCS bucket to have two role bindings."
  }
  assert {
    condition = alltrue([for k, v in google_storage_bucket_iam_member.deploy : contains([
      # Expected Cloud Deploy SA roles on state bucket
      "roles/storage.objectViewer",
      "roles/storage.objectCreator",
    ], v.role)])
    error_message = "Role bindings for Cloud Deploy SA on state bucket do not meet expectations."
  }
}

# Assert resources in ar.tf
run "ar" {
  # Repo creation
  assert {
    condition     = try(length(google_artifact_registry_repository.automation), 0) == 1
    error_message = "Expected a single AR repo to be created."
  }
  assert {
    condition     = google_artifact_registry_repository.automation["oci"] != null
    error_message = "Expected OCI AR repo to be not null."
  }
  assert {
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "default-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repository for private NGINX."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repository for private F5 AI."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual repositories for Docker."
  }

  # Repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.iac), 0) == 1
    error_message = "Expected a single IAM binding for IaC SA on AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.iac : contains([
      # Expected AR role bindings for IaC SA
      "roles/artifactregistry.admin",
    ], v.role)])
    error_message = "Expected IaC SA to have expected AR repo roles."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.automation_reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.automation_reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.automation_writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.automation_writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern on automation repos."
  }
  assert {
    condition     = try(length(google_service_account.ar), 0) == 1
    error_message = "Expected a single AR SA to be created."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.ar), 0) == 1
    error_message = "Expected a single IAM binding for AR SA on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.ar : contains([
      # Expected AR repo bindings for AR SA
      "roles/artifactregistry.writer",
    ], v.role)])
    error_message = "Expected AR SA to have expected AR roles."
  }
  assert {
    condition     = try(length(google_service_account_iam_member.ar), 0) == 1
    error_message = "Expected a single IAM binding for AR SA on repos."
  }
  assert {
    condition = alltrue([for k, v in google_service_account_iam_member.ar : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.ar_sa/enabled$", v.member)
      ) && contains([
        # Expected act as IAM roles for workload identities with ar_sa enabled
        "roles/iam.workloadIdentityUser",
      ], v.role)
    ])
    error_message = "Expected AR SA act as role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.virtual_reader), 0) == 0
    error_message = "Expected no IAM bindings for Workload Identity AR readers on virtual repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.virtual_reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern on virtual repos."
  }
}

# Assert resources in github.tf
run "github" {
  # Github repo
  assert {
    condition     = github_repository.automation.name == "default-test"
    error_message = "Expected GitHub repo name to be 'default-test'."
  }
  assert {
    condition     = github_repository.automation.description == "Bootstrapped automation repository"
    error_message = "Expected GitHub repo description to be 'Bootstrapped automation repository'."
  }
  assert {
    condition     = github_repository.automation.visibility == "public"
    error_message = "Expected GitHub repo to have public visibility."
  }
  assert {
    condition     = github_repository.automation.archive_on_destroy
    error_message = "Expected GitHub repo to have archive_on_destroy set as true."
  }
  assert {
    condition     = try(length(github_repository.automation.template), 0) == 1
    error_message = "Expected GitHub repo to use a single template."
  }
  assert {
    condition = alltrue([for template in github_repository.automation.template :
      template.owner == "memes" &&
      template.repository == "terraform-google-f5-demo-bootstrap-template" &&
      !template.include_all_branches
    ])
    error_message = "Expected GitHub repo template properties to meet expectations."
  }

  # Collaborators
  assert {
    condition     = try(length(github_repository_collaborator.collaborators), 0) == 0
    error_message = "Expected GitHub repo to not have collaborators."
  }
  assert {
    condition = alltrue([for collaborator in github_repository_collaborator.collaborators : contains([
      # Expected set of collaborators
    ], collaborator.username) && collaborator.permission == "push"])
    error_message = "Expected GitHub repo collaborators did not match."
  }

  # SSH deploy key
  assert {
    condition     = try(length(tls_private_key.automation), 0) == 0
    error_message = "Expected no SSH key for GitHub deployments."
  }
  assert {
    condition     = try(length(github_repository_deploy_key.automation), 0) == 0
    error_message = "Expected GitHub repo to have no SSH deploy keys."
  }

  # Workload identity provider
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "default-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'default-test-gh'."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.ar_sa"] == "'enabled'"
    error_message = "Expected GitHub OIDC provider to have ar_sa attribute set to 'enabled'."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.infra_manager"] == "'enabled'"
    error_message = "Expected GitHub OIDC provider to have infra_manager attribute set to 'enabled'."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.cloud_deploy"] == "'enabled'"
    error_message = "Expected GitHub OIDC provider to have cloud_deploy attribute set to 'enabled'."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/default-test@33333:')"
    error_message = "Expected GitHub OIDC provider attribute_condition does not meet expectations."
  }

  # GitHub conditional secrets and variables
  assert {
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_secret.deploy_sa), 0) == 1
    error_message = "Expected a GitHub secret for Cloud Deploy SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 1
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = try(length(github_actions_variable.nginx_jwt), 0) == 0
    error_message = "Expected no GitHub variables for NGINX JWT secret."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.nginx_jwt : v.variable_name == "NGINX_JWT_SECRET"])
    error_message = "Expected GitHub variable for NGINX JWT to be named 'NGINX_JWT_SECRET'."
  }
  assert {
    condition     = try(length(github_actions_variable.f5_ai_license), 0) == 0
    error_message = "Expected no GitHub variables for F5 AI license secret."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.f5_ai_license : v.variable_name == "F5_AI_LICENSE_SECRET"])
    error_message = "Expected GitHub variable for F5 AI license to be named 'F5_AI_LICENSE_SECRET'."
  }

  # Actions permissions
  assert {
    condition     = github_actions_repository_permissions.automation.enabled
    error_message = "Expected GitHub actions to be enabled in repo."
  }
  assert {
    condition     = !github_actions_repository_permissions.automation.sha_pinning_required
    error_message = "Expected GitHub actions to NOT require SHA pinning."
  }
  assert {
    condition = (
      github_actions_repository_permissions.automation.allowed_actions == "selected" &&
      try(length(github_actions_repository_permissions.automation.allowed_actions_config), 0) == 1
    )
    error_message = "Expected GitHub allowed repo actions to be configured with 1 config set."
  }
  assert {
    condition = alltrue([for config in github_actions_repository_permissions.automation.allowed_actions_config :
      try(length(config.patterns_allowed), 0) > 0 &&
      alltrue([for allowed in config.patterns_allowed : contains([
        "GoogleCloudPlatform/release-please-action@*",
        "google-github-actions/auth@*",
        "google-github-actions/create-cloud-deploy-release@*",
        "google-github-actions/setup-gcloud@*",
        "hashicorp/setup-terraform@*",
        "jaxxstorm/action-install-gh-release@*",
        "opentofu/setup-opentofu@*",
        "pre-commit/action@*",
        "terraform-linters/setup-tflint@*",
      ], allowed)])
    ])
    error_message = "Expected GitHub allowed repo actions patterns to meet expectations, got '${jsonencode(github_actions_repository_permissions.automation.allowed_actions_config.*.patterns_allowed)}."
  }

  # Workflow permissions
  assert {
    condition     = github_workflow_repository_permissions.automation.default_workflow_permissions == "read"
    error_message = "Expected GitHub workflow permissions for GITHUB_TOKEN to be 'read', got '${github_workflow_repository_permissions.automation.default_workflow_permissions}'."
  }
  assert {
    condition     = github_workflow_repository_permissions.automation.can_approve_pull_request_reviews
    error_message = "Expected GitHub workflow permissions to allow PR creation and approval."
  }
}

# Assert resources in outputs.tf
run "outputs" {
  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have one entry."
  }
  assert {
    condition     = output.registries["oci"] != null
    error_message = "Expected registries output for key 'oci' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci"].project), 0) > 0
    error_message = "Expected registries output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci"].location), 0) > 0
    error_message = "Expected registries output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 1
    error_message = "Expected repo_identifiers output to have a single entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = output.sops_kms_id == null
    error_message = "Expected sops_kms_id output to be null."
  }
  assert {
    condition     = try(length(output.iac_sa), 0) > 0
    error_message = "Expected iac_sa output to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }
  assert {
    condition     = try(length(output.html_url), 0) > 0
    error_message = "Expected html_url output to be not null or empty."
  }
  assert {
    condition     = try(length(output.http_clone_url), 0) > 0
    error_message = "Expected http_clone_url output to be not null or empty."

  }
  assert {
    condition     = try(length(output.ssh_clone_url), 0) > 0
    error_message = "Expected http_clone_url output to be not null or empty."
  }
  assert {
    condition     = output.deploy_public_key == null
    error_message = "Expected deploy_public_key output to be null."
  }
  assert {
    condition     = output.deploy_private_key == null
    error_message = "Expected deploy_private_key output to be null."
  }
  assert {
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
  assert {
    condition     = output.nginx_jwt != null
    error_message = "Expected nginx_jwt output to be not null."
  }
  assert {
    condition     = output.nginx_jwt.secret_id == null
    error_message = "Expected nginx_jwt output field secret_id to be null."
  }
  assert {
    condition     = output.nginx_jwt.id == null
    error_message = "Expected nginx_jwt output field id to be null."
  }
  assert {
    condition     = output.f5_ai_license != null
    error_message = "Expected f5_ai_license output to be not null."
  }
  assert {
    condition     = output.f5_ai_license.secret_id == null
    error_message = "Expected f5_ai_license output field secret_id to be null."
  }
  assert {
    condition     = output.f5_ai_license.id == null
    error_message = "Expected f5_ai_license output field id to be null."
  }
}

# Assert resources in secrets.tf
run "secrets" {
  assert {
    condition     = try(length(google_secret_manager_secret.nginx_jwt), 0) == 0
    error_message = "Expected no NGINX JWT secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.nginx_jwt : v.secret_id == "default-test-nginx-jwt"])
    error_message = "Expected NGINX JWT secret name to be 'default-test-nginx-jwt'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "default-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'default-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "default-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'default-test-upstream-oci-password-f5-ai'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.f5_ai_license), 0) == 0
    error_message = "Expected no F5 AI license secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.f5_ai_license : v.secret_id == "default-test-f5-ai-license"])
    error_message = "Expected F5 AI license secret name to be 'default-test-f5-ai-license'."
  }
}
