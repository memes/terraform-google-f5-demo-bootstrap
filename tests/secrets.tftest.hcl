# Validate the module resources and outputs when the secrets variable is set.
#
# NOTE: This test only looks at resource and outputs related to secrets.
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
  name       = "var-secrets-test"
  project_id = "mock-project-id"
}

# Setting secrets variable to empty should result in same outputs as default value.
run "empty" {
  variables {
    secrets = {}
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

  # GitHub conditional secrets and variables
  assert {
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # Outputs
  assert {
    condition     = try(length(output.secrets), 0) == 0
    error_message = "Expected secrets e output to be empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.secrets), 0) == 0
    error_message = "Expected no additional secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.secrets : startswith(v.secret_id, "var-secrets-test-")])
    error_message = "Expected additional secret names to start with 'var-secrets-test-'."
  }
}

run "null_value" {
  variables {
    secrets = {
      "mock-secret" = null
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

  # GitHub conditional secrets and variables
  assert {
    condition     = try(length(github_actions_variable.secrets), 0) == 1
    error_message = "Expected one GitHub variable for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # Outputs
  assert {
    condition     = try(length(output.secrets), 0) == 1
    error_message = "Expected secrets output to have one entry."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.secrets), 0) == 1
    error_message = "Expected one additional secret to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.secrets : startswith(v.secret_id, "var-secrets-test-")])
    error_message = "Expected additional secret names to start with 'var-secrets-test-'."
  }
}

run "empty_value" {
  variables {
    secrets = {
      "mock-secret" = ""
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

  # GitHub conditional secrets and variables
  assert {
    condition     = try(length(github_actions_variable.secrets), 0) == 1
    error_message = "Expected one GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # Outputs
  assert {
    condition     = try(length(output.secrets), 0) == 1
    error_message = "Expected secrets output to have one entry."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.secrets), 0) == 1
    error_message = "Expected one additional secret to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.secrets : startswith(v.secret_id, "var-secrets-test-")])
    error_message = "Expected additional secret names to start with 'var-secrets-test-'."
  }
}

run "value" {
  variables {
    secrets = {
      "mock-secret" = "secret"
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

  # GitHub conditional secrets and variables
  assert {
    condition     = try(length(github_actions_variable.secrets), 0) == 1
    error_message = "Expected one GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # Outputs
  assert {
    condition     = try(length(output.secrets), 0) == 1
    error_message = "Expected secrets output to have one entry."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.secrets), 0) == 1
    error_message = "Expected one additional secret to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.secrets : startswith(v.secret_id, "var-secrets-test-")])
    error_message = "Expected additional secret names to start with 'var-secrets-test-'."
  }
}

run "multi_value" {
  variables {
    secrets = {
      "mock-secret"       = "secret"
      "mock-extra-secret" = null
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

  # GitHub conditional secrets and variables
  assert {
    condition     = try(length(github_actions_variable.secrets), 0) == 2
    error_message = "Expected two GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # Outputs
  assert {
    condition     = try(length(output.secrets), 0) == 2
    error_message = "Expected secrets output to have two entries."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.secrets), 0) == 2
    error_message = "Expected two additional secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.secrets : startswith(v.secret_id, "var-secrets-test-")])
    error_message = "Expected additional secret names to start with 'var-secrets-test-'."
  }
}
