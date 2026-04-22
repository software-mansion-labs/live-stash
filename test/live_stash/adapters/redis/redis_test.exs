defmodule LiveStash.Adapters.RedisTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  alias LiveStash.Adapters.Redis
  alias LiveStash.Adapters.Redis.Context
  alias LiveStash.Fakes
  alias Phoenix.LiveView.Socket

  setup do
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
          lifecycle: %Phoenix.LiveView.Lifecycle{},
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

    {:ok, socket: socket, secret: secret, stash_id: stash_id, redis_id: redis_id}
  end

  describe "child_spec/1" do
    test "builds the supervisor tree with the configured Redix connection and no ETS cleaners" do
      Application.put_env(:live_stash, :redis, host: "localhost", port: 6379)

      spec = Redis.child_spec([])

      assert %{id: Redis, type: :supervisor} = spec
      {Supervisor, :start_link, [children, [strategy: :one_for_one]]} = spec.start

      assert [{Redix, redix_args}] = children

      assert Keyword.fetch!(redix_args, :name) == LiveStash.Adapters.Redis.Conn
      assert Keyword.fetch!(redix_args, :sync_connect) == false
      assert Keyword.fetch!(redix_args, :host) == "localhost"
      assert Keyword.fetch!(redix_args, :port) == 6379
    end
  end

  describe "init_stash/3" do
    test "reuses existing stashId, pushes init event and clears Redis when not reconnected", %{
      socket: socket,
      redis_id: redis_id,
      stash_id: stash_id
    } do
      binary_state = :erlang.term_to_binary(%{username: "stale"})

      assert {:ok, "OK"} =
               Redis.command([
                 "HSET",
                 redis_id,
                 "owner_id",
                 inspect(self()),
                 "payload",
                 binary_state
               ])

      initialized_socket = Redis.init_stash(socket, %{}, stored_keys: [:username])

      generated_id = initialized_socket.private.live_stash_context.id

      assert generated_id == stash_id
      assert LiveStash.TestRedisConn.snapshot().store[redis_id] == nil

      queued_events = get_in(initialized_socket.private, [:live_temp, :push_events]) || []

      assert Enum.any?(queued_events, fn
               ["live-stash:init-redis", payload] -> payload.stashId == generated_id
               _other -> false
             end)
    end

    test "uses existing stashId from connect_params and does not clear Redis when reconnected? is true",
         %{socket: socket, redis_id: redis_id, stash_id: stash_id} do
      binary_state = :erlang.term_to_binary(%{recovered: true})

      assert {:ok, "OK"} =
               Redis.command([
                 "HSET",
                 redis_id,
                 "owner_id",
                 inspect(self()),
                 "payload",
                 binary_state
               ])

      socket = put_in(socket.private.connect_params["_mounts"], 1)

      initialized_socket = Redis.init_stash(socket, %{}, stored_keys: [:username])

      id_after_init = initialized_socket.private.live_stash_context.id
      assert id_after_init == stash_id
      assert initialized_socket.private.live_stash_context.reconnected? == true

      store = LiveStash.TestRedisConn.snapshot().store
      assert store[redis_id] != nil
    end
  end

  describe "stash/1" do
    test "saves specified assigns to Redis Hash with correct owner_id", %{
      socket: socket,
      redis_id: redis_id
    } do
      returned_socket = Redis.stash(socket)

      assert %Socket{} = returned_socket

      assert {:ok, saved_binary} = Redis.command(["HGET", redis_id, "payload"])
      assert :erlang.binary_to_term(saved_binary) == %{username: "tester"}

      assert {:ok, owner} = Redis.command(["HGET", redis_id, "owner_id"])
      assert owner == inspect(self())
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
    end

    test "updates state when stashed assigns fingerprint changes", %{
      socket: socket,
      redis_id: redis_id
    } do
      stashed_socket = Redis.stash(socket)
      updated_socket = put_in(stashed_socket.assigns.username, "tester-2")

      Redis.stash(updated_socket)

      assert {:ok, saved_binary} = Redis.command(["HGET", redis_id, "payload"])
      assert :erlang.binary_to_term(saved_binary) == %{username: "tester-2"}
    end

    test "crashes the process if attempting to stash to a record owned by a different PID", %{
      socket: socket,
      redis_id: redis_id
    } do
      fake_owner = "#PID<0.999.0>"
      Redis.command(["HSET", redis_id, "owner_id", fake_owner, "payload", "old_state"])

      socket_with_new_state = put_in(socket.assigns.username, "current process")

      assert_raise RuntimeError, ~r/already exists for another process/, fn ->
        Redis.stash(socket_with_new_state)
      end
    end

    test "logs and returns socket unchanged when Redis EVAL fails", %{
      socket: socket
    } do
      assert :ok = LiveStash.TestRedisConn.fail_next("EVAL", :econnrefused)

      log =
        capture_log(fn ->
          returned_socket = Redis.stash(socket)
          assert returned_socket == socket
        end)

      assert log =~ "Failed to stash assigns"
    end
  end

  describe "recover_state/1" do
    test "recovers state from Redis Hash and updates socket assigns", %{
      socket: socket,
      redis_id: redis_id
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      state_to_recover = %{player_level: 42, theme: "dark"}
      binary_state = :erlang.term_to_binary(state_to_recover)

      assert {:ok, "OK"} =
               Redis.command([
                 "HSET",
                 redis_id,
                 "owner_id",
                 inspect(self()),
                 "payload",
                 binary_state
               ])

      assert {:recovered, recovered_socket} = Redis.recover_state(socket)

      assert recovered_socket.assigns.player_level == 42
      assert recovered_socket.assigns.__changed__ == %{player_level: true, theme: true}
    end

    test "takes ownership (updates owner_id) upon recovery", %{
      socket: socket,
      redis_id: redis_id
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      fake_owner = "#PID<0.999.0>"
      binary_state = :erlang.term_to_binary(socket.assigns)
      Redis.command(["HSET", redis_id, "owner_id", fake_owner, "payload", binary_state])

      assert {:recovered, _recovered_socket} = Redis.recover_state(socket)

      assert {:ok, owner} = Redis.command(["HGET", redis_id, "owner_id"])
      assert owner == inspect(self())
    end

    test "returns {:not_found, socket} when there is no payload in Redis for the given id", %{
      socket: socket
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      assert {:not_found, returned_socket} = Redis.recover_state(socket)
      assert returned_socket == socket
    end

    test "returns {:error, socket} and logs when Redis EVAL fails", %{socket: socket} do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)
      assert :ok = LiveStash.TestRedisConn.fail_next("EVAL", :timeout)

      log =
        capture_log(fn ->
          assert {:error, returned_socket} = Redis.recover_state(socket)
          assert returned_socket == socket
        end)

      assert log =~ "Failed to recover state"
    end

    test "returns {:error, socket} and logs when payload contains unsafe/unknown atoms", %{
      socket: socket,
      redis_id: redis_id
    } do
      socket = put_in(socket.private.live_stash_context.reconnected?, true)

      malicious_binary = <<131, 118, 0, 31, "non_existent_malicious_atom_999">>
      Redis.command(["HSET", redis_id, "owner_id", inspect(self()), "payload", malicious_binary])

      log =
        capture_log(fn ->
          assert {:error, returned_socket} = Redis.recover_state(socket)
          assert returned_socket == socket
        end)

      assert log =~ "invalid atoms"
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

      Redis.command(["HSET", redis_id, "owner_id", inspect(self()), "payload", "to_be_deleted"])
      assert {:ok, _} = Redis.command(["HGET", redis_id, "payload"])

      reset_socket = Redis.reset_stash(socket)

      assert %Socket{} = reset_socket
      assert reset_socket.private.live_stash_context.stash_fingerprint == nil
      assert LiveStash.TestRedisConn.snapshot().store[redis_id] == nil
    end

    test "logs DEL errors and still returns socket", %{socket: socket, redis_id: redis_id} do
      socket = put_in(socket.private.live_stash_context.stash_fingerprint, "fingerprint")
      Redis.command(["HSET", redis_id, "owner_id", inspect(self()), "payload", "to_be_deleted"])

      assert :ok = LiveStash.TestRedisConn.fail_next("DEL", :timeout)

      log =
        capture_log(fn ->
          returned_socket = Redis.reset_stash(socket)
          assert %Socket{} = returned_socket
          assert returned_socket.private.live_stash_context.stash_fingerprint == "fingerprint"
        end)

      assert log =~ "Failed to reset stash"
    end
  end

  defp redis_key(id, secret) do
    hashed_binary =
      :crypto.hash(:sha256, id <> secret)
      |> Base.encode64(padding: false)

    "live_stash:" <> hashed_binary
  end
end
