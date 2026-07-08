defmodule SapoCore.Prefs do
  @moduledoc """
  User UI preferences: nix-declared base ⊕ local overlay.

  * BASE: `services.sapohub.prefs` (a real nix option) serialized to
    `/etc/sapohub/prefs.json` (`:prefs_base` path config). GitHub is the
    source of truth.
  * OVERLAY: UI edits write `:prefs_overlay` (a JSON file in the state
    dir) and broadcast on `"prefs"` — instant effect, no deploy.

  The overlay only ever reaches git/nix on a deploy run with
  `--sync-prefs` — the Settings "Deploy" button passes it. A bare
  `sapohub-deploy` (run by hand, over SSH, from cron, anywhere outside
  the UI) skips that sync entirely: git/nix is treated as authoritative,
  the overlay file is left untouched (nothing lost — still live at
  runtime, still queued for the next `--sync-prefs` run), and the
  rebuild uses exactly what's already committed. When the sync does run,
  `sapohub-deploy` renders the overlay into `sapohub-prefs.nix` in the
  config repo (`lib.mkDefault`, so hand-written config always wins),
  commits and pushes; the overlay is then consumed. See
  `nix/deploy-script.nix`.

  Known keys:
  * `"dashboard_button.<module_id>"` → the selected `dashboard_buttons/1`
    option id (`"default"` for the standard icon + title tile)
  * `"dashboard_order"` → comma-separated slot ids, front to back (see
    `SapoCore.Dashboard`); unset or unrecognized ids fall back to the
    Nix module order with `assistant` last
  * `"statusline.<item_id>"` → boolean (item enabled); ignored once
    `"statusline_order"` is set (see below)
  * `"statusline_order"` → comma-separated item ids, front to back (see
    `SapoCore.Statusline`); when set, it's the definitive list (only
    those ids show); unset falls back to natural order filtered by each
    item's own `"statusline.<item_id>"` toggle
  """

  @doc "Effective value for `key` (overlay wins over base, then default)."
  def get(key, default \\ nil) when is_binary(key) do
    Map.get(overlay(), key, Map.get(base(), key, default))
  end

  @doc "All effective prefs (base merged with overlay)."
  def all, do: Map.merge(base(), overlay())

  @doc "Set a pref in the overlay (instant; synced to git on next deploy)."
  def put(key, value) when is_binary(key) do
    path = overlay_path()
    File.mkdir_p!(Path.dirname(path))
    updated = Map.put(overlay(), key, value)
    File.write!(path, Jason.encode!(updated, pretty: true))
    SapoKit.PubSub.broadcast("prefs", {:pref_changed, key, value})
    :ok
  end

  defp base do
    with path when is_binary(path) <- Application.get_env(:sapo_core, :prefs_base),
         {:ok, raw} <- File.read(path),
         {:ok, %{} = map} <- Jason.decode(raw) do
      map
    else
      _ -> %{}
    end
  end

  defp overlay do
    with {:ok, raw} <- File.read(overlay_path()),
         {:ok, %{} = map} <- Jason.decode(raw) do
      map
    else
      _ -> %{}
    end
  end

  defp overlay_path, do: Application.fetch_env!(:sapo_core, :prefs_overlay)
end
