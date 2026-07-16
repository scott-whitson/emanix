;;; early-init.el --- pre-init settings -*- lexical-binding: t; -*-
;; Packages come from Nix (emacs-overlay), not package.el.
(setq package-enable-at-startup nil)
(setq gc-cons-threshold (* 64 1024 1024))
(setq inhibit-startup-screen t)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
