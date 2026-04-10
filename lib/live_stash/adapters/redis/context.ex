defmodule LiveStash.Adapters.Redis.Context do
  @moduledoc """
  Holds the state and configuration for the Redis adapter.

  ## Fields
  * `:assigns` - A list of assign keys to automatically stash on every update.
  * `:reconnected?` - A boolean indicating whether the LiveView socket has successfully reconnected vs. a fresh mount.
  * `:stash_fingerprint` - A binary string representing the fingerprint of the stashed state. This is used to determine if the state has changed and needs to be re-stashed.
  * `:id` - A unique identifier (UUID) representing the specific stash instance stored in the Redis database.
  * `:secret` - A binary string used as part of the record id in the Redis for security purposes.
  * `:ttl` - Time-to-live for the records kept in the Redis, specified in seconds.
  """

  alias Phoenix.LiveView
  alias LiveStash.Adapters.Common

  @enforce_keys [
    :assigns,
    :reconnected?,
    :id
  ]

  defstruct [
    :assigns,
    :reconnected?,
    :id,
    stash_fingerprint: nil,
    secret: "live_stash",
    ttl: 5 * 60 * 1000
  ]

  @type t :: %__MODULE__{
          assigns: [atom()],
          reconnected?: boolean(),
          stash_fingerprint: binary() | nil,
          secret: binary(),
          ttl: integer(),
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

    attrs
    |> Keyword.put(:reconnected?, Common.reconnected?(connect_params))
    |> Keyword.put(:id, get_in(connect_params, ["liveStash", "stashId"]) || Uniq.UUID.uuid4())
    |> then(&struct!(__MODULE__, &1))
  end
end
