# Validate the module resources and outputs when Google Cloud related variables are modified from default.
#
# NOTE: This test only looks at GCP resources and outputs; see default.tftest.hcl for other assertions.
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
  mock_resource "github_repository" {
    defaults = {
      full_name = "mock/repo"
    }
  }
}

variables {
  name       = "var-gcp-variables-test"
  project_id = "mock-project-id"
}

# Setting gcp_options variable to null should result in same outputs as default value.
run "gcp_options_null" {
  variables {
    gcp_options = null
  }

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

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
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
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}

# Setting gcp_options variable to empty object should result in same outputs as default value.
run "gcp_options_empty" {
  variables {
    gcp_options = {}
  }

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

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
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
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}

run "gcp_options_disable_infra_manager" {
  variables {
    gcp_options = {
      enable_infra_manager = false
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) == 9
    error_message = "Expected 9 APIs to be enabled."
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
      "cloudbuild.googleapis.com",
      "clouddeploy.googleapis.com",
    ], k) && !v.disable_on_destroy && !v.disable_dependent_services])
    error_message = "Expected project to have enabled expected APIs."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = try(length(google_project_iam_member.infra_manager), 0) == 0
    error_message = "Expected no project roles bound for workload identities with infra_manager disabled attribute."
  }
  assert {
    condition = alltrue([for k, v in google_project_iam_member.infra_manager :
      can(regex("^principalSet://iam.googleapis.com/.*/attribute.infra_manager/enabled$", v.member)) &&
      contains([
        # Expected Infra Manager roles to bind to workload identities
      ], v.role)
    ])
    error_message = "Expected a Infra Manager project role bindings to workload identities matching pattern."
  }

  # Allow the right workload identities with appropriate Infra Manager attributes to act as IaC SA.
  assert {
    condition     = try(length(google_service_account_iam_member.iac_infra_manager), 0) == 0
    error_message = "Expected zero service account roles bound for workload identities with infra_manager enabled attribute."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.ar_sa"] == "'enabled'"
    error_message = "Expected GitHub OIDC provider to have ar_sa attribute set to 'enabled'."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.infra_manager"] == "'disabled'"
    error_message = "Expected GitHub OIDC provider to have infra_manager attribute set to 'disabled'."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.cloud_deploy"] == "'enabled'"
    error_message = "Expected GitHub OIDC provider to have cloud_deploy attribute set to 'enabled'."
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
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}
run "gcp_options_disable_cloud_deploy" {
  variables {
    gcp_options = {
      enable_cloud_deploy = false
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) == 8
    error_message = "Expected 8 APIs to be enabled."
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
    ], k) && !v.disable_on_destroy && !v.disable_dependent_services])
    error_message = "Expected project to have enabled expected APIs."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 0
    error_message = "Expected project to have enabled 0 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
    ] : google_project_service_identity.ids[api] != null])
    error_message = "Expected project to have enabled service identity for expected APIs."
  }

  # Cloud Deploy service account creation and role bindings (project and workload identity)
  assert {
    condition     = try(length(google_service_account.deploy), 0) == 0
    error_message = "Expected a Cloud Deploy SA to not be created."
  }
  assert {
    condition     = try(length(google_project_iam_member.deploy), 0) == 0
    error_message = "Expected Cloud Deploy SA to have a no project roles."
  }
  assert {
    condition = alltrue([for k, v in google_project_iam_member.deploy : contains([
      # Expected project role bindings
    ], v.role)])
    error_message = "Expected Cloud Deploy SA to have expected project roles."
  }

  # Workload Identity Pool creation and administrative role binding for IaC SA
  assert {
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = try(length(google_service_account_iam_member.deploy), 0) == 0
    error_message = "Expected no service account roles bound for workload identities with deploy_sa enabled attribute."
  }
  assert {
    condition = alltrue([for k, v in google_service_account_iam_member.deploy : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.deploy_sa/enabled$", v.member)
      ) && contains([
        # Expected Cloud Deploy SA impersonation roles to bind to workload identities
      ], v.role)
    ])
    error_message = "Expected Cloud Deploy SA impersonation role bindings to workload identities matching pattern."
  }

  # Allow the right workload identities with appropriate Cloud Deploy attributes to release deployments
  assert {
    condition     = try(length(google_project_iam_member.cloud_deploy), 0) == 0
    error_message = "Expected no service account roles bound for workload identities with deploy_sa enabled attribute."
  }
  assert {
    condition = alltrue([for k, v in google_project_iam_member.cloud_deploy : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.deploy_sa/enabled$", v.member)
      ) && contains([
        # Expected Cloud Deploy releaser roles
      ], v.role)
    ])
    error_message = "Expected Cloud Deploy releaser role bindings to workload identities matching pattern."
  }

  # Allow the right workload identities with appropriate Cloud Deploy attributes to act as Cloud Deploy SA
  assert {
    condition     = try(length(google_service_account_iam_member.deploy_cloud_deploy), 0) == 0
    error_message = "Expected no service account roles bound for workload identities with cloud_deploy enabled attribute."
  }
  assert {
    condition = alltrue([for k, v in google_service_account_iam_member.deploy_cloud_deploy : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.cloud_deploy/enabled$", v.member)
      ) && contains([
        # Expected Cloud Deploy act as roles
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = try(length(google_storage_bucket_iam_member.deploy), 0) == 0
    error_message = "Expected GCS bucket to have no role bindings."
  }
  assert {
    condition = alltrue([for k, v in google_storage_bucket_iam_member.deploy : contains([
      # Expected Cloud Deploy SA roles on state bucket
    ], v.role)])
    error_message = "Role bindings for Cloud Deploy SA on state bucket do not meet expectations."
  }

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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.ar_sa"] == "'enabled'"
    error_message = "Expected GitHub OIDC provider to have ar_sa attribute set to 'enabled'."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.infra_manager"] == "'enabled'"
    error_message = "Expected GitHub OIDC provider to have infra_manager attribute set to 'enabled'."
  }
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.attribute_mapping["attribute.cloud_deploy"] == "'disabled'"
    error_message = "Expected GitHub OIDC provider to have cloud_deploy attribute set to 'disabled'."
  }

  # GitHub conditional secrets and variables
  assert {
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_secret.deploy_sa), 0) == 0
    error_message = "Expected no GitHub secrets for Cloud Deploy SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 1
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) == 0
    error_message = "Expected deploy_sa output to be null or empty."
  }
}

