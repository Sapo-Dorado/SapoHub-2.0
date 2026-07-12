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
    <div class="min-h-[100dvh] bg-[#0D1113] text-[#E6ECE9]">
      <SapoCoreWeb.Statusline.statusline crumb="hello" items={@statusline} />
      <SapoCoreWeb.Layouts.flash_group flash={@flash} />

      <main class="max-w-[640px] mx-auto px-4 py-8 space-y-6">
        <div class="flex items-center gap-2.5 font-mono text-[11px] font-semibold uppercase tracking-[.14em] text-[#86948F]">
          <span>Hello module</span>
          <span class="h-px flex-1 bg-[#242D31]"></span>
        </div>

        <p class="font-mono text-[12.5px] text-[#86948F]">
          This is the reference util module. See <code class="text-[#E6ECE9]">modules/hello</code>
          and <code class="text-[#E6ECE9]">docs/module-authoring.md</code>.
        </p>

        <form phx-submit="create" class="flex gap-2">
          <input
            type="text"
            name="name"
            value={@name}
            placeholder="your name"
            class="flex-1 box-border px-3 py-[9px] rounded-[4px] bg-[#151B1E] border border-[#242D31] text-sm text-[#E6ECE9] placeholder-[#86948F] focus:border-[#7FB069] focus:outline-none font-mono"
          />
          <button
            type="submit"
            class="px-3 py-[7px] rounded-[4px] border border-[#242D31] font-mono text-[11.5px] text-[#86948F] hover:text-[#E6ECE9] hover:border-[#3C5934] cursor-pointer"
          >
            Greet
          </button>
        </form>

        <div class="rounded-[4px] border border-[#242D31] divide-y divide-[#242D31] overflow-hidden">
          <p
            :for={g <- @greetings}
            id={"greeting-#{g.id}"}
            class="px-3 py-2.5 bg-[#151B1E] font-mono text-[12.5px] text-[#E6ECE9]"
          >
            Hello, {g.name}!
          </p>
          <p :if={@greetings == []} class="px-3 py-6 text-center font-mono text-[12px] text-[#86948F]">
            No greetings yet.
          </p>
        </div>
      </main>
    </div>
    """
  end
end
