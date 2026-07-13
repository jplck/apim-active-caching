output "environment_id" {
  value = azurerm_container_app_environment.this.id
}

output "middleware_fqdn" {
  value = azurerm_container_app.middleware.ingress[0].fqdn
}

# External middleware URL — APIM uses this as the workers backend / OpenAPI source.
output "middleware_url" {
  value = "https://${azurerm_container_app.middleware.ingress[0].fqdn}"
}

output "refresher_job_name" {
  value = azurerm_container_app_job.refresher.name
}
