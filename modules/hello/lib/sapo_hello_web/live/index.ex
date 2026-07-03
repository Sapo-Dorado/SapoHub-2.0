defmodule SapoHelloWeb.Live.Index do
  @moduledoc """
  Reference LiveView page for the hello module. Deliberately minimal:
  shows greetings, lets you add one, and demonstrates PubSub updates.
  """
  use SapoKit.Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SapoKit.PubSub.subscribe("hello:greetings")

    {:ok, assign(socket, greetings: SapoHello.list_greetings(), name: "")}
  end

  @impl true
  def handle_event("create", %{"name" => name}, socket) do
    case SapoHello.create_greeting(%{name: name}) do
      {:ok, _greeting} ->
        {:noreply, assign(socket, name: "")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create greeting")}
    end
  end

  @impl true
  def handle_info({:greeting_created, _greeting}, socket) do
    {:noreply, assign(socket, greetings: SapoHello.list_greetings())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="space-y-4">
        <h1 class="text-xl font-semibold">Hello Module</h1>
        <p class="text-sm opacity-70">
          This is the reference util module. See <code>modules/hello</code> and
          <code>docs/module-authoring.md</code>.
        </p>

        <form phx-submit="create" class="flex gap-2">
          <input
            type="text"
            name="name"
            value={@name}
            placeholder="Your name"
            class="input input-bordered flex-1"
          />
          <button type="submit" class="btn btn-primary">Greet</button>
        </form>

        <ul id="greetings" class="space-y-1">
          <li :for={g <- @greetings} class="text-sm">
            Hello, {g.name}!
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
