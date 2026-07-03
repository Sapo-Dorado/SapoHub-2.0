defmodule SapoHello.MixProject do
  use Mix.Project

  def project do
    [
      app: :sapo_hello,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # A util module depends ONLY on the SapoHub module kit. When composed by
  # Nix, this path is substituted with the store path of the kit source.
  defp deps do
    [
      {:sapo_module_kit, path: "../../contract"}
    ]
  end
end
