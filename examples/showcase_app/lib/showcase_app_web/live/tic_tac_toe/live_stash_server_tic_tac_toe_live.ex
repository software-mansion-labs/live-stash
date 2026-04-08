defmodule ShowcaseAppWeb.LiveStashServerTicTacToeLive do
  use ShowcaseAppWeb, :live_view
  use LiveStash,
    adapter: LiveStash.Adapters.ETS,
    ttl: 5 * 60 * 1000,
    assigns: [:board, :current_player, :winner, :winning_line]

  @winning_lines [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6]
  ]

  def mount(_params, _session, socket) do
    socket
    |> LiveStash.recover_state()
    |> case do
      {:recovered, recovered_socket} ->
        recovered_socket
      _ -> start_new_game(socket)
    end
    |> then(&{:ok, &1})
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col items-center pt-8 pb-4 px-4 sm:pt-10 sm:pb-8 sm:px-6">
      <div class="w-full max-w-lg">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-3xl sm:text-4xl font-bold text-white">Tic Tac Toe</h1>
          <.return_link />
        </div>

        <div class="bg-base-100 rounded-2xl sm:rounded-3xl p-5 sm:p-8 shadow-2xl border border-gray-800 flex flex-col items-center w-full">

          <div class="text-xl sm:text-2xl font-bold mb-5 flex items-center justify-center w-full rounded-xl bg-base-200 py-3 sm:py-4">
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

          <div class="grid grid-cols-3 gap-2 sm:gap-3 bg-gray-900 p-3 sm:p-4 rounded-2xl w-full max-w-sm mb-5 shadow-inner">
            <%= for i <- 0..8 do %>
              <button
                phx-click="play"
                phx-value-idx={i}
                disabled={@board[i] != nil || @winner != nil}
                class={[
                  "h-20 sm:h-24 text-4xl sm:text-5xl font-extrabold rounded-xl flex items-center justify-center transition-all duration-200",
                  @board[i] == nil && @winner == nil && "bg-base-200 hover:bg-gray-700 cursor-pointer",
                  @board[i] == nil && @winner != nil && "bg-base-200 cursor-not-allowed opacity-50",
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
            class="btn bg-[#4e2a8e] hover:bg-[#3a1f6a] text-white border-none w-full max-w-xs text-base sm:text-lg min-h-0 h-12"
          >
            Restart Game
          </button>
        </div>
      </div>
      <.socket_debugger />
    </div>
    """
  end

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
    |> LiveStash.reset_stash()
    |> assign(board: Map.new(0..8, fn i -> {i, nil} end), current_player: "X", winner: nil, winning_line: [])
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
