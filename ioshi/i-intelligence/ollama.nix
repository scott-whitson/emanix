{ config, lib, pkgs, ... }:
{
  # Local inference host for ni (the eminix assistant). Home-Manager user
  # service — keeps ni in the i-intelligence tree next to pi.nix. CPU-only:
  # the Radeon 780M (gfx1103) is unsupported by ROCm, and Ollama auto-detects
  # CPU cores, so no acceleration or num_thread tuning is set here.
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
