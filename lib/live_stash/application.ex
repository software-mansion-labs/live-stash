defmodule LiveStash.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    env_adapters = Application.get_env(:live_stash, :adapters, [])
    default_adapter = LiveStash.default_adapter()

    adapters =
      if default_adapter in env_adapters do
        env_adapters
      else
        env_adapters ++ [default_adapter]
      end

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
