defmodule ShowcaseAppWeb.RegistrationLive do
  use ShowcaseAppWeb, :live_view

  alias ShowcaseApp.{User, Repo}

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       step: 1,
       username: "",
       email: "",
       password: "",
       area: nil,
       techs: []
     )}
  end


  def handle_event("next_step_1", %{"username" => u, "email" => e, "password" => p}, socket) do
    {:noreply, assign(socket, step: 2, username: u, email: e, password: p)}
  end

  def handle_event("next_step_2", _params, socket) do
    {:noreply, assign(socket, step: 3)}
  end

  def handle_event("next_step_3", _params, socket) do
    {:noreply, assign(socket, step: 4)}
  end

  def handle_event("prev_step", _params, socket) do
    {:noreply, assign(socket, step: socket.assigns.step - 1)}
  end

  def handle_event("select_area", %{"value" => new_area}, socket) do
    techs = if socket.assigns.area == new_area, do: socket.assigns.techs, else: []
    {:noreply, assign(socket, area: new_area, techs: techs)}
  end

  def handle_event("toggle_tech", %{"value" => tech}, socket) do
    techs = socket.assigns.techs
    new_techs = if tech in techs, do: List.delete(techs, tech), else: [tech | techs]
    {:noreply, assign(socket, techs: new_techs)}
  end

