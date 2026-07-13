# All ids use one(resource.this[*].id) so they are null when the feature flag is
# off (empty list => null) and the single created id when it is on.

output "enabled" {
  description = "Echoes var.enable_private_networking so consumers can gate off a single source."
  value       = var.enable_private_networking
}

output "vnet_id" {
  value = one(azurerm_virtual_network.this[*].id)
}

output "pe_subnet_id" {
  description = "Private-endpoint subnet id (Postgres/Redis/KeyVault/ACR PEs)."
  value       = one(azurerm_subnet.pe[*].id)
}

output "apim_integration_subnet_id" {
  description = "APIM Std v2 outbound VNet integration subnet id."
  value       = one(azurerm_subnet.apim_integration[*].id)
}

output "aca_infrastructure_subnet_id" {
  description = "Container Apps environment infrastructure subnet id."
  value       = one(azurerm_subnet.aca_infrastructure[*].id)
}

output "dns_zone_id_apim" {
  value = one(azurerm_private_dns_zone.apim[*].id)
}

output "dns_zone_id_postgres" {
  value = one(azurerm_private_dns_zone.postgres[*].id)
}

output "dns_zone_id_redis" {
  value = one(azurerm_private_dns_zone.redis[*].id)
}

output "dns_zone_id_keyvault" {
  value = one(azurerm_private_dns_zone.keyvault[*].id)
}

output "dns_zone_id_acr" {
  value = one(azurerm_private_dns_zone.acr[*].id)
}
