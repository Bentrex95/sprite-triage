# The public demo: the page against the simulated API. No token, nothing sent to Fly.
# Build and run locally:
#   docker build -t sprite-triage-demo . && docker run --rm -p 127.0.0.1:4090:4090 sprite-triage-demo
FROM elixir:1.20-otp-28

ENV MIX_ENV=prod \
    SPRITE_TRIAGE_IP=0.0.0.0 \
    SPRITE_TRIAGE_PUBLIC_DEMO=true

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv
RUN mix compile

EXPOSE 4090
CMD ["mix", "sprite_triage.demo"]
