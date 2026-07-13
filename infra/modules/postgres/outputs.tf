output "server_id" {
  value = azurerm_postgresql_flexible_server.this.id
}

output "server_name" {
  value = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.workday.name
}

output "port" {
  value = 5432
}

output "middleware_role" {
  description = "PG role name the middleware connects as (PGUSER)."
  value       = local.middleware_role
}

output "refresher_role" {
  description = "PG role name the refresher connects as (PGUSER)."
  value       = local.refresher_role
}

output "private_endpoint_id" {
  description = "Id of the Postgres private endpoint, or null when private networking is off."
  value       = try(azurerm_private_endpoint.pg[0].id, null)
}
