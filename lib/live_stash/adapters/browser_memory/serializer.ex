defmodule LiveStash.Adapters.BrowserMemory.Serializer do
  @moduledoc false

  require Logger

  alias Phoenix.LiveView.Socket

  @spec encode_token(socket :: Socket.t(), value :: term(), opts :: map()) ::
          binary()
  def encode_token(socket, value, %{security_mode: :sign} = opts) do
    Phoenix.Token.sign(socket, opts.secret, value, max_age: convert_ms_to_seconds(opts.ttl))
  end

  def encode_token(socket, value, %{security_mode: :encrypt} = opts) do
    Phoenix.Token.encrypt(socket, opts.secret, value, max_age: convert_ms_to_seconds(opts.ttl))
  end

  @spec decode_token(
          socket :: Socket.t(),
          stashed_state :: binary(),
          opts :: map()
        ) ::
          {:ok, map()} | {:error, atom()}
  def decode_token(socket, value, %{security_mode: :sign} = opts) do
    Phoenix.Token.verify(socket, opts.secret, value, max_age: convert_ms_to_seconds(opts.ttl))
  end

  def decode_token(socket, value, %{security_mode: :encrypt} = opts) do
    Phoenix.Token.decrypt(socket, opts.secret, value, max_age: convert_ms_to_seconds(opts.ttl))
  end

  defp convert_ms_to_seconds(ms) when is_integer(ms) and ms > 0 do
    max(div(ms, 1000), 1)
  end
end
