# Validate the module resources and outputs when various GitHub related variables are changed from default values.
#
# NOTE: This test only looks at GitHub resources and outputs; see default.tftest.hcl for other assertions.
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
  name       = "github-test"
  project_id = "mock-project-id"
}

# Setting github_options variable to null should result in same outputs as default value.
run "null" {
  variables {
    github_options = null
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

# Setting github_options variable to empty object should result in same outputs as default value.
run "empty" {
  variables {
    github_options = {}
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "private" {
  variables {
    github_options = {
      private_repo = true
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
  }
  assert {
    condition     = github_repository.automation.description == "Bootstrapped automation repository"
    error_message = "Expected GitHub repo description to be 'Bootstrapped automation repository'."
  }
  assert {
    condition     = github_repository.automation.visibility == "private"
    error_message = "Expected GitHub repo to have private visibility."
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "name" {
  variables {
    github_options = {
      name = "explicit-name"
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "explicit-name"
    error_message = "Expected GitHub repo name to be 'explicit-name'."
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/explicit-name@33333:')"
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
    error_message = "Expected a GitHub variable for one AR repos."
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "description" {
  variables {
    github_options = {
      description = "Test automation repo"
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
  }
  assert {
    condition     = github_repository.automation.description == "Test automation repo"
    error_message = "Expected GitHub repo description to be 'Test automation repo'."
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "empty_template" {
  variables {
    github_options = {
      template = ""
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
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
    condition     = try(length(github_repository.automation.template), 0) == 0
    error_message = "Expected GitHub repo to not have a template."
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "template" {
  variables {
    github_options = {
      template = "mock/template"
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
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
      template.owner == "mock" &&
      template.repository == "template" &&
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "empty_collaborators" {
  variables {
    github_options = {
      collaborators = []
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "collaborators" {
  variables {
    github_options = {
      collaborators = [
        "collaborator0",
        "collaborator1",
      ]
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
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
    condition     = try(length(github_repository_collaborator.collaborators), 0) == 2
    error_message = "Expected GitHub repo to have 2 collaborators."
  }
  assert {
    condition = alltrue([for collaborator in github_repository_collaborator.collaborators : contains([
      # Expected set of collaborators
      "collaborator0",
      "collaborator1",
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "ssh_deploy_key" {
  variables {
    github_options = {
      ssh_deploy_key = true
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
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
    condition     = try(length(tls_private_key.automation), 0) == 1
    error_message = "Expected an SSH key for GitHub deployments."
  }
  assert {
    condition     = try(length(github_repository_deploy_key.automation), 0) == 1
    error_message = "Expected GitHub repo to have an SSH deploy keys."
  }

  # Workload identity provider
  assert {
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = coalesce(output.deploy_public_key, "unset") != "unset"
    error_message = "Expected deploy_public_key output to have a value."
  }
  assert {
    condition     = coalesce(output.deploy_private_key, "unset") != "unset"
    error_message = "Expected deploy_private_key output to have a value."
  }
  assert {
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "empty_org" {
  variables {
    github_options = {
      org = ""
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:mock_user@11111/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}

run "org" {
  override_data {
    target = data.github_organization.default
    values = {
      login = "explicit-org"
      id    = "44444"
    }
  }
  variables {
    github_options = {
      org = "explicit-org"
    }
  }

  # Github repo
  assert {
    condition     = github_repository.automation.name == "github-test"
    error_message = "Expected GitHub repo name to be 'github-test'."
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
    condition     = google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id == "github-test-gh"
    error_message = "Expected GitHub OIDC provider to be named 'github-test-gh'."
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
    condition     = google_iam_workload_identity_pool_provider.github.attribute_condition == "assertion.sub.startsWith('repo:explicit-org@44444/github-test@33333:')"
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
    condition     = try(length(github_actions_variable.secrets), 0) == 0
    error_message = "Expected no GitHub variables for additional secrets."
  }
  assert {
    condition     = alltrue([for k, v in github_actions_variable.secrets : can(regex("^[A-Z_]+_SECRET$", v.variable_name))])
    error_message = "Expected GitHub variable for additional secrets to be named correctly."
  }

  # GitHub outputs
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
    condition     = try(length(output.github_repo), 0) > 0
    error_message = "Expected github_repo output to be not null or empty."
  }
}
