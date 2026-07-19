{ config, lib, pkgs, ... }:
{
  # Local inference host for ni (the eminix assistant). NixOS *system* service
  # (imported via profiles/eminix.nix, like ewm.nix/secrets.nix) — the
  # Home-Manager services.ollama module has no `loadModels`, only the system
  # module does. CPU-only: the Radeon 780M (gfx1103) is unsupported by ROCm,
  # and Ollama auto-detects CPU cores, so no acceleration/num_thread is set.
  # ELISA (Emacs, user scott) reaches it at localhost:11434 regardless of the
  # service user.
  services.ollama = {
    enable = true;
    loadModels = [
      "qwen2.5-coder:3b"   # ni default chat model (snappy, RAG-grounded)
      "qwen2.5-coder:7b"   # heavier reasoning toggle
      "nomic-embed-text"   # embeddings for ELISA
    ];
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "30m";   # keep the model warm between questions
    };
  };
}
