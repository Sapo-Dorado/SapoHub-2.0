# Machine-owned — overwritten by `sapohub-deploy` (or Settings → Deploy)
# whenever there are local UI preference changes to sync (see
# SapoCore.Prefs / nix/deploy-script.nix). Starts empty so the very first
# `nixos-rebuild switch`, before any deploy has run, has something valid
# to import. Committed to git so preferences survive a redeploy on a new
# host. Don't hand-edit for long-lived changes — anything you set
# directly on `services.sapohub.prefs` in your own config always wins
# (this file's values are wrapped in `lib.mkDefault`).
{ ... }:
{
  services.sapohub.prefs = { };
}
