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

# --- Private networking (OPTIONAL — plan.md §10) --------------------------
# All off by default so the public POC path is byte-for-byte unchanged. Flip
# enable_private_networking to true to stand up the VNet, delegated subnets and
# privatelink DNS zones, and to push every backend service onto private endpoints.
# Accepted as a STRING (not bool) so `azd` can prompt for it: azd substitutes
# infra parameters as strings, and an empty answer to a bool var would fail type
# conversion. Normalised to a real bool in local.enable_private_networking below.
# Standalone Terraform users may still pass a bool literal (`true`/`false`) — it
# is coerced to a string automatically.
variable "enable_private_networking" {
  type        = string
  description = "Master feature flag for the private-networking topology (VNet + private endpoints). Accepts true/false/yes/no/1/0 (empty = false). Default keeps the all-public POC."
  default     = "false"

  validation {
    condition     = contains(["", "true", "false", "yes", "no", "1", "0"], lower(trimspace(var.enable_private_networking)))
    error_message = "enable_private_networking must be one of: true, false, yes, no, 1, 0 (or empty for false)."
  }
}

variable "vnet_address_space" {
  type        = string
  description = "CIDR for the single VNet when private networking is enabled."
  default     = "10.20.0.0/16"
}

variable "apim_integration_subnet_cidr" {
  type        = string
  description = "APIM Std v2 outbound VNet integration subnet CIDR (delegated to Microsoft.Web/serverFarms)."
  default     = "10.20.0.0/24"
}

variable "aca_infrastructure_subnet_cidr" {
  type        = string
  description = "Container Apps environment infrastructure subnet CIDR (delegated to Microsoft.App/environments)."
  default     = "10.20.4.0/23"
}

variable "pe_subnet_cidr" {
  type        = string
  description = "Private-endpoint subnet CIDR (Postgres/Redis/KeyVault/ACR)."
  default     = "10.20.8.0/24"
}
