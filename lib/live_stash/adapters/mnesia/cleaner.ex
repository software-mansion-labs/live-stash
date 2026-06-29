defmodule LiveStash.Adapters.Mnesia.Cleaner do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Adapters.Mnesia.State
  alias LiveStash.Utils

  @cleanup_interval Application.compile_env(:live_stash, :mnesia_cleanup_interval, 1 * 60 * 1_000)

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
    clean_expired_states!()
    schedule_cleanup()

    {:noreply, state}
  rescue
    error ->
      err = Utils.exception_message("Could not clean up expired states", error, __STACKTRACE__)
      Logger.error(err)

      {:noreply, state}
  end

  @doc """
  Deletes all records whose `delete_at` has expired.

  TTL bumping for live LiveViews is handled by
  `LiveStash.Adapters.Mnesia.Hook` via periodic keep-alive ticks on the owning
  process, so this cleaner only needs to delete records whose owners stopped
  bumping them. Deletion uses dirty Mnesia select/delete in `State.delete_expired!/1`
  so cleanup does not run inside a transaction.
  """
  @spec clean_expired_states!() :: :ok
  def clean_expired_states!() do
    if state_table_available?() do
      State.delete_expired!(System.os_time(:second))
      :ok
    else
      Logger.warning(
        Utils.message("Mnesia State table not available during cleanup. Skipping cleanup cycle.")
      )

      :ok
    end
  end

  defp state_table_available?() do
    :mnesia.system_info(:is_running) == :yes and
      :mnesia.table_info(State, :where_to_read) != :nowhere
  rescue
    _ -> false
  end

  defp schedule_cleanup(), do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
