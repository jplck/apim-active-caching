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

# --- private networking (opt-in) ------------------------------------------
# Root passes these EXACT inputs. When enable_private_networking is false the
# subnet id stays null (provider treats it as unset), so the Container Apps
# environment is provisioned public exactly as before — a byte-for-byte no-op.
variable "enable_private_networking" {
  type        = bool
  default     = false
  description = "Opt-in: place the Container Apps environment on the VNet and make middleware ingress internal (VNet-only)."
}

variable "infrastructure_subnet_id" {
  type        = string
  default     = null
  description = "ACA infrastructure subnet id. Required (non-null) only when enable_private_networking is true."
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
