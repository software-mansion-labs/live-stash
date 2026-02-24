defmodule ShowcaseApp.Repo do
  use Ecto.Repo,
    otp_app: :showcase_app,
    adapter: Ecto.Adapters.SQLite3
end
