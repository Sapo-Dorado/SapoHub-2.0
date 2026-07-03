defmodule SapoCore.Application do
  @moduledoc false

  use Application

  alias SapoCore.Generated.Registry

  @impl true
  def start(_type, _args) do
    children =
      [
        SapoCoreWeb.Telemetry,
        SapoCore.Repo,
        {DNSCluster, query: Application.get_env(:sapo_core, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: SapoCore.PubSub},
        {Task.Supervisor, name: SapoCore.TaskSupervisor},
        SapoCoreWeb.Endpoint
      ] ++ module_children()

    # Migrations are NOT run here: in dev/test the `sapo.migrate` alias runs
    # them; in a release, systemd ExecStartPre runs SapoCore.Release.migrate()
    # (after any staged snapshot restore).

    opts = [strategy: :one_for_one, name: SapoCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Children contributed by enabled util modules via `c:SapoKit.Module.children/1`.
  defp module_children do
    for mod <- Registry.modules(),
        child <- mod.children(Registry.config_for(mod)) do
      child
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SapoCoreWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
