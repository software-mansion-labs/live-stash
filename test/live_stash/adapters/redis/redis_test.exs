defmodule LiveStash.Adapters.RedisTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias LiveStash.Adapters.Redis
  alias LiveStash.Adapters.Redis.Context
  alias LiveStash.Adapters.Redis.Registry
  alias LiveStash.Fakes
  alias Phoenix.LiveView.Socket

  require LiveStash.Adapters.Redis.Registry

  @table_name Application.compile_env(:live_stash, :ets_table_name, :live_stash_redis_registry)

  setup do
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    Registry.create_table!()
    LiveStash.TestRedisConn.stop()
    {:ok, _pid} = LiveStash.TestRedisConn.start_link(name: LiveStash.Adapters.Redis.Conn)

    on_exit(fn -> LiveStash.TestRedisConn.stop() end)

    secret = "live_stash"
    stash_id = "test_uuid_1234"

    socket =
      Fakes.socket(
        assigns: %{
          __changed__: %{},
          player_id: 123,
          username: "tester"
        },
        private: %{
          live_temp: %{},
          connect_params: %{"liveStash" => %{"stashId" => stash_id}},
          live_stash_context: %Context{
            stored_keys: [:username],
            reconnected?: false,
            ttl: 86_400,
            secret: secret,
            id: stash_id,
            stash_fingerprint: nil
          }
        }
      )

    redis_id = redis_key(stash_id, secret)

    {:ok,
     socket: socket,
     secret: secret,
     stash_id: stash_id,
     redis_id: redis_id,
     delete_at: System.os_time(:millisecond) + 86_400}
  end

  describe "child_spec/1" do
    test "builds the supervisor tree with the configured Redix connection" do
      Application.put_env(:live_stash, :redis, host: "localhost", port: 6379)

      spec = Redis.child_spec([])

      assert %{id: Redis, type: :supervisor} = spec

      {Supervisor, :start_link, [children, [strategy: :one_for_one]]} = spec.start

      assert [
               {Redix, redix_args},
               {LiveStash.Adapters.Redis.Cleaner, []},
               {LiveStash.Adapters.Redis.Storage, []}
             ] = children

      assert Keyword.fetch!(redix_args, :name) == LiveStash.Adapters.Redis.Conn
      assert Keyword.fetch!(redix_args, :sync_connect) == false
      assert Keyword.fetch!(redix_args, :host) == "localhost"
      assert Keyword.fetch!(redix_args, :port) == 6379
      assert [strategy: :one_for_one] = [strategy: :one_for_one]
    end
  end

  describe "init_stash/3" do
    test "reuses existing stashId, pushes init event and clears Redis when not reconnected", %{
      socket: socket,
      redis_id: redis_id,
      stash_id: stash_id,
      delete_at: delete_at
    } do
      Registry.insert!(
        Registry.registry(id: redis_id, pid: self(), delete_at: delete_at, ttl: 1000)
      )

      binary_state = :erlang.term_to_binary(%{username: "stale"})
      assert {:ok, "OK"} = Redis.command(["SET", redis_id, binary_state, "EX", "86400"])

      initialized_socket = Redis.init_stash(socket, %{}, stored_keys: [:username])

      generated_id = initialized_socket.private.live_stash_context.id

      assert generated_id == stash_id
      assert Registry.get_by_id!(redis_id) == :not_found
      assert LiveStash.TestRedisConn.snapshot().store[redis_id] == nil

      queued_events = get_in(initialized_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:init-redis", payload] ->
                 payload.stashId == generated_id

               _other ->
                 false
             end)
    end

    test "uses existing stashId from connect_params and does not clear Redis when reconnected? is true",
         %{socket: socket, redis_id: redis_id, stash_id: stash_id, delete_at: delete_at} do
      Registry.insert!(
        Registry.registry(id: redis_id, pid: self(), delete_at: delete_at, ttl: 1000)
      )

      binary_state = :erlang.term_to_binary(%{recovered: true})
      assert {:ok, "OK"} = Redis.command(["SET", redis_id, binary_state, "EX", "86400"])

      socket = put_in(socket.private.connect_params["_mounts"], 1)

      initialized_socket = Redis.init_stash(socket, %{}, stored_keys: [:username])

      id_after_init = initialized_socket.private.live_stash_context.id
      assert id_after_init == stash_id
      assert initialized_socket.private.live_stash_context.reconnected? == true

      queued_events = get_in(initialized_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:init-redis", payload] ->
                 payload.stashId == id_after_init

               _other ->
                 false
             end)

      assert {:ok, _pid, _delete_at, _ttl} = Registry.get_by_id!(redis_id)
      assert LiveStash.TestRedisConn.snapshot().store[redis_id] == binary_state
    end
  end

  describe "stash/1" do
    test "saves specified assigns to Redis", %{socket: socket, redis_id: redis_id} do
      returned_socket = Redis.stash(socket)

      assert %Socket{} = returned_socket

      assert {:ok, saved_binary} = Redis.command(["GET", redis_id])
      assert :erlang.binary_to_term(saved_binary) == %{username: "tester"}

      assert {:ok, pid, _delete_at, ttl} = Registry.get_by_id!(redis_id)
      assert pid == self()
      assert ttl == 86_400
    end

    test "does not update Redis when only untracked assigns change - fingerprint remains the same",
         %{socket: socket, redis_id: redis_id} do
      stashed_socket = Redis.stash(socket)

      %{store: store_before} = LiveStash.TestRedisConn.snapshot()
      stored_before = store_before[redis_id]

      socket_with_untracked_change = %{
        stashed_socket
        | assigns: Map.put(stashed_socket.assigns, :player_id, 999)
      }

      Redis.stash(socket_with_untracked_change)

      %{store: store_after} = LiveStash.TestRedisConn.snapshot()

      assert store_before == store_after
      assert store_after[redis_id] == stored_before
      assert {:ok, saved_binary} = Redis.command(["GET", redis_id])
      assert :erlang.binary_to_term(saved_binary) == %{username: "tester"}
    end

    test "updates state when stashed assigns fingerprint changes", %{
      socket: socket,
      redis_id: redis_id
    } do
      stashed_socket = Redis.stash(socket)

      updated_socket = put_in(stashed_socket.assigns.username, "tester-2")

      Redis.stash(updated_socket)

      assert {:ok, saved_binary} = Redis.command(["GET", redis_id])
      assert :erlang.binary_to_term(saved_binary) == %{username: "tester-2"}
    end

    test "stashes only the intersection of configured keys and present socket assigns", %{
      socket: socket,
      redis_id: redis_id
    } do
      context = socket.private.live_stash_context
      updated_context = %{context | stored_keys: [:username, :missing_key]}
      socket_configured = put_in(socket.private.live_stash_context, updated_context)

      assert %Socket{} = Redis.stash(socket_configured)

      assert {:ok, saved_binary} = Redis.command(["GET", redis_id])
      assert :erlang.binary_to_term(saved_binary) == %{username: "tester"}
    end

    test "logs and returns socket unchanged when Redis SET fails", %{
      socket: socket,
      redis_id: redis_id
    } do
      assert :ok = LiveStash.TestRedisConn.fail_next("SET", :econnrefused)

      log =
        capture_log(fn ->
          returned_socket = Redis.stash(socket)
          assert returned_socket == socket
        end)

      assert log =~ "Failed to stash assigns"
      assert Registry.get_by_id!(redis_id) == :not_found
      assert LiveStash.TestRedisConn.snapshot().store[redis_id] == nil
    end
  end

  describe "recover_state/1" do
    test "recovers state from Redis and updates socket assigns, keeping existing assigns", %{
      socket: socket,
      redis_id: redis_id
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      state_to_recover = %{player_level: 42, theme: "dark"}
      binary_state = :erlang.term_to_binary(state_to_recover)

      assert {:ok, "OK"} = Redis.command(["SET", redis_id, binary_state, "EX", "86400"])

      assert {:recovered, recovered_socket} = Redis.recover_state(socket)

      assert recovered_socket.assigns.player_level == 42
      assert recovered_socket.assigns.theme == "dark"
      assert recovered_socket.assigns.__changed__ == %{player_level: true, theme: true}
      assert recovered_socket.assigns.player_id == 123
      assert recovered_socket.assigns.username == "tester"
    end

    test "returns {:not_found, socket} when there is no state in Redis for the given id", %{
      socket: socket
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      assert {:not_found, returned_socket} = Redis.recover_state(socket)
      assert returned_socket == socket
    end

    test "returns {:error, socket} and logs when Redis GET fails", %{socket: socket} do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)
      assert :ok = LiveStash.TestRedisConn.fail_next("GET", :timeout)

      log =
        capture_log(fn ->
          assert {:error, returned_socket} = Redis.recover_state(socket)
          assert returned_socket == socket
        end)

      assert log =~ "Failed to recover state"
    end

    test "rescues exceptions, logs error and returns {:error, socket}", %{socket: socket} do
      socket_ready = put_in(socket.private.live_stash_context.reconnected?, true)
      broken_socket = put_in(socket_ready.private.live_stash_context.secret, nil)

      log =
        capture_log(fn ->
          assert {:error, _socket} = Redis.recover_state(broken_socket)
        end)

      assert log =~ "Could not recover state"
    end

    test "returns :new and socket when reconnected? is false", %{socket: socket} do
      assert {:new, returned_socket} = Redis.recover_state(socket)
      assert returned_socket == socket
    end
  end

  describe "reset_stash/1" do
    test "deletes the state from Redis and clears fingerprint", %{
      socket: socket,
      redis_id: redis_id
    } do
      socket = put_in(socket.private.live_stash_context.stash_fingerprint, "some_hash_to_clear")

      binary_state = :erlang.term_to_binary(%{data: "to_be_deleted"})
      assert {:ok, "OK"} = Redis.command(["SET", redis_id, binary_state, "EX", "86400"])

      Registry.insert!(
        Registry.registry(
          id: redis_id,
          pid: self(),
          delete_at: System.os_time(:millisecond) + 1000,
          ttl: 1000
        )
      )

      assert {:ok, _} = Redis.command(["GET", redis_id])

      reset_socket = Redis.reset_stash(socket)

      assert %Socket{} = reset_socket
      assert reset_socket.private.live_stash_context.stash_fingerprint == nil
      assert Registry.get_by_id!(redis_id) == :not_found
      assert LiveStash.TestRedisConn.snapshot().store[redis_id] == nil
    end

    test "rescues exceptions, logs error and returns socket unchanged", %{socket: socket} do
      broken_socket = put_in(socket.private.live_stash_context, nil)

      log =
        capture_log(fn ->
          assert %Socket{} = Redis.reset_stash(broken_socket)
        end)

      assert log =~ "Failed to reset stash"
    end

    test "logs DEL errors and still returns socket", %{socket: socket, redis_id: redis_id} do
      socket = put_in(socket.private.live_stash_context.stash_fingerprint, "fingerprint")

      Registry.insert!(
        Registry.registry(
          id: redis_id,
          pid: self(),
          delete_at: System.os_time(:millisecond) + 1000,
          ttl: 1000
        )
      )

      assert :ok = LiveStash.TestRedisConn.fail_next("DEL", :timeout)

      log =
        capture_log(fn ->
          returned_socket = Redis.reset_stash(socket)
          assert %Socket{} = returned_socket
          assert returned_socket.private.live_stash_context.stash_fingerprint == nil
        end)

      assert log =~ "Failed to reset stash"
      assert Registry.get_by_id!(redis_id) == :not_found
    end
  end

  defp redis_key(id, secret) do
    hashed_binary =
      :crypto.hash(:sha256, id <> secret)
      |> Base.encode64(padding: false)

    "live_stash:" <> hashed_binary
  end
end
