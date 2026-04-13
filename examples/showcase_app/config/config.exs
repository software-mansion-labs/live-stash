# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :live_stash,
  adapters: [LiveStash.Adapters.ETS, LiveStash.Adapters.BrowserMemory, LiveStash.Adapters.Redis],
  redis: "redis://localhost:6379"

config :showcase_app, :scopes,
  user: [
    default: true,
    module: ShowcaseApp.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: ShowcaseApp.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :showcase_app,
  ecto_repos: [ShowcaseApp.Repo],
  generators: [timestamp_type: :utc_datetime]

config :showcase_app, ShowcaseApp.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: Path.expand("../showcase_app_dev.db", Path.dirname(__ENV__.file))


# Configure the endpoint
config :showcase_app, ShowcaseAppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ShowcaseAppWeb.ErrorHTML, json: ShowcaseAppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ShowcaseApp.PubSub,
  live_view: [signing_salt: "elkkDNDq"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :showcase_app, ShowcaseApp.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  showcase_app: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  showcase_app: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
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
