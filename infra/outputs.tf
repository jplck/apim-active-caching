output "RESOURCE_GROUP" {
  value = azurerm_resource_group.this.name
}

output "AZURE_LOCATION" {
  value = azurerm_resource_group.this.location
}

output "APIM_GATEWAY_URL" {
  value = module.apim.gateway_url
}

output "WORKERS_ENDPOINT" {
  description = "Passively-cached workers endpoint served via APIM."
  value       = module.apim.workers_endpoint
}

output "MIDDLEWARE_URL" {
  description = "Middleware Container App external URL (APIM backend / OpenAPI source)."
  value       = module.containerapps.middleware_url
}

output "POSTGRES_FQDN" {
  value = module.postgres.fqdn
}

output "ACR_LOGIN_SERVER" {
  value = module.registry.login_server
}

output "REFRESHER_JOB_NAME" {
  value = module.containerapps.refresher_job_name
}

output "KEY_VAULT_URI" {
  value = module.keyvault.vault_uri
}

output "WORKDAY_SOAP_MOCK_ENDPOINT" {
  description = "Mocked Workday SOAP Get_Workers endpoint (the refresher's POC source)."
  value       = module.apim.workday_soap_mock_endpoint
}
