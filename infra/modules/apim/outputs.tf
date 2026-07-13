output "id" {
  value = azurerm_api_management.this.id
}

output "name" {
  value = azurerm_api_management.this.name
}

output "gateway_url" {
  value = azurerm_api_management.this.gateway_url
}

output "workers_endpoint" {
  description = "Passively-cached workers endpoint served via APIM."
  value       = "${azurerm_api_management.this.gateway_url}/workers"
}

output "workday_soap_mock_endpoint" {
  description = "Mocked Workday SOAP Get_Workers endpoint (POST a SOAP envelope)."
  value       = "${azurerm_api_management.this.gateway_url}/workday-soap/Human_Resources"
}

output "private_endpoint_id" {
  description = "Resource ID of the inbound APIM Gateway private endpoint (null when private networking is disabled)."
  value       = try(azurerm_private_endpoint.apim[0].id, null)
}
