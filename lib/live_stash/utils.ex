defmodule LiveStash.Utils do
  @moduledoc false

  @spec error_message(
          message :: String.t(),
          error :: Exception.t(),
          stacktrace :: Exception.stacktrace()
        ) ::
          String.t()
  def error_message(message, error, stacktrace) do
    "[LiveStash] #{message} - report issue to LiveStash maintainers:\n#{Exception.format(:error, error, stacktrace)}"
  end

  @spec error_message(
          message :: String.t(),
          error :: Exception.t()
        ) ::
          String.t()
  def error_message(message, error) do
    "[LiveStash] #{message} - report issue to LiveStash maintainers:\n#{Exception.format(:error, error)}"
  end
end
