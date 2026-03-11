defmodule LiveStash.Utils do
  @moduledoc false

  @spec error_message(
          message :: String.t(),
          error :: Exception.t(),
          stacktrace :: Exception.stacktrace()
        ) ::
          String.t()
  def error_message(message, error, stacktrace) do
    "#{message} - report issue to LiveStash maintainers:\n#{Exception.format(:error, error, stacktrace)}"
  end

  @spec warning_message(message :: String.t(), reason :: term()) :: String.t()
  def warning_message(message, reason) do
    "#{message}, reason: #{inspect(reason)}"
  end
end
