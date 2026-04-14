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
  alias LiveStash.Utils

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

  @doc """
  Builds context from socket, session and opts (e.g. in `on_mount` / `init_stash`).
  """
  @spec new(LiveView.Socket.t(), keyword(), keyword()) :: t()
  def new(socket, session, opts) do
    {session_key, base_attrs} = Keyword.pop(opts, :session_key)

    base_attrs
    |> Common.maybe_put_secret(session_key, session)
    |> Keyword.put(:reconnected?, Common.reconnected?(Common.get_connect_params(socket)))
    |> validate_attributes!()
    |> then(&struct!(__MODULE__, &1))
  end

  defp validate_attributes!(attrs) do
    Enum.each(attrs, fn attr ->
      error_msg =
        case attr do
          {:security_mode, mode} when mode not in [:sign, :encrypt] ->
            "Invalid security_mode: #{inspect(mode)}. Expected :sign or :encrypt."

          {:ttl, ttl} when not is_integer(ttl) ->
            "Invalid ttl: #{inspect(ttl)}. Expected an integer."

          {:secret, secret} when not is_binary(secret) ->
            "Invalid secret: #{inspect(secret)}. Expected a binary (string)."

          {:stash_fingerprint, fp} when not (is_binary(fp) or is_nil(fp)) ->
            "Invalid stash_fingerprint: #{inspect(fp)}. Expected a binary or nil."

          {:reconnected?, reconnected} when not is_boolean(reconnected) ->
            "Invalid reconnected?: #{inspect(reconnected)}. Expected a boolean."

          {:stored_keys, keys} ->
            if is_list(keys) and Enum.all?(keys, &is_atom/1) do
              nil
            else
              "Invalid stored_keys: #{inspect(keys)}. Expected a list of atoms."
            end

          {unknown_key, _value}
          when unknown_key not in [
                 :stored_keys,
                 :reconnected?,
                 :stash_fingerprint,
                 :secret,
                 :ttl,
                 :security_mode
               ] ->
            "Unknown attribute passed: #{inspect(unknown_key)}"

          _ ->
            nil
        end

      if error_msg do
        msg = Utils.reason_message(error_msg, :invalid)
        raise ArgumentError, msg
      end
    end)

    attrs
  end
end
