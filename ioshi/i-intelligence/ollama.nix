{ config, lib, pkgs, ... }:
{
  # Local inference host for elisa (the eminix assistant). NixOS *system* service
  # (imported via profiles/eminix.nix, like ewm.nix/secrets.nix) — the
  # Home-Manager services.ollama module has no `loadModels`, only the system
  # module does. Uses Vulkan for GPU acceleration on the Radeon 780M (gfx1103);
  # ROCm is not supported on this iGPU, but Vulkan works via Mesa/RADV.
  # ELISA (Emacs, user scott) reaches it at localhost:11434 regardless of the
  # service user.
  services.ollama = {
    enable = true;
    package = pkgs.ollama-vulkan; # GPU acceleration via Vulkan (Radeon 780M)
    loadModels = [
      "qwen2.5-coder:3b" # ni default chat model (snappy, RAG-grounded)
      "qwen2.5-coder:7b" # heavier reasoning toggle
      "nomic-embed-text" # embeddings for ELISA
    ];
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "30m"; # keep the model warm between questions
      OLLAMA_NUM_THREADS = "8";  # 8 physical Zen 4 cores > 16 hyperthreads for LLM
    };
  };
}
