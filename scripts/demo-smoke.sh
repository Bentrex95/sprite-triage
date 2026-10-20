#!/bin/sh
# Builds the demo image from the Dockerfile, starts it as Fly would (FLY_APP_NAME set,
# no key) and checks that the page answers in demo mode. Needs Docker and curl.
set -eu
here=$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))
tag=sprite-triage-smoke
name=sprite-triage-smoke-$$
port=${SPRITE_TRIAGE_SMOKE_PORT:-4099}

docker build -q -t "$tag" "$here" >/dev/null
docker run -d --rm --name "$name" -p "127.0.0.1:$port:4090" -e FLY_APP_NAME=smoke "$tag" >/dev/null
trap 'docker stop "$name" >/dev/null 2>&1 || true' EXIT

page=""
for _ in $(seq 1 30); do
  page=$(curl -fsS "http://127.0.0.1:$port/" 2>/dev/null) && break
  sleep 1
done

echo "$page" | grep -q 'id="demo-banner"' || { echo "demo smoke: FAIL (no demo page)"; docker logs "$name"; exit 1; }
echo "$page" | grep -q 'data-phx-session' || { echo "demo smoke: FAIL (no LiveView)"; exit 1; }
echo "demo smoke: PASS"
