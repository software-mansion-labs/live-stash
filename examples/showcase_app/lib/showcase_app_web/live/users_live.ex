defmodule ShowcaseAppWeb.UsersLive do
  use ShowcaseAppWeb, :live_view

  alias ShowcaseApp.{User, Repo}

  def mount(_params, _session, socket) do
    {:ok, assign(socket, users: Repo.all(User))}
  end

  def render(assigns) do
    ~H"""
    <div class="p-8">
      <h1 class="text-3xl font-bold mb-6">Registered Users</h1>
      <table class="table w-full">
        <thead>
          <tr>
            <th>Name</th>
            <th>Email</th>
            <th>Area</th>
            <th>Technologies</th>
          </tr>
        </thead>
        <tbody>
          <%= for user <- @users do %>
            <tr>
              <td>{user.username}</td>
              <td>{user.email}</td>
              <td>{user.area}</td>
              <td>{Enum.join(user.techs, ", ")}</td>
            </tr>
          <% end %>
        </tbody>
      </table>
    </div>
    """
  end
end
