defmodule LiveStash.Adapters.ETS.Context do
  @moduledoc """
  Holds the state and configuration for the ETS adapter.

  ## Fields

  * `:reconnected?` - A boolean indicating whether the LiveView socket has successfully reconnected vs. a fresh mount.
  * `:id` - A unique identifier (UUID) representing the specific stash instance stored in the ETS table.
  * `:secret` - A binary string used as part of the record id in the ETS for security purposes. Defaults to `"live_stash"`.
  * `:ttl` - Time-to-live for the records kept in the ETS table, specified in milliseconds. Defaults to 5 minutes (`300_000` ms).
  * `:node_hint` - Information about the Elixir node that currently holds stashed state in the ETS. This is used to optimize state retrieval in a distributed deployment.
  """

  alias LiveStash.Utils
  alias LiveStash.Adapters.ETS.NodeHint
  alias Phoenix.LiveView

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

    attrs = maybe_put_secret(base_attrs, session_key, session)

    connect_params = get_connect_params(socket) || %{}

    context =
      attrs
      |> Keyword.put(:reconnected?, reconnected?(connect_params))
      |> Keyword.put(:id, connect_params["stashId"] || UUID.uuid4())
      |> then(&struct!(__MODULE__, &1))

    node_hint = NodeHint.get_node_hint(socket, connect_params, context.secret)

    %{context | node_hint: node_hint}
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
