defmodule LiveStash.Adapters.Redis.Cleaner do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Adapters.Redis.Registry
  alias LiveStash.Adapters.Redis
  alias LiveStash.Utils

  @refresh_interval Application.compile_env(:live_stash, :ttl_refresh_interval, 1 * 1_000)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:ttl_refresh, state) do
    Logger.debug("[LiveStash] Refreshing active states in Redis...")

    clean_expired_states!()
    schedule_cleanup()

    Logger.debug("[LiveStash] Active states refreshed")

    {:noreply, state}
  rescue
    error ->
      err = Utils.exception_message("Could not refresh active states", error, __STACKTRACE__)
      Logger.error(err)

      {:noreply, state}
  end

  @doc """
  Cleans up expired local trackers and bumps TTL in Redis for active ones.
  It uses a batching approach to avoid locking the local ETS table for too long.
  """
  @spec clean_expired_states!() :: :ok
  def clean_expired_states!() do
    now = System.os_time(:millisecond)

    case Registry.get_batch!(now) do
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
        Registry.bump_delete_at!(id, new_delete_at)
      else
        Logger.debug("deleting for id #{id}")
        Registry.delete_by_id!(id)

        case Redis.command(["DEL", id]) do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "[LiveStash] Failed to delete stash for #{id} in Redis: #{inspect(reason)}"
            )
        end
      end
    end)

    case Registry.get_next_batch!(continuation) do
      {candidates, next_continuation} ->
        do_clear!(candidates, next_continuation, now)

      :"$end_of_table" ->
        :ok
    end
  end

  defp schedule_cleanup(), do: Process.send_after(self(), :ttl_refresh, @refresh_interval)
end
