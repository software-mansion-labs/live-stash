defmodule LiveStash.Adapters.BrowserMemory.Context do
  @moduledoc """
  Holds the state and configuration for the BrowserMemory adapter.

  ## Fields
  * `:stored_keys` - A list of assign keys to automatically stash on every update.
  * `:reconnected?` - A boolean indicating whether the LiveView socket has successfully reconnected vs. a fresh mount.
  * `:stash_fingerprint` - A binary string representing the fingerprint of the stashed state. This is used to determine if the state has changed and needs to be re-stashed.
  * `:secret` - A binary string used as the cryptographic secret for signing or encrypting the data sent to the browser.
  * `:ttl` - Time-to-live for the stored browser data in milliseconds.
  * `:security_mode` - Defines the security approach applied to the client-side data (`:sign` to prevent tampering, or `:encrypt` to hide contents). Defaults to `:sign`.
  * `:key_set` - A `MapSet` used internally to track which keys are currently stored in the browser's memory, ensuring accurate synchronization and cleanup.
  """

  alias Phoenix.LiveView
  alias LiveStash.Adapters.Common

  @enforce_keys [
    :stored_keys,
    :reconnected?
  ]

  defstruct [
    :stored_keys,
    :reconnected?,
    stash_fingerprint: nil,
    secret: "live_stash",
    ttl: 5 * 60 * 1000,
    security_mode: :sign
  ]

  @type t :: %__MODULE__{
          stored_keys: [atom()],
          reconnected?: boolean(),
          stash_fingerprint: binary() | nil,
          secret: binary(),
          security_mode: :sign | :encrypt,
          ttl: integer()
        }

  @allowed_keys [
    :stored_keys,
    :reconnected?,
    :stash_fingerprint,
    :secret,
    :ttl,
    :security_mode
  ]

  @doc """
  Builds context from socket, session and opts (e.g. in `on_mount` / `init_stash`).
  """
  @spec new(LiveView.Socket.t(), keyword(), keyword()) :: t()
  def new(socket, session, opts) do
    {session_key, base_attrs} = Keyword.pop(opts, :session_key)

    base_attrs
    |> Common.maybe_put_secret(session_key, session)
    |> Keyword.put(
      :reconnected?,
      Common.reconnected?(Common.get_connect_params(socket))
    )
    |> Common.validate_attributes!(@allowed_keys)
    |> then(&struct!(__MODULE__, &1))
  end
end
