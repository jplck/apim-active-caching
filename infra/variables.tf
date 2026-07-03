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
  description = "External-cache TTL. Keep > refresh interval so the cache never empties between runs (default 2 days > daily refresh)."
  default     = 172800
}

variable "refresh_cron" {
  type        = string
  description = "Cron for the refresher Container Apps Job (UTC, 5-field). Daily full load by default."
  default     = "0 2 * * *"
}
