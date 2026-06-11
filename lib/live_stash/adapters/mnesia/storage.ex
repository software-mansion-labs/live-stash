defmodule LiveStash.Adapters.Mnesia.Storage do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Adapters.Mnesia.State
  alias LiveStash.Utils

  @wait_timeout 15_000
  @retry_delay 5_000
  @max_retries 3
  @task_supervisor LiveStash.Adapters.Mnesia.TaskSupervisor

  @type state :: %__MODULE__{
          healing?: boolean(),
          retries_left: non_neg_integer(),
          auto_heal?: boolean(),
          reconcile_task: Task.t() | nil,
          reconcile_pending?: boolean()
        }
  defstruct healing?: false,
            retries_left: @max_retries,
            auto_heal?: true,
            reconcile_task: nil,
            reconcile_pending?: false

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Memento.start()
    {:ok, _node} = :mnesia.subscribe(:system)

    :ok = :net_kernel.monitor_nodes(true)
    State.ensure_cluster_table!()

    auto_heal? = Application.get_env(:live_stash, :mnesia_auto_heal, true)
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

      state.reconcile_task != nil ->
        Logger.info(
          Utils.message("Mnesia cluster reconciliation in progress. Deferring split-brain heal.")
        )

        {:noreply, state}

      node() > remote_node ->
        Logger.info(Utils.message("Yielding state to #{remote_node}. Attempting auto-heal."))

        {:noreply, %{state | healing?: true, retries_left: @max_retries}, {:continue, :heal}}

      true ->
        Logger.info(
          Utils.message(
            "This node's state was selected over #{remote_node}. Node #{remote_node} is attempting auto-heal."
          )
        )

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:heal_retry, state) do
    {:noreply, state, {:continue, :heal}}
  end

  @impl true
  def handle_info({:nodeup, node}, %{healing?: true} = state) do
    Logger.info(Utils.message("Node #{node} connected during a heal. Not reconciling."))

    {:noreply, state}
  end

  def handle_info({:nodeup, node}, %{reconcile_task: %Task{}} = state) do
    Logger.info(
      Utils.message(
        "Node #{node} connected while reconciling. Will re-check when the current pass finishes."
      )
    )

    {:noreply, %{state | reconcile_pending?: true}}
  end

  def handle_info({:nodeup, node}, state) do
    Logger.info(Utils.message("Node #{node} connected. Reconciling Mnesia cluster membership."))

    {:noreply, start_reconcile(state)}
  end

  @impl true
  def handle_info({ref, :ok}, %{reconcile_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    Logger.info(Utils.message("Mnesia cluster reconciliation complete."))

    {:noreply, finish_reconcile(state)}
  end

  def handle_info({ref, other}, %{reconcile_task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    Logger.error(Utils.reason_message("Mnesia cluster reconciliation failed", other))

    {:noreply, retry_reconcile(state)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{reconcile_task: %Task{ref: ref}} = state
      ) do
    Logger.error(Utils.reason_message("Mnesia cluster reconciliation task exited", reason))

    {:noreply, retry_reconcile(state)}
  end

  def handle_info(:reconcile_retry, %{reconcile_task: %Task{}} = state) do
    {:noreply, state}
  end

  def handle_info(:reconcile_retry, state) do
    {:noreply, start_reconcile(state)}
  end

  @impl true
  def handle_info({:nodedown, _node}, state) do
    {:noreply, state}
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

  defp start_reconcile(state) do
    task =
      Task.Supervisor.async_nolink(@task_supervisor, fn ->
        State.ensure_cluster_table!(Node.list())
      end)

    %{state | reconcile_task: task, reconcile_pending?: false}
  end

  defp finish_reconcile(%{reconcile_pending?: true} = state) do
    start_reconcile(%{state | reconcile_task: nil})
  end

  defp finish_reconcile(state) do
    %{state | reconcile_task: nil}
  end

  defp retry_reconcile(%{reconcile_pending?: true} = state) do
    start_reconcile(%{state | reconcile_task: nil})
  end

  defp retry_reconcile(state) do
    Process.send_after(self(), :reconcile_retry, @retry_delay)
    %{state | reconcile_task: nil}
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
