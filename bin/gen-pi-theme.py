#!/usr/bin/env python3
"""
gen-pi-theme.py — generate a pi coding agent theme.json from a colors.toml.

Usage:
    gen-pi-theme.py <colors.toml> <output.json>   # explicit src + dst
    gen-pi-theme.py <colors.toml>                 # writes <stem>.json next to source
    gen-pi-theme.py <theme-dir>                   # reads colors.toml, writes pi-agent-theme.json

Reads a catppuccin colors.toml (single source of truth) and emits a pi-agent
theme JSON that matches the installed schema. Every pi agent color token is
mapped from the catppuccin semantic names in the TOML.

Run by dot-theme-set on theme switch. Also safe to run by hand to verify.
"""

import json
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:
    import tomli as tomllib  # Python < 3.11 fallback

SCHEMA_URL = (
    "https://raw.githubusercontent.com/earendil-works/pi/main/"
    "packages/coding-agent/src/modes/interactive/theme/theme-schema.json"
)

# ──────────────────────────────────────────────────────────────────────
# Background groups per variant.
# Mocha (dark) uses deeper surfaces for tool boxes so they stand out against
# the dark terminal. Latte (light) uses mantle/base to keep tool boxes close
# to the terminal's own bg so they don't read as separate cards.
# ──────────────────────────────────────────────────────────────────────
BG_DARK = {
    "user_message_bg": "mantle",
    "tool_pending_bg": "base",
    "tool_success_bg": "surface0",
    "tool_error_bg": "surface0",
    "custom_message_bg": "mantle",
    "selected_bg": "surface0",
}

BG_LIGHT = {
    "user_message_bg": "mantle",
    "tool_pending_bg": "mantle",
    "tool_success_bg": "mantle",
    "tool_error_bg": "mantle",
    "custom_message_bg": "base",
    "selected_bg": "surface0",
}

# Thinking-level gradient: 6 steps, same semantic names for both variants
# (catppuccin provides brighter values on dark, deeper values on light).
THINK = ["overlay1", "surface2", "blue", "sapphire", "mauve", "pink"]


def detect_variant(toml: dict) -> str:
    """Return 'dark' or 'light' from perceived brightness of background."""
    bg = toml.get("ui", {}).get("background", "#000000").lstrip("#")
    r, g, b = int(bg[0:2], 16), int(bg[2:4], 16), int(bg[4:6], 16)
    luminance = (r * 0.299 + g * 0.587 + b * 0.114) / 255
    return "light" if luminance > 0.5 else "dark"


def build_colors(toml: dict) -> tuple[dict, dict]:
    """Return (vars_map, colors) for a pi-agent theme."""
    c = toml["catppuccin"]
    ui = toml["ui"]
    variant = detect_variant(toml)
    bg_map = BG_DARK if variant == "dark" else BG_LIGHT

    # vars — flat map of every semantic name so colors{} can reference them.
    vars_map = dict(c)
    for i in range(16):
        key = f"color{i}"
        if key in toml.get("ansi", {}):
            vars_map[key] = toml["ansi"][key]
    vars_map.update({
        "foreground": ui["foreground"],
        "background": ui["background"],
        "cursor": ui["cursor"],
        "accent": ui["accent"],
        "selection_foreground": ui["selection_foreground"],
        "selection_background": ui["selection_background"],
    })

    colors = {
        # Core UI
        "accent":                "accent",
        "border":                "blue",
        "borderAccent":          "sapphire",
        "borderMuted":           "surface2",
        "success":               "green",
        "error":                 "red",
        "warning":               "yellow",
        "muted":                 "overlay0",
        "dim":                   "overlay1",
        "text":                  "text",
        "thinkingText":          "subtext1",

        # Backgrounds
        "selectedBg":            bg_map["selected_bg"],
        "userMessageBg":         bg_map["user_message_bg"],
        "userMessageText":       "text",
        "customMessageBg":       bg_map["custom_message_bg"],
        "customMessageText":     "text",
        "customMessageLabel":    "pink",
        "toolPendingBg":         bg_map["tool_pending_bg"],
        "toolSuccessBg":         bg_map["tool_success_bg"],
        "toolErrorBg":           bg_map["tool_error_bg"],
        "toolTitle":             "text",
        "toolOutput":            "subtext1",

        # Markdown
        "mdHeading":             "peach",
        "mdLink":                "blue",
        "mdLinkUrl":             "sky",
        "mdCode":                "teal",
        "mdCodeBlock":           "text",
        "mdCodeBlockBorder":     "surface2",
        "mdQuote":               "subtext1",
        "mdQuoteBorder":         "surface2",
        "mdHr":                  "surface2",
        "mdListBullet":          "mauve",

        # Tool diffs
        "toolDiffAdded":         "green",
        "toolDiffRemoved":       "red",
        "toolDiffContext":       "overlay1",

        # Syntax highlighting
        "syntaxComment":         "overlay1",
        "syntaxKeyword":         "mauve",
        "syntaxFunction":        "blue",
        "syntaxVariable":        "text",
        "syntaxString":          "green",
        "syntaxNumber":          "peach",
        "syntaxType":            "sapphire",
        "syntaxOperator":        "sky",
        "syntaxPunctuation":     "text",

        # Thinking levels
        "thinkingOff":           THINK[0],
        "thinkingMinimal":       THINK[1],
        "thinkingLow":           THINK[2],
        "thinkingMedium":        THINK[3],
        "thinkingHigh":          THINK[4],
        "thinkingXhigh":         THINK[5],

        # Bash mode
        "bashMode":              "green",
    }

    return vars_map, colors


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(f"Usage: {argv[0]} <colors.toml|theme-dir> [output.json]", file=sys.stderr)
        return 1

    src = Path(argv[1])
    if src.is_dir():
        colors_toml = src / "colors.toml"
        out = src / "pi-agent-theme.json"
    elif src.suffix == ".toml":
        colors_toml = src
        out = Path(argv[2]) if len(argv) > 2 else src.with_suffix(".json")
    else:
        print(f"Unknown source: {src}", file=sys.stderr)
        return 1

    if not colors_toml.is_file():
        print(f"colors.toml not found: {colors_toml}", file=sys.stderr)
        return 1

    with open(colors_toml, "rb") as f:
        toml = tomllib.load(f)

    variant = detect_variant(toml)
    theme_name = colors_toml.parent.name
    vars_map, colors = build_colors(toml)

    theme = {
        "$schema": SCHEMA_URL,
        "name": theme_name,
        "variant": variant,
        "vars": vars_map,
        "colors": colors,
    }

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(theme, indent=2) + "\n")
    print(f"Wrote {out}  ({theme_name}, {variant})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
