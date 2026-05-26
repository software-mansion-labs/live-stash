# Build context: repo root (live-stash/)
# The testing app has a local path dep on live_stash at "../"
# so the build context must include both.

FROM hexpm/elixir:1.19.1-erlang-28.1.1-alpine-3.21.0 AS build

RUN apk add --no-cache build-base git nodejs npm

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

RUN mix assets.deploy
RUN mix compile
RUN mix release

FROM alpine:3.21.0

RUN apk add --no-cache libstdc++ openssl ncurses-libs

WORKDIR /app
COPY --from=build /app/testing/_build/prod/rel/testing .

ENV PHX_SERVER=true
ENV PORT=4000

CMD ["./bin/testing", "start"]
