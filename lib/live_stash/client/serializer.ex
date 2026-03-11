defmodule LiveStash.Serializer do
  @moduledoc false

  require Logger

  alias LiveStash.Utils

  @spec term_to_external(Phoenix.LiveView.Socket.t(), term(), term(), map()) ::
          {binary(), binary(), binary()}
  def term_to_external(socket, key, value, opts) do
    {get_hash(key), encode_token(socket, key, opts), encode_token(socket, value, opts)}
  end

  @spec external_to_term(Phoenix.LiveView.Socket.t(), map(), map()) :: map()
  def external_to_term(socket, stashed_state, opts) do
    Enum.reduce(stashed_state, %{}, fn
      {_key_hash, %{"key" => encoded_key, "value" => encoded_value}}, acc ->
        with {:ok, decoded_key} <- decode_token(socket, encoded_key, opts),
             {:ok, processed_value} <- decode_token(socket, encoded_value, opts) do
          Map.put(acc, decoded_key, processed_value)
        else
          {:error, reason} ->
            warning =
              Utils.warning_message(
                "Could not recover a stashed item. Skipping.",
                reason
              )

            Logger.warning(warning)

            acc
        end

      {_key_hash, _malformed_payload}, acc ->
        Logger.warning("Malformed stashed state item received from client. Skipping.")
        acc
    end)
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
