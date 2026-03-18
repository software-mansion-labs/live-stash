# Example

We are going to take a look at an example of a tic tac toe game that you can examine in full detail in LiveStash project subdirectory `/examples/showcase_app`. This particular example uses **client** mode with **encryption** and a **session key** set to guarantee extra safety.

## Initialization

```elixir
defmodule ShowcaseAppWeb.Auth.LiveStashClientTicTacToeLive do
  use ShowcaseAppWeb, :live_view
  use LiveStash, mode: :client, security_mode: :encrypt, session_key: "user_token"

  import LiveStash
```

Here, we define the LiveView module and inject the necessary dependencies. By calling use LiveStash, we configure how the state should be persisted. In this specific example, it is configured to `:client` mode, meaning the game's state will be encrypted and stored securely on the user's browser (client-side) using the defined `session_key`.

## Render

```elixir
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-300 flex flex-col items-center py-12 px-6" data-theme="dark">
      <div class="w-full max-w-lg">
        <div class="flex justify-between items-center mb-10">
          <h1 class="text-4xl font-bold text-white">Tic Tac Toe</h1>
          <.return_link />
        </div>

        <div class="bg-base-100 rounded-3xl p-8 shadow-2xl border border-gray-800 flex flex-col items-center">
          <div class="text-2xl font-bold mb-8 h-8 flex items-center justify-center w-full rounded-xl bg-base-200 py-6">
            <%= cond do %>
              <% @winner == "Draw" -> %>
                <span class="text-gray-400">It's a Draw!</span>
              <% @winner -> %>
                <span class="text-green-400">Player {@winner} Wins!</span>
              <% true -> %>
                <span class="text-white">
                  Player <span class={
                    if @current_player == "X", do: "text-purple-400", else: "text-blue-400"
                  }>{@current_player}</span>'s Turn
                </span>
            <% end %>
          </div>

          <div class="grid grid-cols-3 gap-3 bg-gray-900 p-4 rounded-2xl w-full max-w-sm mb-8 shadow-inner">
            <%= for i <- 0..8 do %>
              <button
                phx-click="play"
                phx-value-idx={i}
                disabled={@board[i] != nil || @winner != nil}
                class={[
                  "h-24 sm:h-28 text-5xl font-extrabold rounded-xl flex items-center justify-center transition-all duration-200",
                  @board[i] == nil && @winner == nil &&
                    "bg-base-200 hover:bg-gray-700 cursor-pointer",
                  @board[i] == nil && @winner != nil &&
                    "bg-base-200 cursor-not-allowed opacity-50",
                  @board[i] != nil && "bg-base-300 cursor-default",
                  @board[i] == "X" && "text-purple-400",
                  @board[i] == "O" && "text-blue-400",
                  i in @winning_line && "bg-[#4e2a8e]/40 ring-2 ring-[#4e2a8e] scale-105"
                ]}
              >
                {@board[i]}
              </button>
            <% end %>
          </div>

          <button
            phx-click="reset"
            class="btn bg-[#4e2a8e] hover:bg-[#3a1f6a] text-white border-none w-full max-w-xs text-lg"
          >
            Restart Game
          </button>
        </div>
      </div>
      <.socket_debugger />
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
    |> stash_assigns([:board, :current_player, :winner, :winning_line])
    |> then(&{:noreply, &1})
  end

  def handle_event("reset", _params, socket) do
    {:noreply, start_new_game(socket)}
  end

  defp start_new_game(socket) do
    socket
    |> assign(board: Map.new(0..8, fn i -> {i, nil} end), current_player: "X", winner: nil, winning_line: [])
    |> stash_assigns([:board, :current_player, :winner, :winning_line])
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

Crucially, after updating the socket assigns, we pipe it into `stash_assigns([:board, :current_player, :winner, :winning_line])`. This tells LiveStash to take these specific variables and securely persist them so they aren't lost if the connection drops.

## State recovery

```elixir
  def mount(_params, _session, socket) do
    socket
    |> recover_state()
    |> case do
      {:recovered, recovered_socket} ->
        recovered_socket
      _ -> start_new_game(socket)
    end
    |> then(&{:ok, &1})
  end
```

The `mount/3` lifecycle hook is where LiveStash's recovery mechanism kicks in. When a user connects to the LiveView (or reconnects after a network drop), we immediately call `recover_state/1`.

If LiveStash finds a previously saved state (like an ongoing game), it returns `{:recovered, recovered_socket}` and seamlessly resumes the game right where the user left off. If no state is found (e.g., it's a brand new visit), it falls back to starting a fresh game with `start_new_game(socket)`.
