defmodule MyPlate.MixProject do
  use Mix.Project

  def project do
    [
      app: :my_plate,
      version: "0.3.0",
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

  # A util module depends ONLY on the SapoHub module kit.
  defp deps do
    [
      {:sapo_module_kit, path: "../../contract"}
    ]
  end
end
