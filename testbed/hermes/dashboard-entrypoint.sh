#!/bin/sh
set -eu
export HERMES_HOME="${HERMES_HOME:-/data/hermes}"
seed-config.sh "$HERMES_HOME"
exec hermes serve --host 0.0.0.0 --port 9119
