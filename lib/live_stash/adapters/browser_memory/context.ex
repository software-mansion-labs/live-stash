defmodule LiveStash.Adapters.BrowserMemory.Context do
  @moduledoc """
  Holds the state and configuration for the BrowserMemory adapter.

  ## Fields

  * `:reconnected?` - A boolean indicating whether the LiveView socket has successfully reconnected vs. a fresh mount.
  * `:secret` - A binary string used as the cryptographic secret for signing or encrypting the data sent to the browser.
  * `:ttl` - Time-to-live for the stored browser data in milliseconds.
  * `:security_mode` - Defines the security approach applied to the client-side data (`:sign` to prevent tampering, or `:encrypt` to hide contents). Defaults to `:sign`.
  * `:key_set` - A `MapSet` used internally to track which keys are currently stored in the browser's memory, ensuring accurate synchronization and cleanup.
  """

  alias Phoenix.LiveView
  alias LiveStash.Adapters.Common

  @enforce_keys [
    :reconnected?
  ]

  defstruct [
    :reconnected?,
    secret: "live_stash",
    ttl: 5 * 60,
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
    |> maybe_put_ttl()
    |> Common.maybe_put_secret(session_key, session)
    |> Keyword.put(:reconnected?, Common.reconnected?(Common.get_connect_params(socket)))
    |> then(&struct!(__MODULE__, &1))
  end

  defp maybe_put_ttl(attrs) do
    case Keyword.fetch(attrs, :ttl) do
      {:ok, ttl} -> Keyword.put(attrs, :ttl, max(div(ttl, 1000), 1))
      :error -> attrs
    end
  end
end
