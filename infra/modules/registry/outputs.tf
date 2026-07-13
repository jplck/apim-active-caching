output "id" {
  value = azurerm_container_registry.this.id
}

output "name" {
  value = azurerm_container_registry.this.name
}

output "login_server" {
  value = azurerm_container_registry.this.login_server
}

output "private_endpoint_id" {
  value = try(azurerm_private_endpoint.acr[0].id, null)
}
