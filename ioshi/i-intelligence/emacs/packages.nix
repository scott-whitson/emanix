# Single source of truth for the eminix Emacs package set + the org pin.
# Consumed by ioshi/i-intelligence/ewm.nix (the sole build site).
{ pkgs, ... }:
{
  # org ELPA pin — the current emacs-overlay snapshot resolves org with a
  # stale hash; override the source until inputs are regenerated upstream.
  orgOverride = _eself: esuper: {
    org = esuper.org.overrideAttrs (_old: {
      src = pkgs.fetchurl {
        url = "https://elpa.gnu.org/packages/org-9.8.7.tar";
        sha256 = "sha256-bYBtYtZkvZYG1qhPWBTBcWoH0xW+NW4m4m5ime5w+vg=";
      };
    });
  };

  list = epkgs: with epkgs; [
    meow
    vertico
    orderless
    consult
    marginalia
    embark
    embark-consult
    corfu
    dirvish
    magit
    org-roam
    org
    catppuccin-theme
    markdown-mode # transition: vault is still .md until the conversion sub-project
    vterm # native module built by nix; M-x package-install can't do this
  ];
}
