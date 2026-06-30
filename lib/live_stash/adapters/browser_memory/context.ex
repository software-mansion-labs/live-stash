defmodule LiveStash.Adapters.BrowserMemory.Context do
  @moduledoc """
  Holds the state and configuration for the BrowserMemory adapter.

  ## Fields
  * `:stored_keys` - A list of assign keys to automatically stash on every update.
  * `:reconnected?` - A boolean indicating whether the LiveView socket has successfully reconnected vs. a fresh mount.
  * `:stash_fingerprint` - A binary string representing the fingerprint of the stashed state. This is used to determine if the state has changed and needs to be re-stashed.
  * `:secret` - A binary string used as the cryptographic secret for signing or encrypting the data sent to the browser.
  * `:ttl` - Time-to-live for the stored browser data in seconds.
  * `:security_mode` - Required. Defines the security approach applied to the client-side data (`:sign` to prevent tampering, or `:encrypt` to hide contents).
  * `:key_set` - A `MapSet` used internally to track which keys are currently stored in the browser's memory, ensuring accurate synchronization and cleanup.
  * `:version` - An optional value used to validate stashed state on recovery. If set, the recovered payload must carry the same version or it is rejected and browser memory is cleared. Defaults to `nil` (no version check).
  """

  alias Phoenix.LiveView
  alias LiveStash.Adapters.Common
  alias LiveStash.Utils

  @enforce_keys [
    :stored_keys,
    :reconnected?,
    :security_mode
  ]

  defstruct [
    :stored_keys,
    :reconnected?,
    :security_mode,
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
          security_mode: :sign | :encrypt,
          ttl: integer(),
          version: term()
        }

  @allowed_keys [
    :stored_keys,
    :reconnected?,
    :stash_fingerprint,
    :secret,
    :ttl,
    :security_mode,
    :version
  ]

  @doc """
  Builds context from socket, session and opts (e.g. in `on_mount` / `init_stash`).
  """
  @spec new(LiveView.Socket.t(), keyword(), keyword()) :: t()
  def new(socket, session, opts) do
    {session_key, base_attrs} = Keyword.pop(opts, :session_key)

    base_attrs
    |> ensure_security_mode!()
    |> Common.maybe_put_secret(session_key, session)
    |> Keyword.put(
      :reconnected?,
      Common.reconnected?(Common.get_connect_params(socket))
    )
    |> Common.validate_attributes!(@allowed_keys)
    |> then(&struct!(__MODULE__, &1))
  end

  defp ensure_security_mode!(attrs) do
    if Keyword.has_key?(attrs, :security_mode) do
      attrs
    else
      msg =
        Utils.reason_message(
          "Missing required option: :security_mode. You must explicitly configure how client-side data is secured. Example: use LiveStash, adapter: LiveStash.Adapters.BrowserMemory, security_mode: :sign, stored_keys: [:count]",
          :invalid
        )

      raise ArgumentError, msg
    end
  end
end
