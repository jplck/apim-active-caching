output "id" {
  value = azurerm_managed_redis.this.id
}

output "name" {
  value = azurerm_managed_redis.this.name
}

output "hostname" {
  value = azurerm_managed_redis.this.hostname
}

# Managed Redis endpoint port (default_database). APIM connects with ssl on this port.
output "port" {
  value = azurerm_managed_redis.this.default_database[0].port
}
