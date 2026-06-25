defmodule TestingWeb.Performance.LiveStash do
  @moduledoc false

  alias TestingWeb.Performance.Config

  defmacro __using__(opts) do
    quote do
      on_mount({TestingWeb.Performance.LiveStash, unquote(opts)})
    end
  end

  def on_mount(_opts, :not_mounted_at_router, _session, _socket) do
    raise ArgumentError, "LiveStash does not support nested LiveViews."
  end

  def on_mount(opts, params, session, socket) do
    opts = Keyword.put(opts, :ttl, Config.ttl())
    LiveStash.on_mount(opts, params, session, socket)
  end
end
