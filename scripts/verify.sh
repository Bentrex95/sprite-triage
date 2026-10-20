#!/bin/sh
# Before a release: formatting, no warnings, the tests, and the demo image built and
# started (Docker, a few minutes). For everyday work `mix test` is enough.
set -eu
cd "$(dirname "$0")"
sh ./docker-test.sh "mix format --check-formatted && MIX_ENV=test mix compile --force --warnings-as-errors && mix test --warnings-as-errors"
sh ./demo-smoke.sh
