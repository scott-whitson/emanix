{ ... }:
{
  # OpenRouter keys (read by scott-openrouter.el + pi at ~/.pi/agent/auth.json).
  # Decrypt to agenix's DEFAULT path (/run/agenix/openrouter-auth), scott-readable.
  # We must NOT set path = "~/.pi/agent/auth.json": agenix would `mkdir -p` that
  # dir as root during activation and collide with Home Manager (which owns
  # ~/.pi/agent), failing HM activation on first boot (caught by a VM boot test).
  # pi.nix symlinks ~/.pi/agent/auth.json -> this secret instead.
  age.secrets.openrouter-auth = {
    file = ../../secrets/openrouter-auth.age;
    owner = "scott";
    group = "users";
    mode = "0400";
  };
}
