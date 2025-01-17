output "state_bucket" {
  value       = module.bootstrap.state_bucket
  description = <<-EOD
  The GCS bucket that will host automation related state.
  EOD
}

output "repo_identifiers" {
  value       = module.bootstrap.repo_identifiers
  description = <<-EOD
  The Artifact Registry repo that will store OCI artefacts.
  EOD
}

output "automation_sa" {
  value       = module.bootstrap.sa
  description = <<-EOD
  The fully-qualified email address of the automation service account.
  EOD
}

output "github_url" {
  value       = module.bootstrap.html_url
  description = <<-EOD
  The URL to the GitHub repository created for this project.
  EOD
}

output "http_clone_url" {
  value       = module.bootstrap.http_clone_url
  description = <<-EOD
  The repo's clone over HTTPS URL.
  EOD
}

output "ssh_clone_url" {
  value       = module.bootstrap.ssh_clone_url
  description = <<-EOD
  The repo's clone with SSH URL.
  EOD
}

output "webhook_token" {
  sensitive = true
  value     = module.vk8s.webhook_token
}

output "vk8s_sa" {
  value       = module.vk8s.sa
  description = <<-EOD
  The fully-qualified email address of the vk8s service account.
  EOD
}
