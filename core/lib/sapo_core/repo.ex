defmodule SapoCore.Repo do
  use Ecto.Repo,
    otp_app: :sapo_core,
    adapter: Ecto.Adapters.SQLite3
end
