defmodule LiveStash.Adapters.ETS.Cleaner do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Adapters.ETS.State
  alias LiveStash.Utils

  @cleanup_interval Application.compile_env(:live_stash, :ets_cleanup_interval, 1 * 60 * 1_000)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.debug("[LiveStash] Cleaning up expired states...")

    clean_expired_states!()
    schedule_cleanup()

    Logger.debug("[LiveStash] Expired states cleaned up")

    {:noreply, state}
  rescue
    error ->
      err = Utils.exception_message("Could not clean up expired states", error, __STACKTRACE__)
      Logger.error(err)

      {:noreply, state}
  end

  @doc """
  Cleans up expired states from the ETS table.
  It uses a batching approach to avoid locking the table for too long.
  It bumps the delete_at time for records with alive processes and deletes records with dead processes.
  """
  @spec clean_expired_states!() :: :ok
  def clean_expired_states!() do
    now = System.os_time(:millisecond)

    case State.get_batch!(now) do
      {candidates, continuation} ->
        do_clear!(candidates, continuation, now)

      :"$end_of_table" ->
        :ok
    end
  end

  defp do_clear!(candidates, continuation, now) do
    Enum.each(candidates, fn {id, pid, ttl} ->
      if Process.alive?(pid) do
        new_delete_at = now + ttl
        State.bump_delete_at!(id, new_delete_at)
      else
        State.delete_by_id!(id)
      end
    end)

    case State.get_next_batch!(continuation) do
      {candidates, next_continuation} ->
        do_clear!(candidates, next_continuation, now)

      :"$end_of_table" ->
        :ok
    end
  end

  defp schedule_cleanup(), do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
