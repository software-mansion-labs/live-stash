defmodule LiveStash.Adapters.ETS.Context do
  @moduledoc false

  alias LiveStash.Utils
  alias LiveStash.Adapters.ETS.NodeHint
  alias Phoenix.LiveView

  @enforce_keys [
    :reconnected?,
    :secret,
    :id
  ]

  defstruct [
    :reconnected?,
    :secret,
    :id,
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

  @default_secret "live_stash"

  @doc """
  Builds context from socket and opts (e.g. in `on_mount` / `init_stash`).
  """
  @spec from_socket(LiveView.Socket.t(), keyword(), keyword()) :: t()
  def from_socket(socket, session, opts) do
    {session_key, opts} = Keyword.pop(opts, :session_key)

    evaluated_secret =
      if session_key, do: fetch_secret(session_key, session), else: @default_secret

    connect_params = get_connect_params(socket)
    mounts = if connect_params, do: connect_params["_mounts"], else: nil
    id = connect_params["stashId"] || UUID.uuid4()
    reconnected? = not is_nil(mounts) and mounts > 0
    node_hint = NodeHint.get_node_hint(socket, connect_params, evaluated_secret)

    new(opts, reconnected?, evaluated_secret, id, node_hint)
  end

  @spec new(keyword(), boolean(), binary(), binary(), atom() | nil) :: t()
  def new(user_opts, reconnected?, evaluated_secret, id, node_hint) do
    attrs =
      user_opts
      |> Keyword.put(:reconnected?, reconnected?)
      |> Keyword.put(:secret, evaluated_secret)
      |> Keyword.put(:id, id)
      |> Keyword.put(:node_hint, node_hint)

    struct!(__MODULE__, attrs)
  end

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
