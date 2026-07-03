#!/usr/bin/env bash
# Flush the external Redis so the next GET /workers returns 503 (X-Cache: MISS).
# Installs redis-cli if missing (no Docker). Uses core `az` (no redisenterprise
# extension, so it isn't affected by the extension's api-version drift).
#
# Auto-discovers everything from Terraform state in ../infra (run after `azd up`
# or `terraform apply`).
set -euo pipefail

# redisEnterprise api-version. Supported versions vary by region, so discover the
# latest stable one from ARM (override with REDIS_API_VERSION; static fallback).
API_VERSION="${REDIS_API_VERSION:-}"

ensure_redis_cli() {
  command -v redis-cli >/dev/null 2>&1 && return
  echo "[flush] redis-cli not found — installing..."
  sudo=""
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo="sudo"
  if command -v apt-get >/dev/null 2>&1; then
    $sudo apt-get update -qq && $sudo apt-get install -y -qq redis-tools
  elif command -v dnf >/dev/null 2>&1; then
    $sudo dnf install -y redis
  elif command -v yum >/dev/null 2>&1; then
    $sudo yum install -y redis
  elif command -v apk >/dev/null 2>&1; then
    $sudo apk add --no-cache redis
  elif command -v zypper >/dev/null 2>&1; then
    $sudo zypper install -y redis
  elif command -v brew >/dev/null 2>&1; then
    brew install redis
  else
    echo "[flush] no supported package manager; install redis-cli manually." >&2
    exit 1
  fi
}

ensure_redis_cli

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Terraform state location. azd keeps it at .azure/<env>/infra/terraform.tfstate,
# NOT infra/terraform.tfstate. Resolve it (override with TF_STATE; pick the env
# with AZURE_ENV_NAME, else the azd default from .azure/config.json).
state="${TF_STATE:-}"
if [ -z "$state" ]; then
  env_name="${AZURE_ENV_NAME:-}"
  if [ -z "$env_name" ] && [ -f "$ROOT/.azure/config.json" ]; then
    env_name="$(sed -n 's/.*"defaultEnvironment" *: *"\([^"]*\)".*/\1/p' "$ROOT/.azure/config.json")"
  fi
  [ -n "$env_name" ] && state="$ROOT/.azure/$env_name/infra/terraform.tfstate"
fi
# Fall back to plain `terraform apply` state if the azd one isn't there.
[ -n "$state" ] && [ -f "$state" ] || state="$ROOT/infra/terraform.tfstate"

# Read an output from that state. `terraform output` needs an initialized dir;
# init once if the provider cache is missing.
tf_out() { terraform -chdir="$ROOT/infra" output -state="$state" -raw "$1" 2>/dev/null; }
echo "[flush] reading Terraform outputs from ${state}..."
tf_out RESOURCE_GROUP >/dev/null 2>&1 || {
  echo "[flush] initializing Terraform providers..."
  terraform -chdir="$ROOT/infra" init -input=false -no-color >/dev/null
}
rg="$(tf_out RESOURCE_GROUP || true)"
if [ -z "$rg" ]; then
  echo "[flush] no RESOURCE_GROUP output in $state — deploy first, or set TF_STATE." >&2
  exit 1
fi

echo "[flush] locating Managed Redis in ${rg}..."
sub="$(az account show --query id -o tsv --only-show-errors)"
if [ -z "$API_VERSION" ]; then
  API_VERSION="$(az provider show --namespace Microsoft.Cache \
    --query "resourceTypes[?resourceType=='redisEnterprise'].apiVersions[]" -o tsv --only-show-errors \
    | grep -v preview | sort -r | head -1)"
  [ -n "$API_VERSION" ] || API_VERSION="2024-10-01"
fi
name="$(az resource list -g "$rg" --resource-type Microsoft.Cache/redisEnterprise \
  --query "[0].name" -o tsv --only-show-errors)"
[ -n "$name" ] || { echo "[flush] no Microsoft.Cache/redisEnterprise cluster in $rg" >&2; exit 1; }

host="$(az resource show -g "$rg" -n "$name" --resource-type Microsoft.Cache/redisEnterprise \
  --api-version "$API_VERSION" --query properties.hostName -o tsv --only-show-errors)"
key="$(az rest --method post --only-show-errors \
  --url "https://management.azure.com/subscriptions/${sub}/resourceGroups/${rg}/providers/Microsoft.Cache/redisEnterprise/${name}/databases/default/listKeys?api-version=${API_VERSION}" \
  --query primaryKey -o tsv)"

# Managed Redis: TLS on port 10000. FLUSHALL clears APIM's prefixed key too.
echo "[flush] FLUSHALL on ${name} (${host}:10000)"
redis-cli -h "$host" -p 10000 --tls -a "$key" FLUSHALL

# Verify against the gateway from Terraform output.
gw="$(tf_out APIM_GATEWAY_URL || true)"
if [ -n "$gw" ]; then
  echo "[flush] verify (expect HTTP 503 / X-Cache: MISS):"
  curl -si "${gw}/workers" | grep -iE '^(HTTP/|x-cache)' || true
else
  echo "[flush] done. Curl your gateway /workers to confirm the 503/MISS."
fi
