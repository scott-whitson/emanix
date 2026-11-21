;;; early-init.el --- pre-init settings -*- lexical-binding: t; -*-
;; Packages come from Nix (emacs-overlay), not package.el.
(setq package-enable-at-startup nil)
;; 256 MB, not the 64 MB this was until 2026-11-21. A full GC of a ~300 MB
;; heap measures 0.55 s here (gc-elapsed/gcs-done over a 635-hour daemon, and
;; 5 direct timings at 476-685 ms), and at 64 MB one lands every ~110 s --
;; 33 GCs/hour, 18 s of GC per hour of uptime. Per-GC cost grows slowly with
;; the heap because the mark phase follows the live set, so a higher ceiling
;; buys proportionally fewer pauses for a few hundred MB more peak RSS.
(setq gc-cons-threshold (* 256 1024 1024))
(setq inhibit-startup-screen t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
