defmodule LiveStash.Adapters.BrowserMemory.ContextTest do
  use ExUnit.Case, async: true

  alias LiveStash.Adapters.BrowserMemory.Context
  alias Phoenix.LiveView.Socket
  alias LiveStash.Fakes

  @default_secret "live_stash"

  setup do
    socket = Fakes.socket(private: %{connect_params: %{}})

    {:ok, socket: socket}
  end

  describe "new/3" do
    test "returns default settings when no session_key is provided", %{socket: socket} do
      session = %{}
      opts = [ttl: 1000]

      context = Context.new(socket, session, opts)

      assert %Context{} = context
      assert context.secret == @default_secret
      assert context.ttl == 1000
      assert context.reconnected? == false
    end

    test "fetches, hashes, and base64 encodes secret from session when session_key is provided",
         %{socket: socket} do
      session = %{"my_stash_key" => "super_secret_token"}
      opts = [session_key: "my_stash_key"]

      context = Context.new(socket, session, opts)

      expected_secret =
        :sha256
        |> :crypto.hash("super_secret_token")
        |> Base.encode64(padding: false)

      assert context.secret == expected_secret
    end

    test "raises ArgumentError when session_key is not found in session", %{socket: socket} do
      session = %{"other_key" => "value"}
      opts = [session_key: "missing_key"]

      assert_raise ArgumentError, ~r/failed to return a valid secret/, fn ->
        Context.new(socket, session, opts)
      end
    end

    test "raises ArgumentError when session_key returns a non-binary value", %{socket: socket} do
      session = %{"int_key" => 123}
      opts = [session_key: "int_key"]

      assert_raise ArgumentError, ~r/invalid type. Expected a binary string/, fn ->
        Context.new(socket, session, opts)
      end
    end

    test "reraises a custom RuntimeError when LiveView.get_connect_params/1 fails" do
      broken_socket = %Socket{transport_pid: self()}
      session = %{}
      opts = []

      assert_raise RuntimeError, ~r/Failed to get connect params/, fn ->
        Context.new(broken_socket, session, opts)
      end
    end

    test "sets reconnected? to true when _mounts is greater than 0", %{socket: socket} do
      socket = put_in(socket.private.connect_params, %{"_mounts" => 1})
      session = %{}
      opts = []

      context = Context.new(socket, session, opts)

      assert context.reconnected? == true
    end
  end
end
