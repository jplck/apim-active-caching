variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "base" {
  type = string
}

variable "token" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "container_port" {
  type        = number
  default     = 8000
  description = "Middleware HTTP port (FastAPI/uvicorn default) and ingress target port."
}

# --- registry -------------------------------------------------------------
variable "acr_login_server" {
  type = string
}

# --- identities -----------------------------------------------------------
variable "middleware_identity_id" {
  type = string
}

variable "middleware_client_id" {
  type = string
}

variable "refresher_identity_id" {
  type = string
}

variable "refresher_client_id" {
  type = string
}

# --- postgres MI connection contract -------------------------------------
variable "postgres_fqdn" {
  type = string
}

variable "postgres_port" {
  type    = number
  default = 5432
}

variable "postgres_database" {
  type = string
}

variable "middleware_role" {
  type        = string
  description = "PG role (PGUSER) the middleware connects as."
}

variable "refresher_role" {
  type        = string
  description = "PG role (PGUSER) the refresher connects as."
}

# --- key vault secret references (refresher) ------------------------------
variable "workday_username_secret_id" {
  type        = string
  description = "Versionless KV secret id for the Workday username."
}

variable "workday_password_secret_id" {
  type        = string
  description = "Versionless KV secret id for the Workday password."
}

# --- refresher behaviour --------------------------------------------------
variable "refresh_cron" {
  type = string
}

variable "workday_soap_url" {
  type        = string
  description = "Effective Workday SOAP endpoint (real tenant or in-APIM SOAP mock)."
}

variable "workday_api_version" {
  type    = string
  default = "v46.2"
}

variable "sync_mode" {
  type    = string
  default = "auto"
}

variable "watermark_lookback_seconds" {
  type    = number
  default = 60
}

variable "page_count" {
  type    = number
  default = 100
}

variable "effective_floor" {
  type    = string
  default = "1900-01-01"
}

variable "effective_lookahead_days" {
  type    = number
  default = 0
}
