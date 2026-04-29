defmodule LiveStash.Adapters.Mnesia.State do
  @moduledoc false

  use Memento.Table,
    attributes: [:id, :pid, :delete_at, :ttl, :state],
    type: :set

  alias LiveStash.Utils

  @type t :: %__MODULE__{
          id: term(),
          pid: pid(),
          delete_at: integer(),
          ttl: integer(),
          state: map()
        }

  def new(id, state, opts) do
    ttl = Keyword.fetch!(opts, :ttl)

    %__MODULE__{
      id: id,
      pid: self(),
      delete_at: System.os_time(:second) + ttl,
      ttl: ttl,
      state: state
    }
  end

  def setup_cluster_state! do
    nodes = Node.list()

    if nodes == [] do
      Memento.start()

      case Memento.Table.create(__MODULE__, ram_copies: [node()]) do
        :ok -> :ok
        {:error, {:already_exists, _}} -> :ok
        {:error, reason} -> raise "Could not create Mnesia table: #{inspect(reason)}"
      end
    else
      Memento.start()

      Memento.add_nodes(nodes)

      case Memento.Table.create_copy(__MODULE__, node(), :ram_copies) do
        :ok -> :ok
        {:error, {:already_exists, _, _}} -> :ok
        {:error, reason} -> raise "Could not copy Mnesia table: #{inspect(reason)}"
      end
    end

    Memento.Table.wait([__MODULE__], 15_000)

    :ok
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

      {:error, reason} ->
        msg = Utils.reason_message("Mnesia transaction aborted", reason)
        raise RuntimeError, msg

      {:ok, _result} ->
        :ok
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

  def expired_records(now) when is_integer(now) do
    Memento.transaction!(fn ->
      Memento.Query.select(__MODULE__, {:<, :delete_at, now})
      |> Enum.filter(&locally_owned_or_from_disconnected_node?/1)
      |> Enum.map(fn record -> {record.id, record.pid, record.ttl} end)
    end)
  end

  defp locally_owned_or_from_disconnected_node?(%__MODULE__{pid: pid}) do
    owner_node = node(pid)

    owner_node == node() or owner_node not in Node.list()
  end

  def bump_delete_at!(id, time) when is_integer(time) do
    Memento.transaction!(fn ->
      case Memento.Query.read(__MODULE__, id) do
        nil ->
          :ok

        record ->
          Memento.Query.write(%{record | delete_at: time})
          :ok
      end
    end)
  end
end
