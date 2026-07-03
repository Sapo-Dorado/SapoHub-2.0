defmodule SapoKit.MixProject do
  use Mix.Project

  def project do
    [
      app: :sapo_module_kit,
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

  # Keep this dependency list small and stable: it is the ONLY dependency
  # a SapoHub util module needs.
  defp deps do
    [
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:ecto_sql, "~> 3.13"},
      {:jason, "~> 1.2"}
    ]
  end
end
