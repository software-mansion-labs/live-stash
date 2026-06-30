defmodule LiveStash.Adapters.BrowserMemory.Serializer do
  @moduledoc false

  require Logger

  alias Phoenix.LiveView.Socket

  @spec encode_token(socket :: Socket.t(), value :: term(), opts :: map()) ::
          binary()
  def encode_token(socket, value, %{security_mode: :sign} = opts) do
    compressed_value = compress_term(value)
    Phoenix.Token.sign(socket, opts.secret, compressed_value, max_age: opts.ttl)
  end

  def encode_token(socket, value, %{security_mode: :encrypt} = opts) do
    compressed_value = compress_term(value)
    Phoenix.Token.encrypt(socket, opts.secret, compressed_value, max_age: opts.ttl)
  end

  @spec decode_token(socket :: Socket.t(), value :: binary(), opts :: map()) ::
          :not_found | {:error, :invalid | :missing} | {:ok, term()}
  def decode_token(socket, value, %{security_mode: :sign} = opts) do
    socket
    |> Phoenix.Token.verify(opts.secret, value, max_age: opts.ttl)
    |> decode_verified()
  end

  def decode_token(socket, value, %{security_mode: :encrypt} = opts) do
    socket
    |> Phoenix.Token.decrypt(opts.secret, value, max_age: opts.ttl)
    |> decode_verified()
  end

  defp decode_verified({:ok, binary}), do: decompress_term(binary)
  defp decode_verified({:error, :expired}), do: :not_found
  defp decode_verified(error), do: error

  defp compress_term(term) do
    :erlang.term_to_binary(term, [{:compressed, 1}])
  end

  defp decompress_term(binary) do
    try do
      {:ok, :erlang.binary_to_term(binary)}
    rescue
      ArgumentError -> {:error, :invalid}
    end
  end
end
