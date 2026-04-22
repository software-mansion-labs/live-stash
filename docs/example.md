# Example

We are going to take a look at an example of a tic tac toe game that you can examine in full detail in LiveStash project subdirectory `/examples/showcase_app`. This particular example uses **browser memory** adapter with **encryption** and a **session key** set to guarantee extra safety.

The state that should survive reconnects is declared up front with `stored_keys: [:board, :current_player, :winner, :winning_line]`, and `LiveStash.stash/1` only emits a new browser event when that configured subset changes.

For a complete project example go to our [repository](https://github.com/software-mansion-labs/live-stash/blob/v0.2.0/examples/showcase_app/README.md).

## Initialization

```elixir
defmodule ShowcaseAppWeb.Auth.LiveStashClientTicTacToeLive do
  use ShowcaseAppWeb, :live_view
  use LiveStash,
    adapter: LiveStash.Adapters.BrowserMemory,
    security_mode: :encrypt,
    session_key: "user_token",
    stored_keys: [:board, :current_player, :winner, :winning_line]
```

Here, we define the LiveView module and inject the necessary dependencies. By calling use LiveStash, we configure how the state should be persisted. In this specific example, it is configured to use the browser memory adapter, meaning the game's state will be encrypted and stored securely on the user's browser (client-side) using the defined `session_key`.

## Render

```elixir
  def render(assigns) do
    ~H"""
    <div class="p-4">
      <div class="mb-4 text-lg font-semibold">
        <%= cond do %>
          <% @winner == "Draw" -> %>
            <span>It's a Draw!</span>
          <% @winner -> %>
            <span>Player {@winner} Wins!</span>
          <% true -> %>
            <span>Player {@current_player}'s Turn</span>
        <% end %>
      </div>

      <div class="grid grid-cols-3 gap-2 w-fit">
        <%= for i <- 0..8 do %>
          <button
            phx-click="play"
            phx-value-idx={i}
            disabled={@board[i] != nil || @winner != nil}
            class={[
              "h-16 w-16 border border-current text-2xl font-bold flex items-center justify-center",
              @board[i] == nil && @winner == nil && "cursor-pointer",
              @board[i] != nil && "cursor-default",
              @board[i] == nil && @winner != nil && "cursor-not-allowed",
              i in @winning_line && "border-2"
            ]}
          >
            {@board[i]}
          </button>
        <% end %>
      </div>

      <button phx-click="reset" class="mt-4 border px-3 py-2 rounded">
        Restart Game
      </button>
    </div>
    """
  end
```

The `render/1` function defines the user interface using HEEx templates and Tailwind CSS for styling. It displays the current game status (whether it's a draw, someone won, or whose turn it is). It also renders the 3x3 game board grid and wires up user interactions using Phoenix bindings (`phx-click="play"` and `phx-click="reset"`) to send events back to the server.

## State changes

```elixir
  def handle_event("play", %{"idx" => idx_str}, socket) do
    idx = String.to_integer(idx_str)
    new_board = Map.put(socket.assigns.board, idx, socket.assigns.current_player)

    {winner, winning_line} = check_game_state(new_board)

    next_player = if socket.assigns.current_player == "X", do: "O", else: "X"

    socket
    |> assign(board: new_board, current_player: next_player, winner: winner, winning_line: winning_line)
    |> LiveStash.stash()
    |> then(&{:noreply, &1})
  end

  def handle_event("reset", _params, socket) do
    {:noreply, start_new_game(socket)}
  end

  defp start_new_game(socket) do
    socket
    |> assign(board: Map.new(0..8, fn i -> {i, nil} end), current_player: "X", winner: nil, winning_line: [])
    |> LiveStash.stash()
  end

  defp check_game_state(board) do
    winner_tuple =
      Enum.find_value(@winning_lines, fn [a, b, c] = line ->
        if board[a] != nil and board[a] == board[b] and board[a] == board[c] do
          {board[a], line}
        else
          nil
        end
      end)

    cond do
      winner_tuple != nil ->
        winner_tuple

      not Enum.any?(Map.values(board), &is_nil/1) ->
        {"Draw", []}

      true ->
        {nil, []}
    end
  end
end
```

This section handles the core game logic and user actions. The `handle_event/3` callbacks listen for the actions triggered from the UI. When a player makes a move, the board is updated, checked for a win or draw, and the turn shifts to the next player.

Crucially, after updating the socket assigns, we pipe it into `stash()`. The assigns to persist are declared in `use LiveStash`, so LiveStash securely persists that configured state when the connection drops.

## State recovery

```elixir
  def mount(_params, _session, socket) do
    socket
    |> LiveStash.recover_state()
    |> case do
      {:recovered, recovered_socket} ->
        recovered_socket

      {_, socket} ->
        start_new_game(socket)
    end
    |> then(&{:ok, &1})
  end
```

The `mount/3` lifecycle hook is where LiveStash's recovery mechanism kicks in. When a user connects to the LiveView (or reconnects after a network drop), we immediately call `recover_state/1`.

If LiveStash finds a previously saved state (like an ongoing game), it returns `{:recovered, recovered_socket}` and seamlessly resumes the game right where the user left off. If no state is found (e.g., it's a brand new visit), it falls back to starting a fresh game with `start_new_game(socket)`.

> #### Note {: .note}
>
> In case of an error you must use the returned socket for the invalid state to be cleared.
