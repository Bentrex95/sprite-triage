# The public demo: the page against the simulated API. No token, nothing sent to Fly.
# Build and run locally:
#   docker build -t sprite-triage-demo . && docker run --rm -p 127.0.0.1:4090:4090 sprite-triage-demo
FROM elixir:1.20-otp-28 AS build

ENV MIX_ENV=prod
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv
RUN mix release

# The elixir image is Debian trixie; the release needs the same system libraries.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --home /app app

ENV LANG=C.UTF-8 \
    SPRITE_TRIAGE_IP=0.0.0.0 \
    SPRITE_TRIAGE_SERVER=true \
    SPRITE_TRIAGE_DEMO=true \
    SPRITE_TRIAGE_PUBLIC_DEMO=true

WORKDIR /app
COPY --from=build --chown=app /app/_build/prod/rel/sprite_triage ./
USER app

EXPOSE 4090
CMD ["bin/sprite_triage", "start"]
