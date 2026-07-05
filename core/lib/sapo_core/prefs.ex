defmodule SapoCore.Prefs do
  @moduledoc """
  User UI preferences: nix-declared base ⊕ local overlay.

  * BASE: `services.sapohub.prefs` (a real nix option) serialized to
    `/etc/sapohub/prefs.json` (`:prefs_base` path config). GitHub is the
    source of truth.
  * OVERLAY: UI edits write `:prefs_overlay` (a JSON file in the state
    dir) and broadcast on `"prefs"` — instant effect, no deploy. On the
    next deploy, `sapohub-deploy` renders the overlay into
    `sapohub-prefs.nix` in the config repo (lib.mkDefault, so hand-written
    config wins), commits and pushes; the overlay is then consumed.

  Known keys:
  * `"dashboard_button.<module_id>"` → button variant id (`"default"` or
    a `dashboard_buttons/1` option id)
  * `"statusline.<item_id>"` → boolean (item enabled)
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
