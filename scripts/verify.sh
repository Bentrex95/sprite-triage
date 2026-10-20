#!/bin/sh
# The full check before a release: formatting, warnings, tests three times with random
# seeds (a flaky test once passed a single run by luck), the mutation check, and the demo
# image built and started (Docker, about 15 min). For everyday work `mix test` is enough.
set -eu
cd "$(dirname "$0")"
sh ./docker-test.sh "mix format --check-formatted && MIX_ENV=test mix compile --force --warnings-as-errors && mix test --warnings-as-errors && mix test --warnings-as-errors && mix test --warnings-as-errors && MIX_ENV=test mix run --no-start scripts/sabotage.exs"
sh ./demo-smoke.sh
