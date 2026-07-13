#!/usr/bin/env bash
# Live end-to-end check of the PASSIVE caching flow against a deployed stack.
#
# Flow (new architecture):
#   1. Trigger the refresher Container Apps Job → it pulls Workday (SOAP) and
#      UPSERTs the workers into Postgres. Wait until the execution Succeeds.
#   2. First GET on the APIM workers endpoint → cache MISS (APIM calls the
#      middleware backend, which reads Postgres, then stores the body in Redis).
#   3. Second GET → cache HIT (served straight from the external Redis cache).
#
# Endpoints/names come from Terraform outputs. Run from the repo root after
# `azd up` (or `terraform apply`): scripts/smoke-test.sh
set -euo pipefail

cd "$(dirname "$0")/../infra"

tf() { terraform output -raw "$1"; }

rg="$(tf RESOURCE_GROUP)"
job="$(tf REFRESHER_JOB_NAME)"
workers="$(tf WORKERS_ENDPOINT)"     # e.g. https://apim-xxxx.azure-api.net/workers

echo "Resource group : ${rg}"
echo "Refresher job  : ${job}"
echo "Workers endpoint: ${workers}"
echo

echo "1) Trigger the refresher job now (instead of waiting for cron):"
az containerapp job start -g "$rg" --name "$job" -o none
echo "   started; waiting for the execution to Succeed..."

# Poll the most recent execution until it leaves the Running/Unknown state.
status="Running"
for _ in $(seq 1 60); do
  status="$(az containerapp job execution list -g "$rg" --name "$job" \
    --query "sort_by([].{s:properties.status,t:properties.startTime}, &t)[-1].s" \
    -o tsv 2>/dev/null || echo Unknown)"
  case "$status" in
    Succeeded) echo "   execution: Succeeded"; break ;;
    Failed)    echo "   execution: Failed — check job logs" >&2; exit 1 ;;
    *)         printf '   execution: %s ...\n' "${status:-Unknown}"; sleep 10 ;;
  esac
done
[ "$status" = "Succeeded" ] || { echo "   timed out waiting for the job" >&2; exit 1; }

echo
echo "2) First read — warms the cache from the middleware/Postgres (expect X-Cache: MISS, HTTP 200):"
curl -si "$workers" | grep -iE '^(HTTP/|x-cache)' || true

echo
echo "3) Second read — served from Redis (expect X-Cache: HIT, HTTP 200):"
curl -si "$workers" | grep -iE '^(HTTP/|x-cache)' || true

echo
echo "Cached body (first 400 bytes):"
curl -s "$workers" | head -c 400; echo
