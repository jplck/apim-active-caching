variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "base" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "redis_sku" {
  type        = string
  description = "Azure Managed Redis SKU (Microsoft.Cache/redisEnterprise)."
  default     = "Balanced_B0"
}

variable "enable_private_networking" {
  type        = bool
  description = "When true, create a private endpoint for Managed Redis and disable its public network access."
  default     = false
}

variable "private_endpoint_subnet_id" {
  type        = string
  description = "Subnet id where the Managed Redis private endpoint NIC is placed. Required when enable_private_networking is true."
  default     = null
}

variable "private_dns_zone_id" {
  type        = string
  description = "Private DNS zone id (privatelink.redis.azure.net) linked to the private endpoint. Required when enable_private_networking is true."
  default     = null
}
