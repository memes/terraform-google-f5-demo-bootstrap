output "tfc_project" {
  value       = tfe_project.automation.name
  description = <<-EOD
  The name of the Terraform Cloud/TFE project created by the module.
  EOD
}
