{ config, lib, pkgs, ... }:
{
  # Local inference host for elisa (the eminix assistant). NixOS *system* service
  # — the Home-Manager services.ollama module has no `loadModels`, only the
  # system module does.
  #
  # Imported by profiles/roles/workstation.nix, NOT by profiles/eminix.nix. That
  # distinction is load-bearing: a workstation host, so this file
  # reaches only workstation hosts. non-workstation hosts set services.ollama.enable = false
  # and get plain pkgs.ollama. If this moved into the eminix core, the Vulkan
  # package below would follow onto a WSL box and a headless server that have no
  # use for it.
  #
  # Vulkan for GPU acceleration on the Radeon 780M (gfx1103): ROCm does not
  # support this iGPU, but Vulkan works via Mesa/RADV.
  #
  # elisa (Emacs, any user) reaches it at localhost:11434 regardless of the
  # service user.
  services.ollama = {
    enable = true;
    package = pkgs.ollama-vulkan; # GPU acceleration via Vulkan (Radeon 780M)
    # These must match eminix/elisa-models in emacs/lisp/eminix-elisa.el. A model
    # elisa can toggle to but that is not listed here is not pre-pulled, so the
    # first use stalls on a cold download — or fails outright offline.
    loadModels = [
      "qwen2.5-coder:3b" # elisa default: code-focused, snappy, RAG-grounded
      "qwen2.5:7b" # heavier toggle: general-purpose, not code-specific
      "nomic-embed-text" # embeddings for elisa
    ];
    environmentVariables = {
      OLLAMA_KEEP_ALIVE = "30m";  # keep the model warm between questions
      OLLAMA_NUM_THREADS = "8";   # 8 physical Zen 4 cores > 16 hyperthreads for LLM
      OLLAMA_IGPU_ENABLE = "1";   # allow Vulkan to use the Radeon 780M iGPU
    };
  };
}
