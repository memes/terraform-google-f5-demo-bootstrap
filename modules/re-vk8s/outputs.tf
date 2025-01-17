output "policy_document" {
  value = {
    name      = volterra_secret_policy.automation.name
    namespace = volterra_secret_policy.automation.name
  }
  description = <<-EOD
  The F5 XC secret policy spec used to blindfold credentials.
  EOD
}

output "kubeconfig" {
  value       = base64decode(volterra_api_credential.automation.data)
  description = <<-EOD
  Kubeconfig for the vk8s service configured for automation.
  EOD
}

output "webhook_token" {
  value = random_string.webhook.result
}

output "sa" {
  value       = google_service_account.automation.email
  description = <<-EOD
  The fully-qualified email address of the automation service account.
  EOD
}
