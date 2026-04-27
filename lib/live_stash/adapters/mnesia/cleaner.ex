defmodule LiveStash.Adapters.Mnesia.Cleaner do
  @moduledoc false

  use GenServer
  use Amnesia

  require Logger

  alias LiveStash.Adapters.Mnesia.Database.State
  alias LiveStash.Utils

  @cleanup_interval Application.compile_env(:live_stash, :mnesia_cleanup_interval, 1 * 60 * 1_000)
  @batch_size Application.compile_env(:live_stash, :mnesia_cleanup_batch_size, 100)

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

  @batch_size Application.compile_env(:live_stash, :mnesia_cleanup_batch_size, 100)

  @spec clean_expired_states!() :: :ok
  def clean_expired_states!() do
    now = System.os_time(:second)
    current_node = node()

    Amnesia.transaction do
      State.expired_records(now)
      |> Stream.chunk_every(@batch_size)
      |> Enum.each(fn batch ->
        Enum.each(batch, fn {id, pid, ttl} ->
          record_node = node(pid)

          cond do
            record_node == current_node ->
              if Process.alive?(pid) do
                State.bump_delete_at!(id, now + ttl)
              else
                State.delete_by_id!(id)
              end

            record_node not in Node.list() ->
              State.delete_by_id!(id)

            true ->
              :ok
          end
        end)
      end)
    end

    :ok
  end

  defp schedule_cleanup(), do: Process.send_after(self(), :cleanup, @cleanup_interval)
end
