defmodule SapoCore do
  @moduledoc """
  SapoCore keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  A writable scratch directory for this run of the app.

  Prefer this over `System.tmp_dir!/0` anywhere in sapo_core or a util
  module: under the Nix-built release, `System.tmp_dir!/0` can resolve to
  `/build` (a path baked into the release's environment from the Nix
  build sandbox that produced it, not anything that exists at runtime) --
  `mkdir`/`File.write` calls against it fail with `enoent`. Nix's own
  NixOS module sets `RELEASE_TMP` to a real, pre-created, writable
  directory (`<stateDir>/tmp`) specifically to give releases a safe
  scratch path; this just falls back to `System.tmp_dir!/0` when that
  isn't set (e.g. running under `mix` in dev/test, where the ordinary
  system temp dir is fine).
  """
  def tmp_dir! do
    System.get_env("RELEASE_TMP") || System.tmp_dir!()
  end
end
