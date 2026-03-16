defmodule LiveStash.Serializer do
  @moduledoc false

  require Logger

  alias LiveStash.Utils

  @spec term_to_external(Phoenix.LiveView.Socket.t(), term(), term(), map()) ::
          map()
  def term_to_external(socket, key, value, opts) do
    %{
      key: encode_key(key),
      value: encode_token(socket, value, opts)
    }
  end

  @spec term_to_external(Phoenix.LiveView.Socket.t(), map(), map()) :: binary()
  def term_to_external(socket, value, opts) do
    encode_token(socket, value, opts)
  end

  @spec external_to_term(Phoenix.LiveView.Socket.t(), map(), map(), map()) ::
          map() | {:error, String.t()}
  def external_to_term(socket, stashed_state, stashed_keys, opts) do
    with {:ok, key_list} <- get_key_list(socket, stashed_keys, opts) do
      Enum.reduce_while(key_list, %{}, fn key, acc ->
        process_stashed_key(key, acc, socket, stashed_state, opts)
      end)
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

  defp get_key_list(socket, stashed_keys, opts) do
    case decode_token(socket, stashed_keys, opts) do
      {:ok, decoded_key_list} ->
        {:ok, decoded_key_list}

      {:error, reason} ->
        msg =
          Utils.reason_message(
            "Failed to retrieve key list from stashed keys",
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
