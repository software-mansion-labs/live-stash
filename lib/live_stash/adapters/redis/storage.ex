defmodule LiveStash.Adapters.Redis.Storage do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Adapters.Redis.Registry

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Registry.create_table!()

    {:ok, %{}}
  end
end
