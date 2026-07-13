variable "environment_name" {
  type        = string
  description = "azd environment name; used to name/tag resources."
}

variable "location" {
  type        = string
  description = "Azure region, e.g. westeurope."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription id. Leave null to use ARM_SUBSCRIPTION_ID / az login context."
  default     = null
}

variable "apim_sku" {
  type        = string
  description = "APIM SKU. Standard v2 by default."
  default     = "StandardV2_1"
}

variable "publisher_name" {
  type    = string
  default = "Contoso"
}

variable "publisher_email" {
  type    = string
  default = "admin@example.com"
}

variable "redis_sku" {
  type        = string
  description = "Azure Managed Redis SKU (Microsoft.Cache/redisEnterprise). Balanced_B0 is the cheapest."
  default     = "Balanced_B0"
}

variable "cache_ttl_seconds" {
  type        = number
  description = "External-cache TTL for the passive workers cache (keep > refresh interval)."
  default     = 172800
}

variable "refresh_cron" {
  type        = string
  description = "Cron for the refresher Container Apps Job (UTC, 5-field). Daily sync by default."
  default     = "0 2 * * *"
}

# --- Workday ISU credentials (stored in Key Vault) ------------------------
# Supplied via TF_VAR_workday_username / TF_VAR_workday_password (never committed).
variable "workday_username" {
  type        = string
  description = "Workday ISU username (e.g. isu_integration@tenant). Stored as a Key Vault secret."
  sensitive   = true
}

variable "workday_password" {
  type        = string
  description = "Workday ISU password. Stored as a Key Vault secret."
  sensitive   = true
}

variable "workday_soap_url" {
  type        = string
  description = "Workday SOAP endpoint. Empty string => use the in-APIM SOAP mock."
  default     = ""
}

# --- Postgres -------------------------------------------------------------
variable "postgres_sku" {
  type        = string
  description = "Postgres Flexible Server SKU. Burstable B1ms is the cheapest."
  default     = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  type        = number
  description = "Postgres Flexible Server storage in MB."
  default     = 32768
}

variable "entra_admin_object_id" {
  type        = string
  description = "Object id of the Entra principal made Postgres AAD admin (usually the deployer). Null skips admin + DB role bootstrap (e.g. plain terraform validate)."
  default     = null
}
