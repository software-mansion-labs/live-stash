defmodule LiveStashTest do
  use ExUnit.Case, async: false

  alias LiveStash.Fakes

  setup do
    Process.delete(:live_stash_components)
    :ok
  end

  describe "put_recovered_components/1" do
    test "writes the components map to the :live_stash_components process key" do
      assert Process.get(:live_stash_components) == nil

      assert :ok = LiveStash.put_recovered_components(%{{Foo, "a"} => %{count: 1}})

      assert Process.get(:live_stash_components) == %{{Foo, "a"} => %{count: 1}}
    end

    test "overwrites any previous value" do
      LiveStash.put_recovered_components(%{{Foo, "a"} => %{count: 1}})
      LiveStash.put_recovered_components(%{{Bar, "b"} => %{count: 2}})

      assert Process.get(:live_stash_components) == %{{Bar, "b"} => %{count: 2}}
    end

    test "accepts an empty map" do
      LiveStash.put_recovered_components(%{})

      assert Process.get(:live_stash_components) == %{}
    end
  end

  describe "get_components_buffer/1" do
    test "returns %{} when the buffer key is missing from socket.private" do
      socket = Fakes.socket(private: %{})

      assert LiveStash.get_components_buffer(socket) == %{}
    end

    test "returns the buffer when set in socket.private" do
      buffer = %{{Counter, "x"} => %{count: 5}}
      socket = Fakes.socket(private: %{live_stash_components_buffer: buffer})

      assert LiveStash.get_components_buffer(socket) == buffer
    end

    test "returns %{} when buffer is explicitly nil" do
      socket = Fakes.socket(private: %{live_stash_components_buffer: nil})

      assert LiveStash.get_components_buffer(socket) == %{}
    end
  end
end
