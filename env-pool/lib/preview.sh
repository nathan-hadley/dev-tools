#!/bin/bash
set -e
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ENV_ID="${1:?Usage: env-pool preview <env-id>}"

load_env_meta "$ENV_ID"
prepare_ios_preview "$ENV_ID"
save_env_meta "$ENV_ID"

info "Preview ready for $ENV_ID (sim=$SIM_NAME port=$METRO_PORT)"
echo "$SIM_UDID"
