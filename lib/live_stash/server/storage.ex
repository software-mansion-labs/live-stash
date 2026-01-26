defmodule LiveStash.Server.Storage do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Server.State

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    State.create_table!()

    {:ok, %{}}
  end
end
