terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

locals {
  # Short, stable PG role names mapped to each identity's object id by the Entra
  # bootstrap below. Used as PGUSER by the workloads.
  middleware_role = "middleware"
  refresher_role  = "refresher"
}

# ---------------------------------------------------------------------------
# Azure Postgres Flexible Server — MANAGED-IDENTITY AUTH ONLY.
# password_auth_enabled = false means there is no admin password anywhere; the
# only way in is an Entra access token. active_directory_auth_enabled = true
# turns on the token path. Because password auth is off we must NOT set
# administrator_login / administrator_password.
# ---------------------------------------------------------------------------
resource "azurerm_postgresql_flexible_server" "this" {
  name                = "psql-${var.base}"
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "16"
  sku_name            = var.postgres_sku
  storage_mb          = var.postgres_storage_mb
  zone                = "1"

  authentication {
    password_auth_enabled         = false
    active_directory_auth_enabled = true
    tenant_id                     = var.tenant_id
  }

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "workday" {
  name      = "workday"
  server_id = azurerm_postgresql_flexible_server.this.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Allow the public endpoint to be reached from Azure-internal services (the
# Container Apps). 0.0.0.0-0.0.0.0 is the special "Allow Azure services" range.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Entra admin (usually the deploying principal) — the single account allowed to
# CREATE the two MI DB roles below. Guarded: skipped when no admin object id is
# supplied (e.g. plain `terraform validate`).
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  count               = var.entra_admin_object_id == null ? 0 : 1
  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  object_id           = var.entra_admin_object_id
  principal_name      = var.entra_admin_principal_name
  principal_type      = var.entra_admin_principal_type
}

# ---------------------------------------------------------------------------
# Entra DB role bootstrap.
# Azure Postgres has no Terraform resource to create *Entra* DB principals, so we
# bootstrap them with a guarded psql local-exec. This is the cleaner option than
# the `postgresql` provider here: that provider would need a live Entra access
# token wired as its password at plan time, whereas a one-shot psql script keeps
# token handling in the shell and never runs during `terraform validate` (the
# gate for this change). It maps each user-assigned identity's object id to a
# least-privilege role via the Azure pgaadauth_create_principal_with_oid()
# extension: middleware = read-only (SELECT), refresher = read/write.
#
# Runtime prerequisites (apply only, not validate): psql on PATH, and the caller
# authenticated as the Entra admin above, i.e.
#   export PGUSER="<entra-admin-login>"
#   export PGPASSWORD="$(az account get-access-token \
#     --resource https://ossrdbms-aad.database.windows.net --query accessToken -o tsv)"
# ---------------------------------------------------------------------------
resource "null_resource" "entra_db_roles" {
  count = var.entra_admin_object_id == null ? 0 : 1

  triggers = {
    server          = azurerm_postgresql_flexible_server.this.id
    database        = azurerm_postgresql_flexible_server_database.workday.name
    middleware_oid  = var.middleware_principal_id
    refresher_oid   = var.refresher_principal_id
    middleware_role = local.middleware_role
    refresher_role  = local.refresher_role
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      PGHOST     = azurerm_postgresql_flexible_server.this.fqdn
      PGDATABASE = azurerm_postgresql_flexible_server_database.workday.name
      PGSSLMODE  = "require"
    }
    command = <<-EOT
      set -euo pipefail
      psql -v ON_ERROR_STOP=1 <<'SQL'
      SELECT * FROM pgaadauth_create_principal_with_oid('${local.middleware_role}', '${var.middleware_principal_id}', 'service', false, false);
      SELECT * FROM pgaadauth_create_principal_with_oid('${local.refresher_role}', '${var.refresher_principal_id}', 'service', false, false);
      GRANT CONNECT ON DATABASE "${azurerm_postgresql_flexible_server_database.workday.name}" TO "${local.middleware_role}", "${local.refresher_role}";
      GRANT USAGE ON SCHEMA public TO "${local.middleware_role}", "${local.refresher_role}";
      GRANT USAGE, CREATE ON SCHEMA public TO "${local.refresher_role}";
      GRANT SELECT ON ALL TABLES IN SCHEMA public TO "${local.middleware_role}";
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "${local.middleware_role}";
      GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "${local.refresher_role}";
      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "${local.refresher_role}";
      SQL
    EOT
  }

  depends_on = [
    azurerm_postgresql_flexible_server_active_directory_administrator.this,
    azurerm_postgresql_flexible_server_database.workday,
  ]
}
