# Build context: repo root (live-stash/)
# The testing app has a local path dep on live_stash at "../"
# so the build context must include both.

FROM hexpm/elixir:1.19.1-erlang-28.1.1-debian-bookworm-20260518-slim AS build

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates curl gnupg \
  && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# Make the live_stash source available at the path the dep resolution expects
WORKDIR /app
COPY mix.exs ./
COPY lib/ ./lib/

# Build the testing app
WORKDIR /app/testing
COPY testing/mix.exs testing/mix.lock ./

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod
RUN mix deps.get --only prod
RUN mix deps.compile

COPY testing/config ./config
COPY testing/lib ./lib
COPY testing/priv ./priv
COPY testing/assets ./assets

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:bookworm-slim

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates locales \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app
COPY --from=build /app/testing/_build/prod/rel/testing .

ENV PHX_SERVER=true
ENV PORT=4000

CMD ["./bin/testing", "start"]
