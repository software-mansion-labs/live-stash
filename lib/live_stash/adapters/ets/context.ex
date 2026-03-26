defmodule LiveStash.Adapters.ETS.Context do
  @moduledoc """
  Holds the state and configuration for the ETS adapter.

  ## Fields

  * `:reconnected?` - A boolean indicating whether the LiveView socket has successfully reconnected vs. a fresh mount.
  * `:id` - A unique identifier (UUID) representing the specific stash instance stored in the ETS table.
  * `:secret` - A binary string used as part of the record id in the ETS for security purposes.
  * `:ttl` - Time-to-live for the records kept in the ETS table, specified in milliseconds.
  * `:node_hint` - Information about the Elixir node that currently holds stashed state in the ETS. This is used to optimize state retrieval in a distributed deployment.
  """

  alias LiveStash.Adapters.ETS.NodeHint
  alias Phoenix.LiveView
  alias LiveStash.Adapters.Common

  @enforce_keys [
    :reconnected?,
    :id
  ]

  defstruct [
    :reconnected?,
    :id,
    secret: "live_stash",
    ttl: 5 * 60 * 1000,
    node_hint: nil
  ]

  @type t :: %__MODULE__{
          reconnected?: boolean(),
          secret: binary(),
          ttl: integer(),
          node_hint: atom() | nil,
          id: binary()
        }

  @doc """
  Builds context from socket, session and opts (e.g. in `on_mount` / `init_stash`).
  """
  @spec new(LiveView.Socket.t(), keyword(), keyword()) :: t()
  def new(socket, session, opts) do
    {session_key, base_attrs} = Keyword.pop(opts, :session_key)

    attrs = Common.maybe_put_secret(base_attrs, session_key, session)

    connect_params = Common.get_connect_params(socket) || %{}

    context =
      attrs
      |> Keyword.put(:reconnected?, Common.reconnected?(connect_params))
      |> Keyword.put(:id, get_in(connect_params, ["liveStash", "stashId"]) || UUID.uuid4())
      |> then(&struct!(__MODULE__, &1))

    node_hint = NodeHint.get_node_hint(socket, connect_params, context.secret)

    %{context | node_hint: node_hint}
  end
end
