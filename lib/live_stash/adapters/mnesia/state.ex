defmodule LiveStash.Adapters.Mnesia.State do
  @moduledoc false

  use Memento.Table,
    attributes: [:id, :pid, :delete_at, :state],
    type: :set

  require Logger
  alias LiveStash.Utils

  # `Memento.transaction/1`'s spec claims it always returns `{:ok, _} | {:error, _}`,
  # but in reality returns :ok. The `:ok ->` branch in `put!/3` is therefore reachable.
  @dialyzer {:no_match, put!: 3}

  @type t :: %__MODULE__{
          id: term(),
          pid: pid(),
          delete_at: integer(),
          state: map()
        }

  def new(id, state, opts) do
    ttl = Keyword.fetch!(opts, :ttl)

    %__MODULE__{
      id: id,
      pid: self(),
      delete_at: System.os_time(:second) + ttl,
      state: state
    }
  end

  def setup_cluster_state!() do
    Memento.start()

    ensure_table_created!()
    wait_for_table!()
  end

  defp ensure_table_created!() do
    Node.list()
    |> init_table()
    |> handle_create_result!()
  end

  defp init_table([]) do
    Memento.Table.create(__MODULE__, ram_copies: [node()])
  end

  defp init_table(nodes) do
    Memento.add_nodes(nodes)
    Memento.Table.create_copy(__MODULE__, node(), :ram_copies)
  end

  defp handle_create_result!(:ok), do: :ok
  defp handle_create_result!({:error, {:already_exists, _}}), do: :ok
  defp handle_create_result!({:error, {:already_exists, _, _}}), do: :ok

  defp handle_create_result!({:error, reason}) do
    raise RuntimeError, Utils.reason_message("Failed to set up Mnesia table", reason)
  end

  defp wait_for_table!() do
    case Memento.Table.wait([__MODULE__], 15_000) do
      :ok ->
        :ok

      {:timeout, bad} ->
        raise RuntimeError,
              Utils.reason_message("Mnesia table did not become ready", {:timeout, bad})

      {:error, reason} ->
        raise RuntimeError, Utils.reason_message("Mnesia table wait failed", reason)
    end
  end

  def insert!(record) do
    Memento.transaction!(fn ->
      Memento.Query.write(record)
    end)

    :ok
  end

  def put!(id, state, opts) do
    pid = self()
    record = new(id, state, opts)

    transaction_result =
      Memento.transaction(fn ->
        case Memento.Query.read(__MODULE__, id) do
          nil ->
            Memento.Query.write(record)
            :ok

          %__MODULE__{pid: ^pid} ->
            Memento.Query.write(record)
            :ok

          %__MODULE__{} ->
            Memento.Transaction.abort(:conflict)
        end
      end)

    case transaction_result do
      :ok ->
        :ok

      {:ok, _result} ->
        :ok

      {:error, reason} ->
        msg = Utils.reason_message("Mnesia transaction aborted", reason)
        raise RuntimeError, msg
    end
  end

  def get_by_id!(id) do
    Memento.transaction!(fn ->
      case Memento.Query.read(__MODULE__, id) do
        nil -> :not_found
        %__MODULE__{state: state} -> {:ok, state}
      end
    end)
  end

  def delete_by_id!(id) do
    Memento.transaction!(fn ->
      Memento.Query.delete(__MODULE__, id)
    end)

    :ok
  end

  @doc """
  Refreshes the `delete_at` of a record to `now + ttl`. No-op if the record
  does not exist.
  """
  def bump_delete_at!(id, ttl) when is_integer(ttl) do
    Memento.transaction!(fn ->
      case Memento.Query.read(__MODULE__, id) do
        nil ->
          :ok

        record ->
          Memento.Query.write(%{record | delete_at: System.os_time(:second) + ttl})
          :ok
      end
    end)
  end

  @doc """
  Deletes every record whose `delete_at` is strictly less than `now`.
  """
  def delete_expired!(now) when is_integer(now) do
    Memento.transaction!(fn ->
      match_head = {__MODULE__, :"$1", :_, :"$2", :_}
      guards = [{:<, :"$2", now}]
      projection = [:"$1"]

      ids = :mnesia.select(__MODULE__, [{match_head, guards, projection}])

      Enum.each(ids, &Memento.Query.delete(__MODULE__, &1))

      length(ids)
    end)
  end
end
