defmodule LiveStash.Adapters.Mnesia.Context do
  @moduledoc false

  alias LiveStash.Adapters.Common
  alias Phoenix.LiveView

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
    ttl: 5 * 60
  ]

  @type t :: %__MODULE__{
          stored_keys: [atom()],
          reconnected?: boolean(),
          stash_fingerprint: binary() | nil,
          secret: binary(),
          ttl: integer(),
          id: binary()
        }

  @allowed_keys [
    :stored_keys,
    :reconnected?,
    :stash_fingerprint,
    :secret,
    :ttl,
    :id
  ]

  @spec new(LiveView.Socket.t(), keyword(), keyword()) :: t()
  def new(socket, session, opts) do
    {session_key, base_attrs} = Keyword.pop(opts, :session_key)

    attrs = Common.maybe_put_secret(base_attrs, session_key, session)

    connect_params = Common.get_connect_params(socket) || %{}

    context =
      attrs
      |> Keyword.put(:reconnected?, Common.reconnected?(connect_params))
      |> Keyword.put(:id, get_in(connect_params, ["liveStash", "stashId"]) || Uniq.UUID.uuid4())
      |> Common.validate_attributes!(@allowed_keys)
      |> then(&struct!(__MODULE__, &1))

    context
  end
end