run "gcp_options_services_disable_on_destroy" {
  variables {
    gcp_options = {
      services_disable_on_destroy = true
    }
  }

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
    ], k) && v.disable_on_destroy && !v.disable_dependent_services])
    error_message = "Expected project to have enabled expected APIs."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
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
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}

run "gcp_options_disable_dependent_services" {
  variables {
    gcp_options = {
      disable_dependent_services = true
    }
  }

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
    ], k) && !v.disable_on_destroy && v.disable_dependent_services])
    error_message = "Expected project to have enabled expected APIs."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
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
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}

run "gcp_options_create_state_bucket" {
  variables {
    gcp_options = {
      create_state_bucket = false
    }
  }

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

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
    condition     = try(length(google_storage_bucket.state), 0) == 0
    error_message = "Expected no GCS buckets for state."
  }
  assert {
    condition = alltrue([for k, v in google_storage_bucket.state :
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = try(length(google_storage_bucket_iam_member.deploy), 0) == 0
    error_message = "Expected GCS bucket to have no role bindings."
  }
  assert {
    condition = alltrue([for k, v in google_storage_bucket_iam_member.deploy : contains([
      # Expected Cloud Deploy SA roles on state bucket
    ], v.role)])
    error_message = "Role bindings for Cloud Deploy SA on state bucket do not meet expectations."
  }

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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
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
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) == 0
    error_message = "Expected state_bucket output to be null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}

run "gcp_options_ar_null" {
  variables {
    gcp_options = {
      ar = null
    }
  }

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

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
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
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}
run "gcp_options_ar_full" {
  variables {
    gcp_options = {
      ar = {
        location = "mock"
        oci      = true
        deb      = true
        rpm      = true
      }
    }
  }

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

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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

  # Repo creation
  assert {
    condition     = try(length(google_artifact_registry_repository.automation), 0) == 3
    error_message = "Expected three AR repos to be created."
  }
  assert {
    condition     = google_artifact_registry_repository.automation["oci"] != null
    error_message = "Expected OCI AR repo to be not null."
  }
  assert {
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "mock"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = google_artifact_registry_repository.automation["deb"] != null
    error_message = "Expected APT AR repo to be not null."
  }
  assert {
    condition     = google_artifact_registry_repository.automation["deb"].repository_id == "var-gcp-variables-test-deb" && google_artifact_registry_repository.automation["deb"].format == "APT" && google_artifact_registry_repository.automation["deb"].location == "mock"
    error_message = "Expected APT AR repo properties to match expectations."
  }
  assert {
    condition     = google_artifact_registry_repository.automation["rpm"] != null
    error_message = "Expected YUM AR repo to be not null."
  }
  assert {
    condition     = google_artifact_registry_repository.automation["rpm"].repository_id == "var-gcp-variables-test-rpm" && google_artifact_registry_repository.automation["rpm"].format == "YUM" && google_artifact_registry_repository.automation["rpm"].location == "mock"
    error_message = "Expected YUM AR repo properties to match expectations."
  }

  # Repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.iac), 0) == 3
    error_message = "Expected three IAM bindings for IaC SA on AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.iac : contains([
      # Expected AR role bindings for IaC SA
      "roles/artifactregistry.admin",
    ], v.role)])
    error_message = "Expected IaC SA to have expected AR repo roles."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 3
    error_message = "Expected three IAM bindings for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 3
    error_message = "Expected three IAM bindings for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_service_account.ar), 0) == 1
    error_message = "Expected a single AR SA to be created."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.ar), 0) == 3
    error_message = "Expected three IAM bindings for AR SA on repos."
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

  # GitHub integration with workload identity provider
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
    condition     = try(length(github_actions_variable.registry), 0) == 3
    error_message = "Expected three GitHub variables for AR repos."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["DEB_REGISTRY"].variable_name == "DEB_REGISTRY"
    error_message = "Expected GitHub variable named 'DEB_REGISTRY' for APT AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["RPM_REGISTRY"].variable_name == "RPM_REGISTRY"
    error_message = "Expected GitHub variable named 'RPM_REGISTRY' for YUM AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 3
    error_message = "Expected registries output to have three entries."
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
    condition     = output.registries["deb"] != null
    error_message = "Expected registries output for key 'deb' to be not null."
  }
  assert {
    condition     = try(length(output.registries["deb"].project), 0) > 0
    error_message = "Expected registries output for key 'deb' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["deb"].location), 0) > 0
    error_message = "Expected registries output for key 'deb' to be not null or empty."
  }
  assert {
    condition     = output.registries["rpm"] != null
    error_message = "Expected registries output for key 'rpm' to be not null."
  }
  assert {
    condition     = try(length(output.registries["rpm"].project), 0) > 0
    error_message = "Expected registries output for key 'rpm' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["rpm"].location), 0) > 0
    error_message = "Expected registries output for key 'rpm' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 3
    error_message = "Expected repo_identifiers output to have a single entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["deb"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'deb' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["rpm"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'rpm' to be not null or empty."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}


