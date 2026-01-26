defmodule LiveStash.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    Supervisor.start_link([LiveStash.Server.Storage, LiveStash.Server.Cleaner],
      strategy: :one_for_one
    )
  end
end
