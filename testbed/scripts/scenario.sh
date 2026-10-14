#!/usr/bin/env bash
# Set the sticky fake-LLM scenario. Usage: scripts/scenario.sh tool_call   (empty = default "text")
# Per message, `[[scenario:NAME]]` in the prompt overrides this.
set -euo pipefail
curl -fsS -X POST http://127.0.0.1:8700/__scenario -d "{\"name\": \"${1:-}\"}"
echo
