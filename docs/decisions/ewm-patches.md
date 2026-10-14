# The EWM patch

`modules/ewm.nix` applies it through `pkgs.applyPatches`. It is an upstream bug,
so its exit condition is the upstream fix.

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

## Retired: `patches/ewm-intercept-type.patch`

`ewm-intercept-prefixes` declared `:type` as `character` while its own default
held `?\M-x` (134217848) and `?\s-f` (8388710) — both above `max-char`
(4194303), because a key event carrying a modifier bit is an integer, not a
character. Nothing validated the list until the personal layer called `setopt` to
add the dictation key, at which point the upstream default failed its own declared
type on every startup.

The patch widened the inline `:type` to accept `integer`.

**Retired 2026-10-14, on the exit condition its own entry named.** Upstream fixed
it in `e43ecc5 fix(input): accept modified key events in Customize` and
`c67705c fix(input): type key options by what the parser accepts`, introducing a
dedicated `ewm-key` widget:

```elisp
(define-widget 'ewm-key 'lazy
  "A single key, as an integer event or a key description."
  :tag "Key"
  :type '(choice character integer string)
  :match (lambda (_ key) (ewm--key-event key)))
```

That is a wider fix than the patch was — it validates the parser's own contract
rather than widening one option's type — so the patch was deleted rather than
rebased. The file is gone; `modules/ewm.nix` no longer names it.

This is why the patch set is now one rather than two, and it is worth noting what
it cost to find out: the patch had been silently inapplicable since the upstream
fix landed, so `nix flake update ewm` could not be run at all without first
noticing the hunk failure. Any future ewm patch should be checked with
`patch -p1 --dry-run` against the candidate rev before the lock is moved.
