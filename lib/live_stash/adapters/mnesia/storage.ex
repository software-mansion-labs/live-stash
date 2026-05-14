defmodule LiveStash.Adapters.Mnesia.Storage do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Adapters.Mnesia.State
  alias LiveStash.Utils

  @wait_timeout 15_000
  @retry_delay 5_000
  @max_retries 3

  @type state :: %__MODULE__{
          healing?: boolean(),
          retries_left: non_neg_integer(),
          auto_heal?: boolean()
        }
  defstruct healing?: false, retries_left: @max_retries, auto_heal?: false

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    State.setup_cluster_state!()
    {:ok, _node} = :mnesia.subscribe(:system)

    auto_heal? = Application.get_env(:live_stash, :auto_heal_mnesia, false)
    {:ok, %__MODULE__{auto_heal?: auto_heal?}}
  end

  @impl true
  def handle_info({:mnesia_system_event, {:inconsistent_database, _context, remote_node}}, state) do
    Logger.error(
      Utils.reason_message("Mnesia split-brain detected with #{remote_node}", :conflict)
    )

    cond do
      not state.auto_heal? ->
        Logger.warning(
          Utils.reason_message(
            "LiveStash Mnesia auto-heal disabled. Manual Mnesia reconciliation required.",
            :conflict
          )
        )

        {:noreply, state}

      state.healing? ->
        {:noreply, state}

      node() > remote_node ->
        Logger.info(Utils.message("Yielding state to #{remote_node}. Attempting auto-heal."))

        {:noreply, %{state | healing?: true, retries_left: @max_retries}, {:continue, :heal}}

      true ->
        Logger.info(
          Utils.message("Attempting to reclaim state from #{remote_node}. Attempting auto-heal.")
        )

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:heal_retry, state) do
    {:noreply, state, {:continue, :heal}}
  end

  @impl true
  def handle_info(_message, state) do
    {:noreply, state}
  end

  @impl true
  def handle_continue(:heal, state) do
    case run_heal() do
      :ok ->
        Logger.info(Utils.message("Mnesia State table copy dropped and recreated successfully."))
        {:noreply, %{state | healing?: false, retries_left: @max_retries}}

      {:error, reason} ->
        schedule_retry(state, reason)
    end
  end

  defp run_heal do
    with :ok <- Memento.Table.delete_copy(State, node()),
         :ok <- Memento.Table.create_copy(State, node(), :ram_copies) do
      wait_for_table(State)
    end
  rescue
    e ->
      Logger.error(Utils.exception_message("Mnesia auto-heal raised", e, __STACKTRACE__))
      {:error, e}
  end

  defp wait_for_table(table) do
    case Memento.Table.wait([table], @wait_timeout) do
      {:timeout, _} -> {:error, :timeout}
      other -> other
    end
  end

  defp schedule_retry(%{retries_left: 1} = state, reason) do
    Logger.error(
      Utils.reason_message(
        "Mnesia auto-heal exhausted all retries. Manual Mnesia restart required.",
        reason
      )
    )

    {:noreply, %{state | healing?: false, retries_left: @max_retries}}
  end

  defp schedule_retry(state, reason) do
    Logger.warning(
      Utils.reason_message(
        "Mnesia auto-heal attempt failed. Retrying in #{div(@retry_delay, 1000)}s...",
        reason
      )
    )

    Process.send_after(self(), :heal_retry, @retry_delay)
    {:noreply, %{state | retries_left: state.retries_left - 1}}
  end
end
