defmodule Projects.RunnerSupervisor do
  @moduledoc "DynamicSupervisor for live-streaming `Projects.Runner` script executions."
  use DynamicSupervisor

  def start_link(opts), do: DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)

  def start_child(opts), do: DynamicSupervisor.start_child(__MODULE__, {Projects.Runner, opts})
end
