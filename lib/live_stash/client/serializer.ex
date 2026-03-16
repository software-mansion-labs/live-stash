defmodule LiveStash.Serializer do
  @moduledoc false

  require Logger

  alias LiveStash.Utils

  @spec term_to_external(Phoenix.LiveView.Socket.t(), term(), term(), map()) ::
          map()
  def term_to_external(socket, key, value, opts) do
    %{
      key_hash: get_hash(key),
      key: encode_token(socket, key, opts),
      value: encode_token(socket, value, opts)
    }
  end

  @spec external_to_term(Phoenix.LiveView.Socket.t(), map(), map()) :: map()
  def external_to_term(socket, stashed_state, opts) do
    {key_list, stashed_state} = get_key_list(socket, stashed_state, opts)

    Enum.reduce(key_list, %{}, fn key, acc ->
      key_hash = get_hash(key)

      with {:ok, %{"key" => encoded_key, "value" => encoded_value}} <-
             Map.fetch(stashed_state, key_hash),
           {:ok, decoded_key} <- decode_token(socket, encoded_key, opts),
           {:ok, decoded_value} <- decode_token(socket, encoded_value, opts) do
        Map.put(acc, decoded_key, decoded_value)
      else
        :error ->
          msg =
            Utils.reason_message(
              "Key #{inspect(key)} is present in key_list, but missing from stashed state.",
              :missing
            )

          raise RuntimeError, msg

        {:ok, _malformed_payload} ->
          msg =
            Utils.reason_message(
              "Malformed payload in stashed state for key #{inspect(key)}",
              :invalid
            )

          raise RuntimeError, msg

        {:error, reason} ->
          msg =
            Utils.reason_message(
              "Failed to decode stashed value for key #{inspect(key)}",
              reason
            )

          raise RuntimeError, msg
      end
    end)
  end

  defp get_key_list(socket, stashed_state, opts) do
    {%{"key" => encoded_key, "value" => encoded_key_list}, stashed_state} =
      Map.pop!(stashed_state, get_hash(:key_list))

    with {:ok, _decoded_key} <- decode_token(socket, encoded_key, opts),
         {:ok, decoded_key_list} <- decode_token(socket, encoded_key_list, opts) do
      {decoded_key_list, stashed_state}
    else
      {:error, reason} ->
        msg =
          Utils.reason_message(
            "Key list of stashed assigns was malformed",
            reason
          )

        raise RuntimeError, msg
    end
  rescue
    KeyError ->
      msg =
        Utils.reason_message(
          "Key list of stashed assigns is missing from stashed state",
          :missing
        )

      raise RuntimeError, msg
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

  defp get_hash(value) do
    value
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode64(padding: false)
  end
end
