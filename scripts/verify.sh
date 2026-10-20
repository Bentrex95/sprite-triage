#!/bin/sh
# The one gate: formatting, warnings, tests three times with random seeds (a flaky test
# once passed a single run by luck), and the mutation check (Docker, about 10 min).
set -eu
cd "$(dirname "$0")"
exec sh ./docker-test.sh "mix format --check-formatted && MIX_ENV=test mix compile --force --warnings-as-errors && mix test --warnings-as-errors && mix test --warnings-as-errors && mix test --warnings-as-errors && MIX_ENV=test mix run --no-start scripts/sabotage.exs"
