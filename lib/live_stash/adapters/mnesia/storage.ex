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
  def handle_info({:mnesia_system_event, {:inconsistent_database, _context, remote_node}}, state) do
    Logger.error(
      Utils.reason_message(
        "Mnesia split-brain detected with #{remote_node}",
        :conflict
      )
    )

    if Application.get_env(:live_stash, :auto_heal_mnesia, false) do
      if node() > remote_node do
        Logger.info("[LiveStash] Yielding state to #{remote_node}. Attempting auto-heal.")

        Task.Supervisor.start_child(LiveStash.Adapters.Mnesia.TaskSupervisor, fn ->
          perform_sacrifice_and_heal()
        end)
      end
    else
      Logger.warning(
        Utils.reason_message(
          "LiveStash auto-heal disabled. Manual Mnesia reconciliation required.",
          :conflict
        )
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  defp perform_sacrifice_and_heal(retries \\ 3)

  defp perform_sacrifice_and_heal(0) do
    Logger.error(
      Utils.reason_message(
        "LiveStash auto-heal exhausted all retries. Local table replica may be missing. Manual Mnesia restart required.",
        :error
      )
    )
  end

  defp perform_sacrifice_and_heal(retries) do
    target_table = LiveStash.Adapters.Mnesia.State

    try do
      with :ok <- Memento.Table.delete_copy(target_table, node()),
           :ok <- Memento.Table.create_copy(target_table, node(), :ram_copies),
           :ok <- wait_for_table(target_table) do
        Logger.info("[LiveStash] Successfully sacrificed and healed Mnesia State table.")
      else
        {:error, reason} ->
          schedule_retry(retries, reason)
      end
    rescue
      e ->
        schedule_retry(retries, e)
    end
  end

  defp wait_for_table(table) do
    case Memento.Table.wait([table], 15_000) do
      :ok -> :ok
      {:timeout, _} -> {:error, :timeout}
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_retry(retries_left, reason) do
    Logger.warning(
      Utils.reason_message(
        "LiveStash auto-heal attempt failed (#{inspect(reason)}). Retrying in 5 seconds...",
        :retry
      )
    )

    Process.sleep(5_000)
    perform_sacrifice_and_heal(retries_left - 1)
  end
end
