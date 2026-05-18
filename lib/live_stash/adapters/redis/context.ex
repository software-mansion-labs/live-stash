defmodule LiveStash.Adapters.Redis.Context do
  @moduledoc """
  Holds the state and configuration for the Redis adapter.

  ## Fields
  * `:stored_keys` - A list of assign keys to automatically stash on every update.
  * `:reconnected?` - A boolean indicating whether the LiveView socket has successfully reconnected vs. a fresh mount.
  * `:stash_fingerprint` - A binary string representing the fingerprint of the stashed state. This is used to determine if the state has changed and needs to be re-stashed.
  * `:id` - A unique identifier (UUID) representing the specific stash instance stored in the Redis database.
  * `:secret` - A binary string used as part of the record id in the Redis for security purposes.
  * `:ttl` - Time-to-live for the records kept in the Redis, specified in seconds.
  * `:version` - An optional value used to validate stashed state on recovery. If set, the recovered payload must carry the same version or it is rejected and the Redis key is deleted. Defaults to `nil` (no version check).
  """

  alias Phoenix.LiveView
  alias LiveStash.Adapters.Common
  alias LiveStash.Utils

  @enforce_keys [
    :stored_keys,
    :reconnected?,
    :id
  ]

  defstruct [
    :stored_keys,
    :reconnected?,
    :id,
    stash_fingerprint: nil,
    secret: "live_stash",
    ttl: 5 * 60,
    version: nil
  ]

  @type t :: %__MODULE__{
          stored_keys: [atom()],
          reconnected?: boolean(),
          stash_fingerprint: binary() | nil,
          secret: binary(),
          ttl: integer(),
          id: binary(),
          version: term()
        }

  @allowed_keys [
    :stored_keys,
    :reconnected?,
    :stash_fingerprint,
    :secret,
    :ttl,
    :id,
    :version
  ]

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
    |> Keyword.put(:id, get_in(connect_params, ["liveStash", "stashId"]) || Utils.generate_id())
    |> Common.validate_attributes!(@allowed_keys)
    |> then(&struct!(__MODULE__, &1))
  end
end
