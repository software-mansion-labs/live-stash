defmodule ShowcaseAppWeb.UsersLive do
  use ShowcaseAppWeb, :live_view

  alias ShowcaseApp.{User, Repo}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, users: Repo.all(User))}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8" data-theme="dark">

      <div class="flex justify-between items-center mb-6">
        <h1 class="text-3xl font-bold text-white">Registered Users</h1>

        <.link navigate={~p"/"} class="btn btn-outline border-gray-600 text-gray-300 hover:bg-gray-800 flex items-center gap-2">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-5 h-5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" />
          </svg>
          Return
        </.link>
      </div>

      <table class="table w-full bg-base-200 text-gray-300 rounded-xl overflow-hidden shadow-xl">
        <thead class="text-gray-400 border-b border-gray-700 bg-base-300">
          <tr>
            <th>Name</th>
            <th>Email</th>
            <th>Area</th>
            <th>Technologies</th>
          </tr>
        </thead>
        <tbody>
          <%= for user <- @users do %>
            <tr class="border-b border-gray-700 hover:bg-base-300 transition-colors">
              <td>{user.username}</td>
              <td>{user.email}</td>
              <td>
                <span class="badge bg-[#4e2a8e] border-none text-white font-semibold">
                  {String.upcase(user.area || "")}
                </span>
              </td>
              <td>{Enum.join(user.techs || [], ", ")}</td>
            </tr>
          <% end %>
        </tbody>
      </table>

    </div>
    """
  end
end
