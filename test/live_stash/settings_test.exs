defmodule LiveStash.SettingsTest do
  use ExUnit.Case, async: true

  alias LiveStash.Settings
  alias Phoenix.LiveView.Socket

  @default_secret "live_stash"

  setup do
    socket = %Socket{
      transport_pid: self(),
      private: %{connect_params: %{}}
    }

    {:ok, socket: socket}
  end

  describe "from_socket/3" do
    test "returns default settings when no session_key is provided", %{socket: socket} do
      session = %{}
      opts = [mode: :client, ttl: 1000]

      settings = Settings.from_socket(socket, session, opts)

      assert %Settings{} = settings
      assert settings.secret == @default_secret
      assert settings.mode == :client
      assert settings.ttl == 1000
      assert settings.reconnected? == false
      assert settings.node_hint == nil
    end

    test "fetches, hashes, and base64 encodes secret from session when session_key is provided",
         %{socket: socket} do
      session = %{"my_stash_key" => "super_secret_token"}
      opts = [session_key: "my_stash_key"]

      settings = Settings.from_socket(socket, session, opts)

      expected_secret =
        :sha256
        |> :crypto.hash("super_secret_token")
        |> Base.encode64(padding: false)

      assert settings.secret == expected_secret
    end

    test "raises ArgumentError when session_key is not found in session", %{socket: socket} do
      session = %{"other_key" => "value"}
      opts = [session_key: "missing_key"]

      assert_raise ArgumentError, ~r/failed to return a valid secret/, fn ->
        Settings.from_socket(socket, session, opts)
      end
    end

    test "raises ArgumentError when session_key returns a non-binary value", %{socket: socket} do
      session = %{"int_key" => 12345}
      opts = [session_key: "int_key"]

      assert_raise ArgumentError, ~r/invalid type. Expected a binary string/, fn ->
        Settings.from_socket(socket, session, opts)
      end
    end

    test "reraises a custom RuntimeError when LiveView.get_connect_params/1 fails" do
      broken_socket = %Socket{transport_pid: self()}
      session = %{}
      opts = []

      assert_raise RuntimeError, ~r/Failed to get connect params/, fn ->
        Settings.from_socket(broken_socket, session, opts)
      end
    end

    test "sets reconnected? to true when _mounts is greater than 0", %{socket: socket} do
      socket = put_in(socket.private.connect_params, %{"_mounts" => 1})
      session = %{}
      opts = []

      settings = Settings.from_socket(socket, session, opts)

      assert settings.reconnected? == true
    end
  end
end
