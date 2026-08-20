output "state_bucket" {
  value       = one([for bucket in google_storage_bucket.state : bucket.name])
  description = <<-EOD
  The GCS bucket that will host automation related state, if created.
  EOD
}

output "registries" {
  value = merge(
    { for k, v in google_artifact_registry_repository.automation : k => {
      project  = v.project
      location = v.location
      name     = v.name
      }
    },
    { for k, v in google_artifact_registry_repository.upstream_oci_nginx : k => {
      project  = v.project
      location = v.location
      name     = v.name
      }
    },
    { for k, v in google_artifact_registry_repository.upstream_oci_f5_ai : k => {
      project  = v.project
      location = v.location
      name     = v.name
      }
    },
    {
      for k, v in google_artifact_registry_repository.oci_virt : k => {
        project  = v.project
        location = v.location
        name     = v.name
      }
    },
  )
  description = <<-EOD
  A map of Artifact Registry resources created by the module.
  EOD
}

output "repo_identifiers" {
  value = merge(
    { for k, v in google_artifact_registry_repository.automation : k => local.ar_repos[k].identifier },
    { for k, v in google_artifact_registry_repository.upstream_oci_nginx : k => format("%s-docker.pkg.dev/%s/%s", v.location, v.project, v.repository_id) },
    { for k, v in google_artifact_registry_repository.upstream_oci_f5_ai : k => format("%s-docker.pkg.dev/%s/%s", v.location, v.project, v.repository_id) },
    { for k, v in google_artifact_registry_repository.oci_virt : k => format("%s-docker.pkg.dev/%s/%s", v.location, v.project, v.repository_id) },
  )
  description = <<-EOD
  A map of Artifact Registry resource types to canonical access identifiers.
  EOD
}

output "sops_kms_id" {
  value       = one([for k, v in google_kms_crypto_key.sops : v.id])
  description = <<-EOD
  The identifier of the KMS encryption/decryption key created by the module for sops usage, if KMS enabled.
  EOD
}

output "iac_sa" {
  value       = google_service_account.iac.email
  description = <<-EOD
  The fully-qualified email address of the IaC automation service account.
  EOD
}

output "ar_sa" {
  value       = one([for k, v in google_service_account.ar : v.email])
  description = <<-EOD
  The fully-qualified email address of the Artifact Registry automation service account, if created.
  EOD
}

output "html_url" {
  value       = github_repository.automation.html_url
  description = <<-EOD
  The URL to the GitHub repository created for this project.
  EOD
}

output "http_clone_url" {
  value       = github_repository.automation.http_clone_url
  description = <<-EOD
  The repo's clone over HTTPS URL.
  EOD
}

output "ssh_clone_url" {
  value       = github_repository.automation.ssh_clone_url
  description = <<-EOD
  The repo's clone with SSH URL.
  EOD
}

output "deploy_public_key" {
  value       = one([for k, v in tls_private_key.automation : v.public_key_openssh])
  sensitive   = true
  description = <<-EOD
  The public deploy key, if created.
  EOD
}

output "deploy_private_key" {
  value       = one([for k, v in tls_private_key.automation : v.private_key_openssh])
  sensitive   = true
  description = <<-EOD
  The private deploy key, if created.
  EOD
}

output "workload_identity_pool_id" {
  value       = google_iam_workload_identity_pool.bots.id
  description = <<-EOD
  The fully-qualified identifier of the created Workload Identity pool.
  EOD
}

output "github_repo" {
  value       = github_repository.automation.full_name
  description = <<-EOD
  The full name of the repository.
  EOD
}

output "deploy_sa" {
  value       = one([for sa in google_service_account.deploy : sa.email])
  description = <<-EOD
  The fully-qualified email address of the Cloud Deploy execution service account, if enabled.
  EOD
}

output "nginx_jwt" {
  value = {
    secret_id = one([for k, v in google_secret_manager_secret.nginx_jwt : v.secret_id])
    id        = one([for k, v in google_secret_manager_secret.nginx_jwt : v.id])
  }
  description = <<-EOD
  If an NGINX JWT secret was created during bootstrap, return the fully-qualified and local identifiers, if appropriate.
  EOD
}

output "f5_ai_license" {
  value = {
    secret_id = one([for k, v in google_secret_manager_secret.f5_ai_license : v.secret_id])
    id        = one([for k, v in google_secret_manager_secret.f5_ai_license : v.id])
  }
  description = <<-EOD
  If an F5 AI license secret was created during bootstrap, return the fully-qualified and local identifiers, if appropriate.
  EOD
}
