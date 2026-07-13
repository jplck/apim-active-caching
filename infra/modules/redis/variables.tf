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
