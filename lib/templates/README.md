# Templates

Files here are substituted, not rendered from scratch in Nix. A template earns
its place when the target format has enough fixed structure (comments,
ordering, syntax) that reproducing it as a Nix string with dozens of
interpolation holes would be harder to read than the file it's supposed to
produce.

## `btop.theme.in`

btop's theme format has 42 `theme[...]="#rrggbb"` entries. `lib/themes.nix`'s
`btop` renderer replaces every `@slot@` placeholder with the matching palette
colour (`builtins.replaceStrings`); see that file's own comment for how the
placeholders were derived from the previously-committed theme.
