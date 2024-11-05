output "state_bucket" {
  value       = google_storage_bucket.state.name
  description = <<-EOD
  The GCS bucket that will host automation related state.
  EOD
}

output "registries" {
  value = { for k, v in google_artifact_registry_repository.automation : k => {
    project  = v.project
    location = v.location
    name     = v.name
  } }
  description = <<-EOD
  A map of Artifact Registry resources created by the module.
  EOD
}

output "repo_identifiers" {
  value       = { for k, v in google_artifact_registry_repository.automation : k => local.ar_repos[k].identifier }
  description = <<-EOD
  A map of Artifact Registry resource types to canonical access identifiers.
  EOD
}

output "sops_kms_id" {
  value       = google_kms_crypto_key.sops.id
  description = <<-EOD
  The identifier of the KMS encryption/decryption key created by the module for sops usage.
  EOD
}

output "sa" {
  value       = google_service_account.automation.email
  description = <<-EOD
  The fully-qualified email address of the automation service account.
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

output "deploy_pubkey" {
  value       = tls_private_key.automation.public_key_openssh
  sensitive   = true
  description = <<-EOD
  The public deploy key.
  EOD
}

output "deploy_privkey" {
  value       = tls_private_key.automation.private_key_openssh
  sensitive   = true
  description = <<-EOD
  The private deploy key.
  EOD
}

output "workload_identity_pool_id" {
  value       = google_iam_workload_identity_pool.automation.id
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
