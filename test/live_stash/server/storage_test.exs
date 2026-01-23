defmodule LiveStash.Server.StorageTest do
  use ExUnit.Case, async: false

  alias LiveStash.Server.Storage

  setup do
    # Start storage for tests
    case GenServer.whereis(Storage) do
      nil -> start_supervised!(Storage)
      _pid -> :ok
    end

    :ok
  end

  describe "insert_state/2" do
    test "inserts new state successfully" do
      id = "test-id-#{System.unique_integer([:positive])}"
      state = %{count: 42, name: "test"}

      assert Storage.insert_state(id, state) == :ok

      {:ok, retrieved_state} = Storage.get_state(id)
      assert retrieved_state == state
    end

    test "overwrites existing state when inserting with same id" do
      id = "test-id-#{System.unique_integer([:positive])}"
      state1 = %{count: 42}
      state2 = %{count: 100}

      assert Storage.insert_state(id, state1) == :ok
      assert Storage.insert_state(id, state2) == :ok

      {:ok, retrieved_state} = Storage.get_state(id)
      assert retrieved_state == state2
      assert retrieved_state.count == 100
    end
  end

  describe "put_state/3" do
    test "creates new state when id does not exist" do
      id = "test-id-#{System.unique_integer([:positive])}"

      assert Storage.put_state(id, :count, 42) == :ok

      {:ok, state} = Storage.get_state(id)
      assert state.count == 42
    end

    test "updates existing state when id exists" do
      id = "test-id-#{System.unique_integer([:positive])}"

      assert Storage.put_state(id, :count, 42) == :ok
      assert Storage.put_state(id, :name, "test") == :ok
      assert Storage.put_state(id, :count, 100) == :ok

      {:ok, state} = Storage.get_state(id)
      assert state.count == 100
      assert state.name == "test"
    end

    test "handles multiple keys correctly" do
      id = "test-id-#{System.unique_integer([:positive])}"

      Storage.put_state(id, :key1, "value1")
      Storage.put_state(id, :key2, "value2")
      Storage.put_state(id, :key3, "value3")

      {:ok, state} = Storage.get_state(id)
      assert state.key1 == "value1"
      assert state.key2 == "value2"
      assert state.key3 == "value3"
    end
  end

  describe "get_state/1" do
    test "returns state when it exists" do
      id = "test-id-#{System.unique_integer([:positive])}"
      state = %{count: 42, name: "test"}

      Storage.insert_state(id, state)

      assert {:ok, retrieved_state} = Storage.get_state(id)
      assert retrieved_state == state
    end

    test "returns {:error, :not_found} when state does not exist" do
      id = "non-existent-id-#{System.unique_integer([:positive])}"

      assert Storage.get_state(id) == {:error, :not_found}
    end

    test "returns state after put_state" do
      id = "test-id-#{System.unique_integer([:positive])}"

      Storage.put_state(id, :count, 42)
      Storage.put_state(id, :name, "test")

      {:ok, state} = Storage.get_state(id)
      assert state.count == 42
      assert state.name == "test"
    end

    test "returns updated state after multiple put_state calls" do
      id = "test-id-#{System.unique_integer([:positive])}"

      Storage.put_state(id, :count, 10)
      {:ok, state1} = Storage.get_state(id)
      assert state1.count == 10

      Storage.put_state(id, :count, 20)
      {:ok, state2} = Storage.get_state(id)
      assert state2.count == 20
    end
  end

  describe "delete_state/1" do
    test "deletes existing state" do
      id = "test-id-#{System.unique_integer([:positive])}"
      state = %{count: 42}

      Storage.insert_state(id, state)
      assert {:ok, ^state} = Storage.get_state(id)

      assert Storage.delete_state(id) == :ok
      assert Storage.get_state(id) == {:error, :not_found}
    end

    test "returns :ok even when deleting non-existent state" do
      id = "non-existent-id-#{System.unique_integer([:positive])}"

      assert Storage.delete_state(id) == :ok
      assert Storage.get_state(id) == {:error, :not_found}
    end
  end
end
