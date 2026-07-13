output "environment_id" {
  value = azurerm_container_app_environment.this.id
}

output "middleware_fqdn" {
  value = azurerm_container_app.middleware.ingress[0].fqdn
}

# Middleware URL — APIM uses this as the workers backend / OpenAPI source.
# Public FQDN by default; private (VNet-only) FQDN when private networking is on.
output "middleware_url" {
  value = "https://${azurerm_container_app.middleware.ingress[0].fqdn}"
}

output "refresher_job_name" {
  value = azurerm_container_app_job.refresher.name
}

# True when the environment is VNet-integrated + internal load balancer only.
output "environment_internal" {
  value = var.enable_private_networking
}
