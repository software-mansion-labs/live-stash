FROM elixir:1.15-alpine

RUN apk add --no-cache build-base inotify-tools git bash

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force