run "state_bucket_options_null" {
  variables {
    state_bucket_options = null
  }

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

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
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
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}

run "state_bucket_options_empty" {
  variables {
    state_bucket_options = {}
  }

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

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) == 2
    error_message = "Expected project to have enabled 2 service identities."
  }
  assert {
    condition = alltrue([for api in [
      # Expected APIs with required service identities
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
    condition     = google_iam_workload_identity_pool.bots.workload_identity_pool_id == "var-gcp-variables-test-bots"
    error_message = "Expected Workload Identity Pool for bots to have workload_identity_pool_id of 'var-gcp-variables-test-bots'."
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
    condition     = alltrue([for k, v in google_kms_key_ring.automation : v.name == "var-gcp-variables-test-automation" && v.location == "global"])
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
    condition     = alltrue([for k, v in google_kms_crypto_key.sops : v.name == "var-gcp-variables-test-sops"])
    error_message = "Expected KMS sops key properties to match."
  }

  # KMS key for bucket encryption
  assert {
    condition     = try(length(google_kms_crypto_key.gcs), 0) == 0
    error_message = "Expected no KMS GCS keys to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_kms_crypto_key.gcs : v.name == "var-gcp-variables-test-gcs"])
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
      v.name == "var-gcp-variables-test-automation" &&
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-gcp-variables-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
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
    condition     = try(length(google_artifact_registry_repository_iam_member.reader), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR readers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.reader : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/reader$", v.member)
      ) && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to workload identities matching pattern."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.writer), 0) == 1
    error_message = "Expected a single IAM binding for Workload Identity AR writers on repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.writer : can(
      regex("^principalSet://iam.googleapis.com/.*/attribute.artifact_registry/writer$", v.member)
      ) && contains([
        # Expected AR roles for writers
        "roles/artifactregistry.writer",
      ], v.role)
    ])
    error_message = "Expected AR writer role bindings to workload identities matching pattern."
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

  # GitHub integration with workload identity provider
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
    error_message = "Expected a GitHub variable for a single AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
  assert {
    condition     = try(length(output.state_bucket), 0) > 0
    error_message = "Expected state_bucket output to be not null or empty."
  }
  assert {
    condition     = length(output.registries) == 1
    error_message = "Expected registries output to have a single entry."
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
    condition     = try(length(output.workload_identity_pool_id), 0) > 0
    error_message = "Expected workload_identity_pool_id output to be not null or empty."
  }
  assert {
    condition     = try(length(output.deploy_sa), 0) > 0
    error_message = "Expected deploy_sa output to be not null or empty."
  }
}
