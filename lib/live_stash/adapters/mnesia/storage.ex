defmodule LiveStash.Adapters.Mnesia.Storage do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Adapters.Mnesia.State
  alias LiveStash.Utils

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    State.setup_cluster_state!()
    {:ok, _node} = :mnesia.subscribe(:system)

    {:ok, %{}}
  end

  @impl true
  def handle_info({:mnesia_system_event, {:inconsistent_database, _context, node}}, state) do
    msg =
      Utils.reason_message(
        "Split-brain on Mnesia table State on #{node}!",
        {:conflict, node}
      )

    Logger.error(msg)

    spawn(fn ->
      msg =
        Utils.reason_message(
          "Attempting self-heal by removing local Mnesia copy and rejoining the cluster.",
          :conflict
        )

      Logger.info(msg)

      Memento.Table.delete_copy(LiveStash.Adapters.Mnesia.State, node())
      Memento.Table.create_copy(LiveStash.Adapters.Mnesia.State, node(), :ram_copies)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end
end
