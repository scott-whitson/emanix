# The two EWM patches

`modules/ewm.nix` applies both through `pkgs.applyPatches`. Each is an upstream
bug, so each one's exit condition is the upstream fix.

## 1. `patches/ewm-keysym-hex.patch` — a key name reported only by number

EWM cannot bind a key Emacs reports only by number: the media/vendor keysyms in
the XF86 `0x1008xxxx` block, which is how this ThinkPad's dictation key arrives.
The elisp side cannot work around it.

`ewm--event-key-spec` sends a non-symbol `:key` as an INTEGER, and the
compositor's `keysym_from_value` reads an integer as a UNICODE CODEPOINT
(`xkb::utf32_to_keysym`). `0x10081247` is 268964423, far above Unicode's
`0x10FFFF`, so it resolves to NoSymbol however it is spelled.

Sending it as the string `"0x10081247"` instead reaches
`resolve_keysym_from_name`, which tries the name as-is, hyphens-as-underscores,
an XF86 prefix and a lossy-name table — but never parses hex.

**Exit condition.** Upstream gains a hex parse in `resolve_keysym_from_name`.

## 2. `patches/ewm-intercept-type.patch` — the default fails the declared type

`ewm-intercept-prefixes` declares `:type` as `character`, but its own default
holds `?\M-x` (134217848) and `?\s-f` (8388710) — both above `max-char`
(4194303), because a key event carrying a modifier bit is an integer, not a
character.

Nothing validated the list until the personal layer called `setopt` on it to add
the dictation key, at which point the upstream default failed its own declared
type on every startup.

**Exit condition.** Upstream widens the type, or corrects the default.
