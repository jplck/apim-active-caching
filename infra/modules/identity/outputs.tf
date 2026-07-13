output "middleware_id" {
  value = azurerm_user_assigned_identity.middleware.id
}

output "middleware_principal_id" {
  value = azurerm_user_assigned_identity.middleware.principal_id
}

output "middleware_client_id" {
  value = azurerm_user_assigned_identity.middleware.client_id
}

output "middleware_name" {
  value = azurerm_user_assigned_identity.middleware.name
}

output "refresher_id" {
  value = azurerm_user_assigned_identity.refresher.id
}

output "refresher_principal_id" {
  value = azurerm_user_assigned_identity.refresher.principal_id
}

output "refresher_client_id" {
  value = azurerm_user_assigned_identity.refresher.client_id
}

output "refresher_name" {
  value = azurerm_user_assigned_identity.refresher.name
}
