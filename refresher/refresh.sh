#!/bin/sh
# Active cache pre-filler. Runs on a schedule (Container Apps Job cron).
# One call: GET the workers API with the refresh token. APIM's refresh branch
# pulls a full load from Workday and cache-stores it in the external Redis cache
# (through APIM, so the key namespace matches what the read path looks up).
set -eu

: "${APIM_GATEWAY_URL:?APIM_GATEWAY_URL is required}"
: "${REFRESH_TOKEN:?REFRESH_TOKEN is required}"

echo "[refresher] refreshing cache via ${APIM_GATEWAY_URL}/workers"
bytes="$(curl -fsS \
  -H "X-Refresh-Token: ${REFRESH_TOKEN}" \
  "${APIM_GATEWAY_URL}/workers" | wc -c | tr -d ' ')"

echo "[refresher] done (${bytes} bytes cached)"
