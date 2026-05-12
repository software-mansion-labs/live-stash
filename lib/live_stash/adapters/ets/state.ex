defmodule LiveStash.Adapters.ETS.State do
  @moduledoc """
  A module that manages the state of LiveViews stored on the server. It uses ETS to store the state.

  The state is stored in the following format:
  - id: the id of the LiveView
  - pid: the pid of the LiveView
  - delete_at: the timestamp (in seconds) when the state should be deleted
  - state: the state of the LiveView
  """

  require Record

  alias LiveStash.Utils

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_server_storage)

  Record.defrecord(:state, [:id, :pid, :delete_at, :state])

  @type t ::
          record(:state,
            id: term(),
            pid: pid(),
            delete_at: integer(),
            state: map()
          )

  @doc """
  Creates the ETS table for storing the state of LiveViews.
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
  Creates a new state record for a LiveView.
  """
  @spec new(id :: term(), state :: map(), opts :: Keyword.t()) :: t()
  def new(id, state, opts) do
    ttl = Keyword.fetch!(opts, :ttl)

    state(
      id: id,
      pid: self(),
      delete_at: System.os_time(:second) + ttl,
      state: state
    )
  end

  @doc """
  Inserts a new state record for a LiveView into the ETS table.
  """
  @spec insert!(record :: tuple()) :: :ok
  def insert!(record) do
    :ets.insert(@table_name, record)
    :ok
  end

  @doc """
  Puts a new state map into the state of a LiveView or creates a new state record if it doesn't exist. Allows update only to the process that owns the state record (matching pid), otherwise raises an error.
  """
  @spec put!(id :: term(), state :: map(), opts :: Keyword.t()) :: :ok
  def put!(id, state, opts) do
    pid = self()
    new_record = new(id, state, opts)

    match_spec = [
      {{:state, id, pid, :_, :_}, [], [{new_record}]}
    ]

    if :ets.select_replace(@table_name, match_spec) == 0 do
      if not :ets.insert_new(@table_name, new_record) do
        msg =
          Utils.reason_message(
            "State with id #{inspect(id)} already exists for another process",
            :conflict
          )

        raise RuntimeError, msg
      end
    end

    :ok
  end

  @doc """
  Gets the state of a LiveView from the ETS table.
  """
  @spec get_by_id!(id :: term()) :: {:ok, map()} | :not_found
  def get_by_id!(id) do
    @table_name
    |> :ets.lookup(id)
    |> case do
      [{:state, ^id, _pid, _delete_at, state}] -> {:ok, state}
      [] -> :not_found
    end
  end

  @doc """
  Deletes the state of a LiveView from the ETS table.
  """
  @spec delete_by_id!(id :: term()) :: :ok
  def delete_by_id!(id) do
    :ets.delete(@table_name, id)
    :ok
  end

  @doc """
  Pops the state of a LiveView from the ETS table, returning it and deleting the record.
  """
  @spec pop_by_id!(id :: term()) :: :not_found | {:ok, map()}
  def pop_by_id!(id) do
    @table_name
    |> :ets.take(id)
    |> case do
      [{:state, ^id, _pid, _delete_at, state}] -> {:ok, state}
      [] -> :not_found
    end
  end

  @doc """
  Refreshes the `delete_at` of a state record to `now + ttl`.

  No-op if the record does not exist.
  """
  @spec bump_delete_at!(id :: term(), ttl :: integer()) :: :ok
  def bump_delete_at!(id, ttl) when is_integer(ttl) do
    :ets.update_element(@table_name, id, {4, System.os_time(:second) + ttl})
    :ok
  end

  @doc """
  Deletes every record whose `delete_at` is strictly less than `now`.

  Uses `:ets.select_delete/2` with a guard so the whole sweep happens inside
  ETS as a single atomic operation per row, without copying records to the
  caller's heap.
  """
  @spec delete_expired!(now :: integer()) :: non_neg_integer()
  def delete_expired!(now) when is_integer(now) do
    match_spec = [
      {
        {:state, :_, :_, :"$1", :_},
        [{:<, :"$1", now}],
        [true]
      }
    ]

    :ets.select_delete(@table_name, match_spec)
  end
end
