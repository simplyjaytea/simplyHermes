#!/usr/bin/env bash
# Start the testbed. Usage: scripts/up.sh [--profile oidc]   (env: TESTBED_NO_BUILD=1 to skip image build)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data/ssh
if [ ! -f data/ssh/id_ed25519 ]; then
  if command -v ssh-keygen >/dev/null; then
    ssh-keygen -q -t ed25519 -N "" -f data/ssh/id_ed25519
  else
    docker run --rm -v "$PWD/data/ssh:/k" --entrypoint ssh-keygen simplyhermes-testbed/hermes:pinned -q -t ed25519 -N "" -f /k/id_ed25519
  fi
  cp data/ssh/id_ed25519.pub data/ssh/authorized_keys
fi
chmod 600 data/ssh/id_ed25519 || true
build=(--build)
[ -n "${TESTBED_NO_BUILD:-}" ] && build=(--no-build)
docker compose "$@" up -d --wait "${build[@]}"
echo "dashboard http://127.0.0.1:9119 (tester / testbed-password)"
echo "ssh -p 2222 -i testbed/data/ssh/id_ed25519 tester@127.0.0.1"
echo "fake llm http://127.0.0.1:8700"
