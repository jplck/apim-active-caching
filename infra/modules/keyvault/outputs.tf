output "id" {
  value = azurerm_key_vault.this.id
}

output "vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}

# Versionless secret ids for Container Apps Key Vault secret references — the
# platform resolves the current version at container startup.
output "username_secret_id" {
  value = azurerm_key_vault_secret.workday_username.versionless_id
}

output "password_secret_id" {
  value = azurerm_key_vault_secret.workday_password.versionless_id
}

output "username_secret_name" {
  value = azurerm_key_vault_secret.workday_username.name
}

output "password_secret_name" {
  value = azurerm_key_vault_secret.workday_password.name
}
