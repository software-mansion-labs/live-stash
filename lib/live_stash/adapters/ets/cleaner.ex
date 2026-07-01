defmodule LiveStash.Adapters.ETS.Cleaner do
  @moduledoc false

  use GenServer

  require Logger

  alias LiveStash.Adapters.ETS.State
  alias LiveStash.Utils

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)

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
      err = Utils.exception_message("Failed to clean up expired states", error, __STACKTRACE__)
      Logger.error(err)

      {:noreply, state}
  end

  @doc """
  Deletes all records whose `delete_at` has elapsed.

  TTL bumping for live LiveViews is handled by `LiveStash.Adapters.ETS.Hook`
  via periodic keep-alive ticks on the owning process, so this cleaner only
  needs to delete records whose owners stopped bumping them.
  """
  @spec clean_expired_states!() :: :ok
  def clean_expired_states!() do
    if :ets.whereis(@table_name) == :undefined do
      Logger.warning(
        Utils.reason_message(
          "ETS table #{@table_name} not found during cleanup. Skipping cleanup cycle.",
          :not_found
        )
      )
    else
      State.delete_expired!(System.os_time(:second))
      :ok
    end
  end

  defp schedule_cleanup(),
    do: Process.send_after(self(), :cleanup, cleanup_interval())

  defp cleanup_interval do
    Application.get_env(:live_stash, :ets_cleanup_interval, 60_000)
  end
end
