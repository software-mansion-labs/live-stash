defmodule LiveStash.Adapters.Common do
  @moduledoc false

  alias Phoenix.LiveView
  alias LiveStash.Utils

  def hash_term(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
  end

  def get_connect_params(socket) do
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

  def reconnected?(%{"_mounts" => mounts}) when is_integer(mounts), do: mounts > 0
  def reconnected?(_params), do: false

  def maybe_put_secret(attrs, nil, _session), do: attrs

  def maybe_put_secret(attrs, session_key, session) do
    Keyword.put(attrs, :secret, fetch_secret(session_key, session))
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
end
