defmodule LiveStash.Adapters.Redis.Registry do
  @moduledoc """
  A module that manages the registry of LiveViews tracked locally.

  The record is stored in the following format:
  - id: the id of the LiveView
  - pid: the pid of the LiveView
  - delete_at: the timestamp when the tracking should be deleted or bumped
  - ttl: the time to live of the state
  """

  require Record

  alias LiveStash.Utils

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_redis_registry)
  @batch_size Application.compile_env(:live_stash, :ets_cleanup_batch_size, 100)

  Record.defrecord(:registry, [:id, :pid, :delete_at, :ttl])

  @type t ::
          record(:registry,
            id: term(),
            pid: pid(),
            delete_at: integer(),
            ttl: integer()
          )

  @typep continuation :: tuple() | :"$end_of_table"

  @doc """
  Creates the ETS table for tracking the LiveViews.
  Table name is configurable via the `:ets_table_name` config.
  """
  @spec create_table!() :: :ets.table()
  def create_table!() do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:keypos, 2},
      {:write_concurrency, true},
      {:decentralized_counters, true}
    ])
  end

  @doc """
  Creates a new tracking record for a LiveView.
  """
  @spec new(id :: term(), opts :: Keyword.t()) :: t()
  def new(id, opts) do
    ttl = Keyword.fetch!(opts, :ttl)

    registry(
      id: id,
      pid: self(),
      delete_at: System.os_time(:millisecond) + ttl,
      ttl: ttl
    )
  end

  @doc """
  Inserts a new tracking record into the ETS table.
  """
  @spec insert!(record :: tuple()) :: :ok
  def insert!(record) do
    :ets.insert(@table_name, record)
    :ok
  end

  @doc """
  Creates a new registry entry if it doesn't exist. Allows update only to the process that owns the registry record (matching pid), otherwise raises an error.
  """
  @spec put!(id :: term(), opts :: Keyword.t()) :: :ok
  def put!(id, opts) do
    pid = self()
    new_record = new(id, opts)

    match_spec = [
      {{:registry, id, pid, :_, :_}, [], [{new_record}]}
    ]

    if :ets.select_replace(@table_name, match_spec) == 0 do
      if not :ets.insert_new(@table_name, new_record) do
        msg =
          Utils.reason_message(
            "Registry entry with id #{inspect(id)} already exists for another process",
            :conflict
          )

        raise RuntimeError, msg
      end
    end

    :ok
  end

  @doc """
  Gets the tracking metadata of a LiveView from the ETS table.
  """
  @spec get_by_id!(id :: term()) :: {:ok, pid(), integer(), integer()} | :not_found
  def get_by_id!(id) do
    @table_name
    |> :ets.lookup(id)
    |> case do
      [{:registry, ^id, pid, delete_at, ttl}] -> {:ok, pid, delete_at, ttl}
      [] -> :not_found
    end
  end

  @doc """
  Deletes the tracking record of a LiveView from the ETS table.
  """
  @spec delete_by_id!(id :: term()) :: :ok
  def delete_by_id!(id) do
    :ets.delete(@table_name, id)
    :ok
  end

  @doc """
  Pops the tracking record of a LiveView from the ETS table, returning it and deleting the record.
  """
  @spec pop_by_id!(id :: term()) :: {:ok, pid(), integer(), integer()} | :not_found
  def pop_by_id!(id) do
    @table_name
    |> :ets.take(id)
    |> case do
      [{:registry, ^id, pid, delete_at, ttl}] -> {:ok, pid, delete_at, ttl}
      [] -> :not_found
    end
  end

  @doc """
  Gets a batch of state records from the ETS table.
  """
  @spec get_batch!(now :: integer()) ::
          {[{term(), pid(), integer()}], continuation()} | :"$end_of_table"
  def get_batch!(now) when is_integer(now) do
    spec = [
      {
        # Pattern: {:registry, id, pid, delete_at, ttl} (5 elements)
        {:registry, :"$1", :"$2", :"$3", :"$4"},
        # Guard
        [{:<, :"$3", now}],
        # Return: {id, pid, ttl}
        [{{:"$1", :"$2", :"$4"}}]
      }
    ]

    :ets.select(@table_name, spec, @batch_size)
  end

  @doc """
  Gets the next batch of state records from the ETS table.
  """
  @spec get_next_batch!(continuation :: continuation()) ::
          {[{term(), pid(), integer()}], continuation()} | :"$end_of_table"
  def get_next_batch!(:"$end_of_table"), do: :"$end_of_table"
  def get_next_batch!(continuation), do: :ets.select(continuation)

  @doc """
  Bumps the delete_at time of a state record in the ETS table.
  """
  @spec bump_delete_at!(id :: term(), time :: integer()) :: :ok
  def bump_delete_at!(id, time) when is_integer(time) do
    :ets.update_element(@table_name, id, {4, time})
    :ok
  end
end
