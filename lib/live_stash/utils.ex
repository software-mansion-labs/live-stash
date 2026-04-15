defmodule LiveStash.Utils do
  @moduledoc false

  @spec exception_message(
          message :: String.t(),
          error :: Exception.t(),
          stacktrace :: Exception.stacktrace()
        ) ::
          String.t()
  def exception_message(message, error, stacktrace \\ []) do
    "[LiveStash] #{message} - report issue to LiveStash maintainers:\n#{Exception.format(:error, error, stacktrace)}"
  end

  @spec reason_message(message :: String.t(), reason :: term()) :: String.t()
  def reason_message(message, reason) do
    "[LiveStash] #{message}, reason: #{inspect(reason)}"
  end

  @spec hash_term(term :: term()) :: binary()
  def hash_term(term) do
    :crypto.hash(:sha256, :erlang.term_to_binary(term))
  end
end
