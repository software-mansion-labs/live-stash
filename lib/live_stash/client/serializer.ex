defmodule LiveStash.Serializer do
  @moduledoc false

  require Logger

  alias LiveStash.Utils

  @spec term_to_external(Phoenix.LiveView.Socket.t(), term(), term(), map()) ::
          {binary(), binary()}
  def term_to_external(socket, key, value, opts) do
    {term_to_string(key), encode_token(socket, value, opts)}
  end

  @spec external_to_term(Phoenix.LiveView.Socket.t(), map(), map()) :: map()
  def external_to_term(socket, stashed_state, opts) do
    Enum.reduce(stashed_state, %{}, fn {key, value}, acc ->
      with {:ok, decoded_key} <- string_to_term(key),
           {:ok, processed_value} <- decode_token(socket, value, opts) do
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

  defp term_to_string(value) do
    value
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  defp string_to_term(encoded_value) do
    with {:ok, decoded64} <- Base.decode64(encoded_value) do
      {:ok, Plug.Crypto.non_executable_binary_to_term(decoded64, [:safe])}
    else
      :error -> {:error, :invalid_base64}
    end
  rescue
    ArgumentError -> {:error, :invalid_term}
  end
end
