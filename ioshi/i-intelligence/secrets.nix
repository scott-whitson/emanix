{ ... }:
{
  # OpenRouter keys (read by scott-openrouter.el at ~/.pi/agent/auth.json).
  # Decrypted at activation from secrets/openrouter-auth.age. Real values are
  # inserted by `agenix -e secrets/openrouter-auth.age` — the committed file is
  # a placeholder until then.
  age.secrets.openrouter-auth = {
    file = ../../secrets/openrouter-auth.age;
    path = "/home/scott/.pi/agent/auth.json";
    owner = "scott";
    group = "users";
    mode = "0600";
  };
}
