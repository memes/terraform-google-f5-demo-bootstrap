output "sa" {
  value       = google_service_account.sa.email
  description = <<-EOD
  The fully-qualified email address of the Cloud Deploy execution service account.
  EOD
}
