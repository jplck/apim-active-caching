#!/usr/bin/env bash
# Peek at the workers / sync_state rows the refresher writes into Postgres.
# This is the Postgres analog of a cache peek: it shows what the middleware will
# serve (and hence what APIM caches).
#
# Postgres is MANAGED-IDENTITY-AUTH ONLY (no password). A human connects with an
# Entra access token as the password:
#   PGPASSWORD = az account get-access-token --resource-type oss-rdbms
#   PGUSER     = the Entra principal name (must be a DB principal — e.g. the
#                Postgres Entra admin / deployer). Override with PGUSER if needed.
#
# Reads POSTGRES_FQDN from Terraform outputs in ../infra. Run after `azd up`
# (or `terraform apply`): scripts/db-verify.sh
set -euo pipefail

cd "$(dirname "$0")/../infra"

if ! command -v psql >/dev/null 2>&1; then
  echo "[db-verify] psql not found. Install the PostgreSQL client, e.g.:" >&2
  echo "            sudo apt-get install -y postgresql-client   # Debian/Ubuntu" >&2
  echo "            brew install libpq                          # macOS" >&2
  exit 1
fi

host="$(terraform output -raw POSTGRES_FQDN)"

# Entra login name. Default to the signed-in user's UPN; override for a service
# principal or a different DB principal via `PGUSER=... scripts/db-verify.sh`.
PGUSER="${PGUSER:-$(az ad signed-in-user show --query userPrincipalName -o tsv 2>/dev/null || true)}"
if [ -z "$PGUSER" ]; then
  echo "[db-verify] could not resolve an Entra login. Set PGUSER to your Postgres" >&2
  echo "            Entra principal name (e.g. your UPN or the admin login)." >&2
  exit 1
fi

# Mint a short-lived Entra access token for the Postgres audience → use as password.
PGPASSWORD="$(az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv)"

export PGHOST="$host"
export PGPORT="${PGPORT:-5432}"
export PGDATABASE="${PGDATABASE:-workday}"
export PGSSLMODE="${PGSSLMODE:-require}"
export PGUSER PGPASSWORD

echo "[db-verify] connecting to ${PGHOST}/${PGDATABASE} as ${PGUSER} (Entra token)..."
psql -v ON_ERROR_STOP=1 -c 'SELECT 1;' >/dev/null || {
  echo "[db-verify] connection failed. Ensure ${PGUSER} is a Postgres Entra principal" >&2
  echo "            and your IP is allowed by the server firewall." >&2
  exit 1
}

echo
echo "[db-verify] sync watermark (sync_state):"
psql -P pager=off -c 'TABLE sync_state;' || echo "  (sync_state not found — run the refresher first)"

echo
echo "[db-verify] worker row count:"
psql -P pager=off -Atc 'SELECT count(*) FROM workers;' || echo "  (workers not found — run the refresher first)"

echo
echo "[db-verify] most recently updated workers (up to 10):"
psql -P pager=off -c \
  'SELECT employee_id, email, company_name, active, updated_at
     FROM workers ORDER BY updated_at DESC LIMIT 10;' \
  || echo "  (workers not found — run the refresher first)"
