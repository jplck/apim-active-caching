#!/usr/bin/env sh
# Generates the middleware's OpenAPI spec ON DEMAND and writes it to
# infra/modules/apim/data/openapi.json, where the apim module imports it inline
# (content_format = "openapi+json").
#
# Why: the workers API used to import from a live link
# (`${middleware_url}/openapi.json`), but APIM's management plane fetches that
# URL when the API is created during `terraform apply`. At that point the
# middleware is either still the placeholder image (azd deploys AFTER provision)
# or — with private networking — only reachable inside the VNet, so the fetch
# fails with a 400 ValidationError. Generating the spec from the FastAPI app and
# importing it inline decouples the API definition from the middleware being
# live/reachable.
#
# Wired as the azd `preprovision` hook (see azure.yaml) so the file exists before
# Terraform's file() read. Safe to run standalone before `terraform apply` too.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
mw_dir="$root_dir/middleware"
out_file="$root_dir/infra/modules/apim/data/openapi.json"
venv_dir="$mw_dir/.venv-openapi"

python="${PYTHON:-python3}"
if ! command -v "$python" >/dev/null 2>&1; then
  echo "gen-openapi: '$python' not found; set PYTHON to a Python 3 interpreter." >&2
  exit 1
fi

# Reuse a cached venv; (re)install deps only when requirements change.
req_file="$mw_dir/requirements.txt"
stamp="$venv_dir/.requirements.sha256"
need_install=0
if [ ! -d "$venv_dir" ]; then
  "$python" -m venv "$venv_dir"
  need_install=1
fi
cur_hash=$(cksum "$req_file" | awk '{print $1"-"$2}')
if [ ! -f "$stamp" ] || [ "$(cat "$stamp" 2>/dev/null)" != "$cur_hash" ]; then
  need_install=1
fi
if [ "$need_install" -eq 1 ]; then
  echo "gen-openapi: installing middleware dependencies into $venv_dir ..."
  "$venv_dir/bin/pip" install --quiet --upgrade pip >/dev/null
  "$venv_dir/bin/pip" install --quiet -r "$req_file"
  printf '%s' "$cur_hash" > "$stamp"
fi

echo "gen-openapi: writing $out_file"
mkdir -p "$(dirname -- "$out_file")"
PYTHONPATH="$mw_dir" "$venv_dir/bin/python" - "$out_file" <<'PY'
import json
import sys

from app.main import app

spec = app.openapi()
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(spec, fh, indent=2, sort_keys=True)
    fh.write("\n")
print("gen-openapi: OpenAPI %s, paths: %s" % (spec.get("openapi"), ", ".join(spec.get("paths", {}))))
PY
