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

variable "tenant_id" {
  type        = string
  description = "Entra tenant id backing the MI-only authentication."
}

variable "postgres_sku" {
  type    = string
  default = "B_Standard_B1ms"
}

variable "postgres_storage_mb" {
  type    = number
  default = 32768
}

variable "middleware_principal_id" {
  type        = string
  description = "Object id of the middleware identity (read-only DB role)."
}

variable "refresher_principal_id" {
  type        = string
  description = "Object id of the refresher identity (read/write DB role)."
}

variable "entra_admin_object_id" {
  type        = string
  default     = null
  description = "Entra principal made PG AAD admin; null skips admin + role bootstrap."
}

variable "entra_admin_principal_name" {
  type        = string
  default     = "pgEntraAdmin"
  description = "Display/login name recorded for the PG AAD admin."
}

variable "entra_admin_principal_type" {
  type        = string
  default     = "User"
  description = "PG AAD admin principal type: User, Group or ServicePrincipal."
}
