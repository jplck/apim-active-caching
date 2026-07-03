output "AZURE_LOCATION" {
  value = azurerm_resource_group.this.location
}

output "RESOURCE_GROUP" {
  value = azurerm_resource_group.this.name
}

output "APIM_GATEWAY_URL" {
  value = azurerm_api_management.this.gateway_url
}

output "WORKERS_ENDPOINT" {
  description = "Public active-cache endpoint to test."
  value       = "${azurerm_api_management.this.gateway_url}/workers"
}

output "WORKDAY_MOCK_ENDPOINT" {
  value = "${azurerm_api_management.this.gateway_url}/workday-mock/workers"
}

output "WORKDAY_SOAP_MOCK_ENDPOINT" {
  description = "Mocked Workday SOAP Get_Workers endpoint (POST a SOAP envelope)."
  value       = "${azurerm_api_management.this.gateway_url}/workday-soap/Human_Resources"
}

output "REFRESHER_JOB_NAME" {
  value = azurerm_container_app_job.refresher.name
}

output "REFRESH_TOKEN" {
  description = "X-Refresh-Token value that triggers the workers API refresh branch."
  value       = random_password.refresh_token.result
  sensitive   = true
}
