defmodule LiveStash.Client do
  @moduledoc """
  A client-side stash that persists data in the browser's memory.
  """

  @behaviour LiveStash.Stash

  require Logger

  alias LiveStash.Utils

  alias Phoenix.LiveView

  @impl true
  def init_stash(socket, opts) do
    ttl = Keyword.fetch!(opts, :ttl)
    security_mode = Keyword.fetch!(opts, :security_mode)
    secret_fun = Keyword.fetch!(opts, :secret_fun)
    mounts = LiveView.get_connect_params(socket)["_mounts"]
    reconnected? = not is_nil(mounts) and mounts > 0

    # If mounts is set to 0 we are on a new connection and stashed state is no longer valid
    if not reconnected? do
      LiveView.push_event(socket, "live-stash:reset", %{})
    end

    socket
    |> LiveView.put_private(:live_stash_security_secret, secret_fun.(socket))
    |> LiveView.put_private(:live_stash_security_mode, security_mode)
    |> LiveView.put_private(:live_stash_ttl, ttl)
    |> LiveView.put_private(:live_stash_mode, :client)
    |> LiveView.put_private(:live_stash_reconnected?, reconnected?)
  end

  @impl true
  def stash(socket, key, value) do
    {external_key, external_value} =
      transform_to_external(
        socket,
        get_opts(socket),
        key,
        value
      )

    LiveView.push_event(socket, "live-stash:stash", %{key: external_key, value: external_value})
  end

  @impl true
  def recover_state(socket) do
    case LiveView.get_connect_params(socket) do
      %{"stashedState" => stashed_state} ->
        parsed_state = parse_state!(socket, get_opts(socket), stashed_state)

        {:recovered, parsed_state}

      _ ->
        {:not_found, %{}}
    end
  rescue
    error in [ArgumentError, FunctionClauseError] ->
      handle_recovery_error(
        error,
        __STACKTRACE__,
        "Could not recover stashed state. Error when decoding key and value to term."
      )

    error ->
      handle_recovery_error(error, __STACKTRACE__, "Could not recover stashed state.")
  end

  @impl true
  def reset_stash(socket) do
    LiveView.push_event(socket, "live-stash:reset", %{})
  end

  defp transform_to_external(_socket, %{security_mode: :encode} = _opts, key, value) do
    encoded_key = encode(key)
    encoded_value = encode(value)

    {encoded_key, encoded_value}
  end

  defp transform_to_external(socket, %{security_mode: :sign} = opts, key, value) do
    encoded_key = encode(key)
    signed_value = Phoenix.Token.sign(socket, opts[:security_secret], value, max_age: opts[:ttl])

    {encoded_key, signed_value}
  end

  defp transform_to_external(socket, %{security_mode: :encrypt} = opts, key, value) do
    encoded_key = encode(key)

    encrypted_value =
      Phoenix.Token.encrypt(socket, opts[:security_secret], value, max_age: opts[:ttl])

    {encoded_key, encrypted_value}
  end

  defp encode(value) do
    value
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  defp decode(encoded_value) do
    encoded_value
    |> Base.decode64!()
    |> Plug.Crypto.non_executable_binary_to_term()
  end

  defp parse_state!(_socket, %{security_mode: :encode} = _opts, stashed_state) do
    stashed_state
    |> Enum.map(fn {key, value} ->
      {decode(key), decode(value)}
    end)
    |> Enum.into(%{})
  end

  defp parse_state!(socket, %{security_mode: :sign} = opts, stashed_state) do
    Enum.reduce(stashed_state, %{}, fn {key, value}, acc ->
      case Phoenix.Token.verify(socket, opts[:security_secret], value, max_age: opts[:ttl]) do
        {:ok, verified_value} ->
          Map.put(acc, decode(key), verified_value)

        {:error, _reason} ->
          acc
      end
    end)
  end

  defp parse_state!(socket, %{security_mode: :encrypt} = opts, stashed_state) do
    Enum.reduce(stashed_state, %{}, fn {key, value}, acc ->
      case Phoenix.Token.decrypt(socket, opts[:security_secret], value, max_age: opts[:ttl]) do
        {:ok, decrypted_value} ->
          Map.put(acc, decode(key), decrypted_value)

        {:error, _reason} ->
          acc
      end
    end)
  end

  defp handle_recovery_error(error, stacktrace, message) do
    err = Utils.error_message(message, error, stacktrace)
    Logger.error(err)

    {:error, err}
  end

  defp get_opts(socket) do
    %{
      ttl: socket.private.live_stash_ttl,
      security_secret: socket.private.live_stash_security_secret,
      security_mode: socket.private.live_stash_security_mode
    }
  end
end
