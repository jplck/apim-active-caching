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