def handle_event("confirm", _params, socket) do
    user_params = %{
      "username" => socket.assigns.username,
      "email" => socket.assigns.email,
      "password" => socket.assigns.password,
      "area" => socket.assigns.area,
      "techs" => socket.assigns.techs
    }

    case Repo.insert(User.changeset(%User{}, user_params)) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Profile created successfully!")
         |> push_navigate(to: ~p"/users")}
      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error creating profile. Please try again.")}
    end
  end

  defp get_techs("frontend"), do: [{"react", "React", "⚛️"}, {"vue", "Vue", "🟢"}, {"angular", "Angular", "🅰️"}, {"svelte", "Svelte", "🔥"}, {"tailwind", "Tailwind", "🌊"}, {"ts", "TypeScript", "📘"}]
  defp get_techs("backend"), do: [{"elixir", "Elixir", "💧"}, {"node", "Node.js", "🟩"}, {"python", "Python", "🐍"}, {"ruby", "Ruby", "💎"}, {"go", "Go", "🐹"}, {"java", "Java", "☕"}]
  defp get_techs("devops"), do: [{"docker", "Docker", "🐳"}, {"k8s", "Kubernetes", "☸️"}, {"aws", "AWS", "☁️"}, {"terraform", "Terraform", "🏗️"}, {"cicd", "CI/CD", "🔄"}, {"linux", "Linux", "🐧"}]
  defp get_techs("qa"), do: [{"selenium", "Selenium", "🤖"}, {"cypress", "Cypress", "🌲"}, {"playwright", "Playwright", "🎭"}, {"jest", "Jest", "🃏"}, {"postman", "Postman", "📫"}, {"appium", "Appium", "📱"}]
  defp get_techs(_), do: []

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-300 flex flex-col items-center justify-center p-6" data-theme="dark">
      <div class="max-w-xl w-full">

        <div class="mb-8">
          <div class="flex justify-between text-sm text-gray-400 mb-2 font-medium">
            <span>Step {@step} of 4</span>
            <span><%= @step * 25 %>%</span>
          </div>
          <progress
            class="progress w-full h-3 bg-base-100 [&::-webkit-progress-value]:bg-[#4e2a8e] [&::-moz-progress-bar]:bg-[#4e2a8e]"
            value={"#{@step * 25}"}
            max="100">
          </progress>
        </div>

        <div class="bg-base-100 p-8 rounded-2xl shadow-xl">

          <%= if @step == 1 do %>
            <h2 class="text-2xl font-bold text-white mb-6">Create Account</h2>
            <form id="registration-form" phx-submit="next_step_1" class="space-y-4">
              <fieldset class="fieldset">
                <legend class="fieldset-legend text-gray-300">Username</legend>
                <input type="text" name="username" value={@username} required class="input w-full bg-base-200 text-white focus:border-[#4e2a8e]" />
              </fieldset>

              <fieldset class="fieldset">
                <legend class="fieldset-legend text-gray-300">Email</legend>
                <input type="email" name="email" value={@email} required class="input w-full bg-base-200 text-white focus:border-[#4e2a8e]" />
              </fieldset>

              <fieldset class="fieldset">
                <legend class="fieldset-legend text-gray-300">Password</legend>
                <input type="password" name="password" value={@password} required class="input w-full bg-base-200 text-white focus:border-[#4e2a8e]" />
              </fieldset>

              <div class="mt-8 flex justify-end">
                <button type="submit" class="btn bg-[#4e2a8e] hover:bg-[#3a1f6a] text-white border-none flex items-center gap-2">
                  Next <.icon_arrow />
                </button>
              </div>
            </form>
          <% end %>

          <%= if @step == 2 do %>
            <h2 class="text-2xl font-bold text-white mb-6">What is your Area?</h2>
            <div class="grid grid-cols-2 gap-4 mb-8">
              <.selection_card name="Frontend" id="frontend" icon="💻" selected={@area == "frontend"} event="select_area" />
              <.selection_card name="Backend" id="backend" icon="⚙️" selected={@area == "backend"} event="select_area" />
              <.selection_card name="DevOps" id="devops" icon="🚀" selected={@area == "devops"} event="select_area" />
              <.selection_card name="QA" id="qa" icon="🐛" selected={@area == "qa"} event="select_area" />
            </div>

            <div class="flex justify-between mt-8">
              <button phx-click="prev_step" class="btn btn-outline border-gray-600 text-gray-300 hover:bg-gray-800">Previous</button>
              <button phx-click="next_step_2" disabled={is_nil(@area)} class="btn bg-[#4e2a8e] hover:bg-[#3a1f6a] text-white border-none flex items-center gap-2 disabled:bg-gray-800 disabled:text-gray-600">
                Next <.icon_arrow />
              </button>
            </div>
          <% end %>

          <%= if @step == 3 do %>
            <h2 class="text-2xl font-bold text-white mb-2">Select Technologies</h2>
            <p class="text-sm text-gray-400 mb-6">Choose the tools you are familiar with.</p>

            <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 mb-8">
              <%= for {id, name, icon} <- get_techs(@area) do %>
                <.selection_card name={name} id={id} icon={icon} selected={id in @techs} event="toggle_tech" />
              <% end %>
            </div>

            <div class="flex justify-between mt-8">
              <button phx-click="prev_step" class="btn btn-outline border-gray-600 text-gray-300 hover:bg-gray-800">Previous</button>
              <button phx-click="next_step_3" disabled={@techs == []} class="btn bg-[#4e2a8e] hover:bg-[#3a1f6a] text-white border-none flex items-center gap-2 disabled:bg-gray-800 disabled:text-gray-600">
                Next <.icon_arrow />
              </button>
            </div>
          <% end %>

          <%= if @step == 4 do %>
            <h2 class="text-2xl font-bold text-white mb-6">Profile Summary</h2>

            <div class="bg-base-200 p-6 rounded-xl space-y-4 text-gray-300">
              <div class="flex justify-between border-b border-gray-700 pb-2">
                <span class="font-semibold text-gray-400">Username:</span>
                <span class="text-white"><%= @username %></span>
              </div>
              <div class="flex justify-between border-b border-gray-700 pb-2">
                <span class="font-semibold text-gray-400">Email:</span>
                <span class="text-white"><%= @email %></span>
              </div>
              <div class="flex justify-between border-b border-gray-700 pb-2">
                <span class="font-semibold text-gray-400">Password:</span>
                <span class="text-white tracking-widest"><%= String.duplicate("*", String.length(@password)) %></span>
              </div>
              <div class="flex justify-between border-b border-gray-700 pb-2 items-center">
                <span class="font-semibold text-gray-400">Area:</span>
                <span class="badge bg-[#4e2a8e] border-none text-white font-bold p-3">
                  <%= String.upcase(@area || "") %>
                </span>
              </div>
              <div>
                <span class="font-semibold text-gray-400 block mb-3">Technologies:</span>
                <div class="flex flex-wrap gap-2">
                  <%= for tech <- @techs do %>
                    <% {_, tech_name, tech_icon} = List.keyfind(get_techs(@area), tech, 0) %>
                    <span class="badge badge-outline border-[#4e2a8e] text-white p-3">
                      <%= tech_icon %> <%= tech_name %>
                    </span>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="flex justify-between mt-8">
              <button phx-click="prev_step" class="btn btn-outline border-gray-600 text-gray-300 hover:bg-gray-800">Previous</button>
              <button phx-click="confirm" class="btn btn-success text-white border-none flex items-center gap-2">
                Confirm & Create
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-5 h-5"><path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" /></svg>
              </button>
            </div>
          <% end %>

        </div>
      </div>
    </div>
    """
  end

  def selection_card(assigns) do
    ~H"""
    <button
      phx-click={@event}
      phx-value-value={@id}
      class={[
        "cursor-pointer border-2 rounded-xl p-4 flex flex-col items-center justify-center transition-all h-28 text-center",
        @selected && "border-[#4e2a8e] bg-[#4e2a8e]/20 text-white scale-105 shadow-lg",
        !@selected && "border-gray-700 text-gray-400 hover:border-gray-500 hover:bg-base-200"
      ]}
    >
      <div class="text-3xl mb-1"><%= @icon %></div>
      <div class="font-semibold text-sm"><%= @name %></div>
    </button>
    """
  end

  def icon_arrow(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-5 h-5">
      <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />
    </svg>
    """
  end
end
