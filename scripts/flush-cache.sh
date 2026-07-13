#!/usr/bin/env bash
# Flush the external Azure Managed Redis so the next GET /workers is a cache MISS.
# Redis is APIM's external cache; flushing it forces APIM to re-fetch from the
# middleware (Postgres) and re-store on the next request. Installs redis-cli if
# missing.
#
# There is NO Terraform output for Redis, so the cluster is discovered by resource
# group via `az` (core `az` + `az rest` for listKeys — no redisenterprise
# extension needed). Reads RESOURCE_GROUP / WORKERS_ENDPOINT from Terraform
# outputs in ../infra. Run after `azd up` (or `terraform apply`).
set -euo pipefail

cd "$(dirname "$0")/../infra"

ensure_redis_cli() {
  command -v redis-cli >/dev/null 2>&1 && return
  echo "[flush] redis-cli not found — installing..."
  sudo=""
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && sudo="sudo"
  if command -v apt-get >/dev/null 2>&1; then
    $sudo apt-get update -qq && $sudo apt-get install -y -qq redis-tools
  elif command -v dnf >/dev/null 2>&1; then
    $sudo dnf install -y redis
  elif command -v apk >/dev/null 2>&1; then
    $sudo apk add --no-cache redis
  elif command -v brew >/dev/null 2>&1; then
    brew install redis
  else
    echo "[flush] no supported package manager; install redis-cli manually." >&2
    exit 1
  fi
}
ensure_redis_cli

rg="$(terraform output -raw RESOURCE_GROUP)"
workers="$(terraform output -raw WORKERS_ENDPOINT)"

# Azure Managed Redis == Microsoft.Cache/redisEnterprise. Supported api-versions
# vary by region, so discover the latest stable one (override REDIS_API_VERSION).
sub="$(az account show --query id -o tsv --only-show-errors)"
api="${REDIS_API_VERSION:-}"
if [ -z "$api" ]; then
  api="$(az provider show --namespace Microsoft.Cache \
    --query "resourceTypes[?resourceType=='redisEnterprise'].apiVersions[]" -o tsv --only-show-errors \
    | grep -v preview | sort -r | head -1 || true)"
fi
[ -n "$api" ] || api="2024-10-01"

echo "[flush] locating Managed Redis in ${rg}..."
name="$(az resource list -g "$rg" --resource-type Microsoft.Cache/redisEnterprise \
  --query "[0].name" -o tsv --only-show-errors)"
[ -n "$name" ] || { echo "[flush] no Microsoft.Cache/redisEnterprise cluster in $rg" >&2; exit 1; }

host="$(az resource show -g "$rg" -n "$name" --resource-type Microsoft.Cache/redisEnterprise \
  --api-version "$api" --query properties.hostName -o tsv --only-show-errors)"
key="$(az rest --method post --only-show-errors \
  --url "https://management.azure.com/subscriptions/${sub}/resourceGroups/${rg}/providers/Microsoft.Cache/redisEnterprise/${name}/databases/default/listKeys?api-version=${api}" \
  --query primaryKey -o tsv)"

# Managed Redis: TLS on port 10000. FLUSHALL clears APIM's prefixed keys too.
echo "[flush] FLUSHALL on ${name} (${host}:10000)"
redis-cli -h "$host" -p 10000 --tls -a "$key" FLUSHALL

echo "[flush] verify (expect X-Cache: MISS on the next call):"
curl -si "$workers" | grep -iE '^(HTTP/|x-cache)' || true
