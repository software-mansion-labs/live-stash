defmodule LiveStash.Adapters.BrowserMemory.Context do
  @moduledoc """
  Holds the state and configuration for the BrowserMemory adapter.

  ## Fields

  * `:reconnected?` - A boolean indicating whether the LiveView socket has successfully reconnected vs. a fresh mount.
  * `:secret` - A binary string used as the cryptographic secret for signing or encrypting the data sent to the browser. Defaults to `"live_stash"`.
  * `:ttl` - Time-to-live for the stored browser data in milliseconds. Defaults to 5 minutes (`300_000` ms).
  * `:security_mode` - Defines the security approach applied to the client-side data (`:sign` to prevent tampering, or `:encrypt` to hide contents). Defaults to `:sign`.
  * `:key_set` - A `MapSet` used internally to track which keys are currently stored in the browser's memory, ensuring accurate synchronization and cleanup.
  """

  alias Phoenix.LiveView
  alias LiveStash.Utils

  @enforce_keys [
    :reconnected?
  ]

  defstruct [
    :reconnected?,
    secret: "live_stash",
    ttl: 5 * 60 * 1000,
    security_mode: :sign,
    key_set: MapSet.new()
  ]

  @type t :: %__MODULE__{
          reconnected?: boolean(),
          secret: binary(),
          security_mode: :sign | :encrypt,
          ttl: integer(),
          key_set: MapSet.t()
        }

  @doc """
  Builds context from socket, session and opts (e.g. in `on_mount` / `init_stash`).
  """
  @spec new(LiveView.Socket.t(), keyword(), keyword()) :: t()
  def new(socket, session, opts) do
    {session_key, base_attrs} = Keyword.pop(opts, :session_key)

    base_attrs
    |> maybe_put_secret(session_key, session)
    |> Keyword.put(:reconnected?, reconnected?(get_connect_params(socket)))
    |> then(&struct!(__MODULE__, &1))
  end

  defp maybe_put_secret(attrs, nil, _session), do: attrs

  defp maybe_put_secret(attrs, session_key, session) do
    Keyword.put(attrs, :secret, fetch_secret(session_key, session))
  end

  defp reconnected?(%{"_mounts" => mounts}) when is_integer(mounts), do: mounts > 0
  defp reconnected?(_params), do: false

  defp fetch_secret(session_key, session) do
    secret =
      try do
        Map.fetch!(session, session_key)
      rescue
        e ->
          msg =
            Utils.exception_message(
              "The provided session_key failed to return a valid secret.",
              e,
              __STACKTRACE__
            )

          reraise ArgumentError.exception(msg), __STACKTRACE__
      end

    if not is_binary(secret) do
      raise ArgumentError,
            "The provided session_key returned an invalid type. Expected a binary string."
    end

    :sha256
    |> :crypto.hash(secret)
    |> Base.encode64(padding: false)
  end

  defp get_connect_params(socket) do
    try do
      LiveView.get_connect_params(socket)
    rescue
      e in RuntimeError ->
        msg =
          Utils.exception_message(
            "Failed to get connect params. This likely means that LiveStash.init_stash/2 is being called outside of the mount lifecycle or before the socket is fully initialized.",
            e,
            __STACKTRACE__
          )

        reraise RuntimeError.exception(msg), __STACKTRACE__
    end
  end
end
