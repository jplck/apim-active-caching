variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "token" {
  type        = string
  description = "Stable random suffix for the globally-unique, <=24-char vault name."
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "workday_username" {
  type        = string
  description = "Workday ISU username stored as the workday-username secret."
  sensitive   = true
}

variable "workday_password" {
  type        = string
  description = "Workday ISU password stored as the workday-password secret."
  sensitive   = true
}

variable "refresher_principal_id" {
  type        = string
  description = "Principal id of the refresher identity granted Key Vault Secrets User."
}
