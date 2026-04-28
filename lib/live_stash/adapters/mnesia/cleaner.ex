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

  @spec clean_expired_states!() :: :ok
  def clean_expired_states!() do
    now = System.os_time(:second)

    State.expired_records(now)
    |> Enum.each(fn {id, pid, ttl} ->
      if Process.alive?(pid) do
        State.bump_delete_at!(id, now + ttl)
      else
        State.delete_by_id!(id)
      end
    end)
  end

  defp schedule_cleanup(), do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
