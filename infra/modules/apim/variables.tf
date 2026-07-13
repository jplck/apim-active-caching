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

variable "apim_sku" {
  type    = string
  default = "StandardV2_1"
}

variable "publisher_name" {
  type    = string
  default = "Contoso"
}

variable "publisher_email" {
  type    = string
  default = "admin@example.com"
}

variable "cache_ttl_seconds" {
  type    = number
  default = 172800
}

# --- external redis cache -------------------------------------------------
variable "redis_hostname" {
  type = string
}

variable "redis_port" {
  type = number
}

# --- workers backend ------------------------------------------------------
variable "middleware_url" {
  type        = string
  description = "Middleware Container App URL used as the workers backend + OpenAPI source."
}
