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
    Logger.error(
      Utils.reason_message("Split-brain detected on Mnesia with node #{node}!", {:conflict, node})
    )

    if Application.get_env(:live_stash, :auto_heal_mnesia, false) do
      Logger.info(
        Utils.reason_message(
          "Auto-heal enabled. Attempting self-heal by removing local Mnesia copy and rejoining the cluster.",
          :conflict
        )
      )

      Task.Supervisor.start_child(LiveStash.Adapters.Mnesia.TaskSupervisor, fn ->
        perform_auto_heal()
      end)
    else
      Logger.warning(
        "live_stash auto-heal is disabled. Manual cluster intervention may be required."
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp perform_auto_heal() do
    try do
      Memento.Table.delete_copy(LiveStash.Adapters.Mnesia.State, node())
      Memento.Table.create_copy(LiveStash.Adapters.Mnesia.State, node(), :ram_copies)

      Memento.Table.wait([LiveStash.Adapters.Mnesia.State], 15_000)

      Logger.info("Successfully auto-healed LiveStash Mnesia State table.")
    rescue
      e ->
        Logger.error(
          "LiveStash auto-heal failed. The cluster might still be unreachable: #{inspect(e)}"
        )
    end
  end
end
