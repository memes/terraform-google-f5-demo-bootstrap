# Validate the module resources and outputs for repos variable combinations.
#
# NOTE: This test only looks at select resources and outputs; see default.tftest.hcl for other assertions.
mock_provider "google" {
  mock_data "google_storage_project_service_account" {
    defaults = {
      member = "serviceAccount:service-1234567890@gs-project-accounts.iam.gserviceaccount.com"
    }
  }
  mock_data "google_artifact_registry_repository.upstream_ar" {
    defaults = {
      repository_id = "mock-repo"
      location      = "mock-location1"
      project       = "mock-project-id"
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
  name       = "var-virtual-repo-test"
  project_id = "mock-project-id"
}

run "null" {
  variables {
    virtual_repo = null
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 1
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
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
    error_message = "Expected repo_identifiers output to have one entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "empty" {
  variables {
    virtual_repo = {}
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 1
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
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
    error_message = "Expected repo_identifiers output to have one entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "disabled" {
  variables {
    virtual_repo = {
      enable = false
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 1
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
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
    error_message = "Expected repo_identifiers output to have one entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "enabled" {
  variables {
    virtual_repo = {
      enable = true
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 1
    error_message = "Expected one virtual Docker repository."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.virtual_reader), 0) == 1
    error_message = "Expected one IAM binding for Workload Identity AR readers on virtual repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 2
    error_message = "Expected a GitHub variable for two AR repos."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_VIRT_REGISTRY"].variable_name == "OCI_VIRT_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_VIRT_REGISTRY' for OCI virtual AR repo."
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
    condition     = output.registries["oci-virt"] != null
    error_message = "Expected registries output for key 'oci-virt' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 2
    error_message = "Expected repo_identifiers output to have two entries."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-virt"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "disabled_docker_hub_disabled" {
  variables {
    virtual_repo = {
      docker_hub = false
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 1
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
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
    error_message = "Expected repo_identifiers output to have one entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "disabled_docker_hub_enabled" {
  variables {
    virtual_repo = {
      docker_hub = true
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 1
    error_message = "Expected one upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 2
    error_message = "Expected a GitHub variable for two AR repos."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_DOCKER_HUB_REGISTRY"].variable_name == "OCI_DOCKER_HUB_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_DOCKER_HUB_REGISTRY' for OCI upstream docker hub AR repo."
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
    condition     = output.registries["oci-docker-hub"] != null
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-docker-hub"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-docker-hub"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 2
    error_message = "Expected repo_identifiers output to have one entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-docker-hub"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "enabled_docker_hub_enabled" {
  variables {
    virtual_repo = {
      enable     = true
      docker_hub = true
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 1
    error_message = "Expected one upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 1
    error_message = "Expected one virtual Docker repository."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 2
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 1
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.virtual_reader), 0) == 1
    error_message = "Expected one IAM binding for Workload Identity AR readers on virtual repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 3
    error_message = "Expected a GitHub variable for two AR repos."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_VIRT_REGISTRY"].variable_name == "OCI_VIRT_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_VIRT_REGISTRY' for OCI virtual AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_DOCKER_HUB_REGISTRY"].variable_name == "OCI_DOCKER_HUB_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_DOCKER_HUB_REGISTRY' for OCI upstream docker hub AR repo."
  }

  # Outputs
  assert {
    condition     = length(output.registries) == 3
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
    condition     = output.registries["oci-virt"] != null
    error_message = "Expected registries output for key 'oci-virt' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = output.registries["oci-docker-hub"] != null
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-docker-hub"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-docker-hub"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 3
    error_message = "Expected repo_identifiers output to have three entries."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-virt"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-docker-hub"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "disabled_ar_repos_null" {
  variables {
    virtual_repo = {
      ar_repos = null
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 1
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
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
    error_message = "Expected repo_identifiers output to have one entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "enabled_ar_repos_null" {
  variables {
    virtual_repo = {
      enable   = true
      ar_repos = null
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 1
    error_message = "Expected one virtual Docker repository."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.virtual_reader), 0) == 1
    error_message = "Expected one IAM binding for Workload Identity AR readers on virtual repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 2
    error_message = "Expected a GitHub variable for two AR repos."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_VIRT_REGISTRY"].variable_name == "OCI_VIRT_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_VIRT_REGISTRY' for OCI virtual AR repo."
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
    condition     = output.registries["oci-virt"] != null
    error_message = "Expected registries output for key 'oci-virt' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 2
    error_message = "Expected repo_identifiers output to have two entries."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-virt"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "disabled_ar_repos_empty" {
  variables {
    virtual_repo = {
      ar_repos = []
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 1
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
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
    error_message = "Expected repo_identifiers output to have one entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "enabled_ar_repos_empty" {
  variables {
    virtual_repo = {
      enable   = true
      ar_repos = []
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 1
    error_message = "Expected one virtual Docker repository."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.virtual_reader), 0) == 1
    error_message = "Expected one IAM binding for Workload Identity AR readers on virtual repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 2
    error_message = "Expected a GitHub variable for two AR repos."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_VIRT_REGISTRY"].variable_name == "OCI_VIRT_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_VIRT_REGISTRY' for OCI virtual AR repo."
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
    condition     = output.registries["oci-virt"] != null
    error_message = "Expected registries output for key 'oci-virt' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 2
    error_message = "Expected repo_identifiers output to have two entries."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-virt"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "disabled_ar_repos_valid" {
  variables {
    virtual_repo = {
      ar_repos = [
        "mock-location1-docker.pkg.dev/mock-project-id/mock-repo",
      ]
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 1
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }

  # Outputs
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
    error_message = "Expected repo_identifiers output to have one entry."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "enabled_ar_repos_valid" {
  variables {
    virtual_repo = {
      enable = true
      ar_repos = [
        "mock-location1-docker.pkg.dev/mock-project-id/mock-repo",
      ]
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 1
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 2
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 1
    error_message = "Expected one IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.virtual_reader), 0) == 1
    error_message = "Expected one IAM binding for Workload Identity AR readers on virtual repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 2
    error_message = "Expected a GitHub variable for one AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_VIRT_REGISTRY"].variable_name == "OCI_VIRT_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_VIRT_REGISTRY' for OCI virtual AR repo."
  }

  # Outputs
  assert {
    condition     = length(output.registries) == 2
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
    condition     = output.registries["oci-virt"] != null
    error_message = "Expected registries output for key 'oci-virt' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 2
    error_message = "Expected repo_identifiers output to have two entries."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-virt"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "full" {
  variables {
    virtual_repo = {
      enable     = true
      docker_hub = true
      ar_repos = [
        "mock-location1-docker.pkg.dev/mock-project-id/mock-repo",
      ]
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 1
    error_message = "Expected one upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 1
    error_message = "Expected one virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 3
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 1
    error_message = "Expected one IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.virtual_reader), 0) == 1
    error_message = "Expected one IAM binding for Workload Identity AR readers on virtual repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 3
    error_message = "Expected a GitHub variable for two AR repos."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_DOCKER_HUB_REGISTRY"].variable_name == "OCI_DOCKER_HUB_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_DOCKER_HUB_REGISTRY' for OCI upstream Docker Hub AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_VIRT_REGISTRY"].variable_name == "OCI_VIRT_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_VIRT_REGISTRY' for OCI virtual AR repo."
  }

  # Outputs
  assert {
    condition     = length(output.registries) == 3
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
    condition     = output.registries["oci-docker-hub"] != null
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-docker-hub"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-docker-hub"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = output.registries["oci-virt"] != null
    error_message = "Expected registries output for key 'oci-virt' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 3
    error_message = "Expected repo_identifiers output to have three entries."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-docker-hub"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-docker-hub"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "enabled_no_bootstrap_oci" {
  variables {
    virtual_repo = {
      enable = true
    }
    gcp_options = {
      ar = {
        oci = false
      }
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = !can(google_project_service.apis["artifactregistry.googleapis.com"])
    error_message = "Expected project to not have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = !can(google_project_service_identity.ids["artifactregistry.googleapis.com"])
    error_message = "Expected project to not have enabled service identity for Artifact Registry."
  }

  # Repo creation
  assert {
    condition     = try(length(google_artifact_registry_repository.automation), 0) == 0
    error_message = "Expected no AR repos to be created."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 0
    error_message = "Expected no upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 0
    error_message = "Expected no virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 1
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 0
    error_message = "Expected no IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 0
    error_message = "Expected no GitHub secrets for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 0
    error_message = "Expected no GitHub variables for any AR repos."
  }

  # Outputs
  assert {
    condition     = length(output.registries) == 0
    error_message = "Expected registries output to have no entries."
  }
  assert {
    condition     = length(output.repo_identifiers) == 0
    error_message = "Expected repo_identifiers output to have no entries."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) == 0
    error_message = "Expected ar_sa output to be null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 0
    error_message = "Expected no upstream NGINX Docker secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 0
    error_message = "Expected no upstream F5 AI harbor secrets to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}

run "full_with_nginx_and_f5_ai" {
  variables {
    virtual_repo = {
      enable     = true
      docker_hub = true
      ar_repos = [
        "mock-location1-docker.pkg.dev/mock-project-id/mock-repo",
      ]
    }
    nginx_jwt = "mock-jwt"
    f5_ai_repo_credentials = {
      username = "dummy-f5-ai-user"
      password = "dummy-f5-ai-password"
    }
  }

  # API enablement
  assert {
    condition     = length(google_project_service.apis) >= 1
    error_message = "Expected at least one API to be enabled."
  }
  assert {
    condition     = google_project_service.apis["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled Artifact Registry API."
  }

  # Google service identities required by bootstrap
  assert {
    condition     = try(length(google_project_service_identity.ids), 0) > 0
    error_message = "Expected project to have enabled at least one service identities."
  }
  assert {
    condition     = google_project_service_identity.ids["artifactregistry.googleapis.com"] != null
    error_message = "Expected project to have enabled service identity for Artifact Registry."
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
    condition     = google_artifact_registry_repository.automation["oci"].repository_id == "var-virtual-repo-test-oci" && google_artifact_registry_repository.automation["oci"].format == "DOCKER" && google_artifact_registry_repository.automation["oci"].location == "us"
    error_message = "Expected OCI AR repo properties to match expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_nginx), 0) == 1
    error_message = "Expected one upstream repo for NGINX private repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_nginx :
      v.repository_id == "var-virtual-repo-test-oci-nginx" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream NGINX repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_f5_ai), 0) == 1
    error_message = "Expected one upstream repo for F5 AI private repo"
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_f5_ai :
      v.repository_id == "var-virtual-repo-test-oci-f5-ai" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream F5 AI repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.upstream_oci_docker_hub), 0) == 1
    error_message = "Expected one upstream repo for public Docker Hub repo."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.upstream_oci_docker_hub :
      v.repository_id == "var-virtual-repo-test-oci-docker-hub" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "REMOTE_REPOSITORY" &&
      try(length(v.remote_repository_config), 0) == 1
    ])
    error_message = "Expected upstream Docker Hub repository to meet basic expectations."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository.oci_virt), 0) == 1
    error_message = "Expected one virtual Docker repositories."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository.oci_virt :
      v.repository_id == "var-virtual-repo-test-oci-virt" &&
      v.format == "DOCKER" &&
      v.location == "us" &&
      v.mode == "VIRTUAL_REPOSITORY" &&
      try(length(v.virtual_repository_config[0].upstream_policies), 0) == 5
    ])
    error_message = "Expected virtual repository to meet basic expectations."
  }

  # Virtual repo IAM bindings
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_automation), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on automation repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_automation :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on automation repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on upstream NGINX repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_nginx :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream NGINX repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on upstream F5 AI repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_f5_ai :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream F5 AI repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub), 0) == 1
    error_message = "Expected one IAM binding for AR identity service account on upstream Docker Hub repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_oci_docker_hub :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream Docker Hub repo."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.identity_upstream_ar), 0) == 1
    error_message = "Expected one IAM bindings for AR identity service account on upstream AR repos."
  }
  assert {
    condition = alltrue([for k, v in google_artifact_registry_repository_iam_member.identity_upstream_ar :
      v.member == "serviceAccount:mock-service-12345@mock-project.iam.gserviceaccount.com" && contains([
        # Expected AR roles for readers
        "roles/artifactregistry.reader",
      ], v.role)
    ])
    error_message = "Expected AR reader role bindings to AR identity service account on upstream AR repos."
  }
  assert {
    condition     = try(length(google_artifact_registry_repository_iam_member.virtual_reader), 0) == 1
    error_message = "Expected one IAM binding for Workload Identity AR readers on virtual repos."
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
    condition     = try(length(github_actions_secret.ar_sa), 0) == 1
    error_message = "Expected a GitHub secret for AR SA."
  }
  assert {
    condition     = try(length(github_actions_variable.registry), 0) == 5
    error_message = "Expected a GitHub variable for five AR repos."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_REGISTRY"].variable_name == "OCI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_REGISTRY' for OCI AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_NGINX_REGISTRY"].variable_name == "OCI_NGINX_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_NGINX_REGISTRY' for OCI upstream NGINX private repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_F5_AI_REGISTRY"].variable_name == "OCI_F5_AI_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_F5_AI_REGISTRY' for OCI upstream F5 AI private repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_DOCKER_HUB_REGISTRY"].variable_name == "OCI_DOCKER_HUB_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_DOCKER_HUB_REGISTRY' for OCI upstream Docker Hub AR repo."
  }
  assert {
    condition     = github_actions_variable.registry["OCI_VIRT_REGISTRY"].variable_name == "OCI_VIRT_REGISTRY"
    error_message = "Expected GitHub variable named 'OCI_VIRT_REGISTRY' for OCI virtual AR repo."
  }

  # Outputs
  assert {
    condition     = length(output.registries) == 5
    error_message = "Expected registries output to have five entries."
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
    condition     = output.registries["oci-nginx"] != null
    error_message = "Expected registries output for key 'oci-nginx' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-nginx"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-nginx' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-nginx"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-nginx' to be not null or empty."
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
    condition     = output.registries["oci-docker-hub"] != null
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-docker-hub"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-docker-hub"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = output.registries["oci-virt"] != null
    error_message = "Expected registries output for key 'oci-virt' to be not null."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].project), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = try(length(output.registries["oci-virt"].location), 0) > 0
    error_message = "Expected registries output for key 'oci-virt' to be not null or empty."
  }
  assert {
    condition     = length(output.repo_identifiers) == 5
    error_message = "Expected repo_identifiers output to have five entries."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-nginx"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-nginx' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-f5-ai"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-f5-ai' to be not null or empty."
  }
  assert {
    condition     = try(length(output.repo_identifiers["oci-docker-hub"]), 0) > 0
    error_message = "Expected repo_identifiers output for key 'oci-docker-hub' to be not null or empty."
  }
  assert {
    condition     = try(length(output.ar_sa), 0) > 0
    error_message = "Expected ar_sa output to be not null or empty."
  }

  # Secret Manager secrets
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_nginx), 0) == 1
    error_message = "Expected one upstream NGINX Docker secret to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_nginx : v.secret_id == "var-virtual-repo-test-upstream-oci-nginx"])
    error_message = "Expected upstream NGINX Docker secret name to be 'var-virtual-repo-test-upstream-oci-nginx'."
  }
  assert {
    condition     = try(length(google_secret_manager_secret.upstream_oci_password_f5_ai), 0) == 1
    error_message = "Expected one upstream F5 AI harbor secret to be created."
  }
  assert {
    condition     = alltrue([for k, v in google_secret_manager_secret.upstream_oci_password_f5_ai : v.secret_id == "var-virtual-repo-test-upstream-oci-password-f5-ai"])
    error_message = "Expected upstream F5 AI harbor secret name to be 'var-virtual-repo-test-upstream-oci-password-f5-ai'."
  }
}
