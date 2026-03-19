defmodule LiveStash.Adapters.ETS.Storage do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Adapters.ETS.State

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    State.create_table!()

    {:ok, %{}}
  end
end
