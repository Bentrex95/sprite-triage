#!/bin/sh
# Runs `mix test` (and anything passed as arguments instead) inside a pinned Elixir image.
# Usage: scripts/docker-test.sh [command...]
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
image=${SPRITE_TRIAGE_IMAGE:-elixir:1.20-otp-28}
cmd=${*:-"mix test"}
exec docker run --rm --init --mount "type=bind,source=$here,target=/w" -w /w "$image" \
  sh -c "mix local.hex --force >/dev/null && mix local.rebar --force >/dev/null && mix deps.get >/dev/null && $cmd"
