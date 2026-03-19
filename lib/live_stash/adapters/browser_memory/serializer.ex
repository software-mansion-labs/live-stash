defmodule LiveStash.Adapters.BrowserMemory.Serializer do
  @moduledoc false

  require Logger

  alias LiveStash.Utils

  @spec term_to_external(Phoenix.LiveView.Socket.t(), term(), term(), map()) ::
          {binary(), binary()}
  def term_to_external(socket, key, value, opts) do
    {encode_key(key), encode_token(socket, value, opts)}
  end

  @spec term_to_external(Phoenix.LiveView.Socket.t(), term(), map()) :: binary()
  def term_to_external(socket, value, opts) do
    encode_token(socket, value, opts)
  end

  @spec external_to_term(Phoenix.LiveView.Socket.t(), map(), binary(), map()) ::
          {:ok, {map(), list()}} | {:error, String.t()}
  def external_to_term(socket, stashed_state, stashed_keys, opts) do
    with {:ok, key_set} <- get_key_set(socket, stashed_keys, opts),
         recovered_state when is_map(recovered_state) <-
           Enum.reduce_while(key_set, %{}, fn key, acc ->
             process_stashed_key(key, acc, socket, stashed_state, opts)
           end) do
      {:ok, {recovered_state, key_set}}
    end
  end

  defp process_stashed_key(key, acc, socket, stashed_state, opts) do
    key_encoded = encode_key(key)

    with {:ok, encoded_value} <- Map.fetch(stashed_state, key_encoded),
         {:ok, decoded_value} <- decode_token(socket, encoded_value, opts) do
      {:cont, Map.put(acc, key, decoded_value)}
    else
      _ ->
        msg =
          Utils.reason_message(
            "Failed to decode stashed assign with key #{inspect(key)}. It may be missing or malformed.",
            :error
          )

        {:halt, {:error, msg}}
    end
  end

  defp get_key_set(socket, stashed_keys, opts) do
    case decode_token(socket, stashed_keys, opts) do
      {:ok, decoded_key_list} ->
        {:ok, MapSet.new(decoded_key_list)}

      {:error, reason} ->
        msg =
          Utils.reason_message(
            "Failed to retrieve key set from stashed keys",
            reason
          )

        {:error, msg}
    end
  end

  defp encode_token(socket, value, %{security_mode: :sign} = opts) do
    Phoenix.Token.sign(socket, opts.secret, value, max_age: opts.ttl)
  end

  defp encode_token(socket, value, %{security_mode: :encrypt} = opts) do
    Phoenix.Token.encrypt(socket, opts.secret, value, max_age: opts.ttl)
  end

  defp decode_token(socket, value, %{security_mode: :sign} = opts) do
    Phoenix.Token.verify(socket, opts.secret, value, max_age: opts.ttl)
  end

  defp decode_token(socket, value, %{security_mode: :encrypt} = opts) do
    Phoenix.Token.decrypt(socket, opts.secret, value, max_age: opts.ttl)
  end

  defp encode_key(key) do
    key
    |> :erlang.term_to_binary()
    |> Base.encode64(padding: false)
  end
end
