#!/usr/bin/env bash
# Live end-to-end check of the active-caching flow against a deployed stack.
# Reads endpoints/keys from Terraform outputs. Run from repo root after `azd up`
# (or `terraform apply`): scripts/smoke-test.sh
set -euo pipefail

cd "$(dirname "$0")/../infra"

gw="$(terraform output -raw APIM_GATEWAY_URL)"
job="$(terraform output -raw REFRESHER_JOB_NAME)"
rg="$(terraform output -raw RESOURCE_GROUP)"

echo "1) Read BEFORE priming — expect X-Cache: MISS (503):"
curl -si "${gw}/workers" | grep -iE '^(HTTP/|x-cache)' || true

echo
echo "2) Trigger the refresher job now (instead of waiting for cron):"
az containerapp job start -n "$job" -g "$rg" -o none
echo "   waiting for the cache to fill..."
sleep 30

echo
echo "3) Read AFTER priming — expect X-Cache: HIT (200) served from Redis:"
curl -si "${gw}/workers" | grep -iE '^(HTTP/|x-cache)' || true
echo
echo "Full cached body:"
curl -s "${gw}/workers" | head -c 400; echo
