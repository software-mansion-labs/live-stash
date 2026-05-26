# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :live_stash,
  adapters: [LiveStash.Adapters.ETS, LiveStash.Adapters.BrowserMemory, LiveStash.Adapters.Redis],
  redis: System.get_env("LIVE_STASH_REDIS_URL", "redis://localhost:6379")

config :testing,
  generators: [timestamp_type: :utc_datetime]

config :testing, Testing.PromEx,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

# Configure the endpoint
config :testing, TestingWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TestingWeb.ErrorHTML, json: TestingWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Testing.PubSub,
  live_view: [signing_salt: "0B/v5WnF"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  testing: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
