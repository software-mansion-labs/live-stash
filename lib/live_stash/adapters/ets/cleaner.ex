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
  Deletes all records whose `delete_at` has elapsed.

  TTL bumping for live LiveViews is handled by `LiveStash.Adapters.ETS.Hook`
  via periodic keep-alive ticks on the owning process, so this cleaner only
  needs to delete records whose owners stopped bumping them.
  """
  @spec clean_expired_states!() :: :ok
  def clean_expired_states!() do
    State.delete_expired!(System.os_time(:second))
    :ok
  end

  defp schedule_cleanup(), do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
