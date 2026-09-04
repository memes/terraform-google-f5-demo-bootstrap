# Validate the module resources and outputs when f5_ai_repo_credentials variables are modified from default.
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
mock_provider "google-beta" {
  mock_resource "google_project_service_identity" {
    defaults = {
      member = "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com"
    }
  }
}
mock_provider "github" {
  mock_resource "github_repository" {
    defaults = {
      full_name = "mock/repo"
    }
  }
}

variables {
  name       = "var-f5-ai-repo-test"
  project_id = "mock-project-id"
}

run "valid" {
  variables {
    f5_ai_repo_credentials = {
      username = "dummy-f5-ai-user"
      password = "dummy-f5-ai-password"
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) == 11
    error_message = "Expected 11 APIs to be enabled."
  }
  assert {
    condition = alltrue([for k, v in google_project_service.apis : contains([
      # Expected APIs to be enabled
      "artifactregistry.googleapis.com",
      "containerscanning.googleapis.com",
      "iam.googleapis.com",
      "iamcredentials.googleapis.com",
      "secretmanager.googleapis.com",
      "serviceusage.googleapis.com",
      "storage-api.googleapis.com",
      "sts.googleapis.com",
      "config.googleapis.com",
      "cloudbuild.googleapis.com",
      "clouddeploy.googleapis.com",
    ], k) && !v.disable_on_destroy && !v.disable_dependent_services])
    error_message = "Expected project to have enabled expected APIs."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-f5-ai-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repos for NGINX private repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 1
    error_message = "Expected one upstream repo for F5 AI private repo"
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
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

  # GitHub conditional secrets and variables
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 2
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_F5_AI_REGISTRY"].variable_name == "OCI_F5_AI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_F5_AI_REGISTRY' for upstream F5 AI OCI AR repo."
  }

  # Outputs
  assert {
    condition     = length(output.registries) == 2
    error_message = "Expected registries output to have two entries."
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
    condition     = output.registries["oci-f5-ai"] != null
    error_message = "Expected registries output for key 'oci-f5-ai' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-f5-ai"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-f5-ai' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-f5-ai"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-f5-ai' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 2
    error_message = "Expected repo_identifiers output to have a single entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-f5-ai"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-f5-ai' to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.nginx_jwt), 0) == 0
    error_message = "Expected no NGINX JWT secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.nginx_jwt : v.secret_id == "var-f5-ai-repo-test-f5-ai-nginx-jwt"])
    error_message = "Expected NGINX JWT secret name to be 'var-f5-ai-repo-credentials-test-nginx-jwt'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-f5-ai-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-f5-ai-repo-credentials-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 1
    error_message = "Expected one upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-f5-ai-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-f5-ai-repo-credentials-test-upstream-oci-password-f5-ai'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.secrets), 0) == 0
    error_message = "Expected no additional secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.secrets : startswith(v.secret_id, "var-f5-ai-repo-test-")])
    error_message = "Expected additional secret names to start with 'var-f5-ai-repo-credentials-test-'."
  }
}
