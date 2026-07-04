defmodule SapoCore.Secrets do
  @moduledoc """
  Boot-time secret validation and status.

  Two tiers:

    * CORE secrets (`config :sapo_core, :core_secrets, [...]`) — missing one
      is a hard boot failure.
    * MODULE secrets (each module's `required_secrets/0`) — missing ones log
      a warning and surface in `status/0` for the Settings page; the module
      is expected to degrade gracefully.

  `validate!/3` is pure over its inputs (modules, core list, env map) for
  testability; the zero-arity call used at boot reads the registry and the
  real environment.
  """

  require Logger

  alias SapoCore.Generated.Registry

  @status_key {__MODULE__, :status}

  @typedoc "One row of secret status, as shown on the Settings page."
  @type entry :: %{var: String.t(), required_by: atom(), set?: boolean()}

  @doc """
  Validate secrets. Raises when a core secret is missing; warns per missing
  module secret; stores the full status for `status/0`. Returns the status.
  """
  @spec validate!([module()], [String.t()], %{String.t() => String.t()}) :: [entry()]
  def validate!(
        modules \\ Registry.modules(),
        core_vars \\ core_secrets(),
        env \\ System.get_env()
      ) do
    status = evaluate(modules, core_vars, env)

    case for %{required_by: :core, set?: false, var: var} <- status, do: var do
      [] ->
        :ok

      missing ->
        raise RuntimeError,
              "missing required core secrets: #{Enum.join(missing, ", ")}. " <>
                "Set them in the secrets file referenced by services.sapohub.secretsFile."
    end

    for %{required_by: owner, set?: false, var: var} <- status, owner != :core do
      Logger.warning(
        "secret #{var} required by module #{owner} is not set; " <>
          "the module should degrade gracefully (see Settings for status)"
      )
    end

    :persistent_term.put(@status_key, status)
    status
  end

  @doc "Compute secret status without side effects."
  @spec evaluate([module()], [String.t()], %{String.t() => String.t()}) :: [entry()]
  def evaluate(modules, core_vars, env) do
    core = for var <- core_vars, do: entry(var, :core, env)

    module_entries =
      for mod <- modules, var <- mod.required_secrets(), do: entry(var, mod.id(), env)

    core ++ module_entries
  end

  @doc "Status computed by the last `validate!` (for the Settings page)."
  @spec status() :: [entry()]
  def status, do: :persistent_term.get(@status_key, [])

  defp entry(var, owner, env) do
    %{var: var, required_by: owner, set?: (Map.get(env, var) || "") != ""}
  end

  defp core_secrets, do: Application.get_env(:sapo_core, :core_secrets, [])
end
