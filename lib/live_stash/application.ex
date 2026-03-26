defmodule LiveStash.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    adapters = Application.get_env(:live_stash, :adapters, [LiveStash.Adapter.default()])

    children =
      adapters
      |> Enum.filter(fn adapter ->
        Code.ensure_loaded?(adapter)

        function_exported?(adapter, :child_spec, 1)
      end)

    opts = [strategy: :one_for_one, name: LiveStash.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
