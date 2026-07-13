output "token" {
  description = "Stable random suffix shared by all resource names."
  value       = local.token
}

output "base" {
  description = "Base name fragment: <environment_name>-<token>."
  value       = local.base
}

output "tags" {
  description = "Common tags applied to every resource (includes azd-env-name)."
  value       = local.tags
}

output "environment_name" {
  value = var.environment_name
}
