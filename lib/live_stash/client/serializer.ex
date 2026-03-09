defmodule LiveStash.Serializer do
  @moduledoc false

  require Logger

  def term_to_external(socket, opts, key, value) do
    {encode(key), secure_value(socket, opts, value)}
  end

  def external_to_term(socket, opts, stashed_state) do
    Enum.reduce(stashed_state, %{}, fn {key, value}, acc ->
      with {:ok, decoded_key} <- safe_decode(key),
           {:ok, processed_value} <- decode_value(socket, opts, value) do
        Map.put(acc, decoded_key, processed_value)
      else
        {:error, reason} ->
          Logger.warning(
            "Could not recover a stashed item (reason: #{inspect(reason)}). Skipping."
          )

          acc
      end
    end)
  end

  defp secure_value(_socket, %{security_mode: :encode}, value) do
    encode(value)
  end

  defp secure_value(socket, %{security_mode: :sign} = opts, value) do
    Phoenix.Token.sign(socket, opts[:security_secret], value, max_age: opts[:ttl])
  end

  defp secure_value(socket, %{security_mode: :encrypt} = opts, value) do
    Phoenix.Token.encrypt(socket, opts[:security_secret], value, max_age: opts[:ttl])
  end

  defp encode(value) do
    value
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  defp safe_decode(encoded_value) do
    with {:ok, decoded64} <- Base.decode64(encoded_value) do
      {:ok, Plug.Crypto.non_executable_binary_to_term(decoded64)}
    else
      :error -> {:error, :invalid_base64}
    end
  rescue
    ArgumentError -> {:error, :invalid_term}
  end

  defp decode_value(_socket, %{security_mode: :encode}, value) do
    safe_decode(value)
  end

  defp decode_value(socket, %{security_mode: :sign} = opts, value) do
    Phoenix.Token.verify(socket, opts[:security_secret], value, max_age: opts[:ttl])
  end

  defp decode_value(socket, %{security_mode: :encrypt} = opts, value) do
    Phoenix.Token.decrypt(socket, opts[:security_secret], value, max_age: opts[:ttl])
  end
end
