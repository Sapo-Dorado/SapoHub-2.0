defmodule Skills.MixProject do
  use Mix.Project

  def project do
    [
      app: :skills,
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

  # A util module depends only on the SapoHub module kit.
  defp deps do
    [
      {:sapo_module_kit, path: "../../contract"}
    ]
  end
end
