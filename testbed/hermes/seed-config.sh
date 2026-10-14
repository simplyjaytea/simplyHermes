#!/bin/sh
# Point a Hermes home at the scripted fake LLM. Usage: seed-config.sh <HERMES_HOME> [owner]
set -eu
home="$1"
mkdir -p "$home"
cat > "$home/config.yaml" <<YAML
model:
  provider: custom
  base_url: ${FAKE_LLM_URL:-http://fake-llm:8700/v1}
  default: fake-model
  api_key: fake
YAML
if [ -n "${2:-}" ]; then chown -R "$2" "$home"; fi
