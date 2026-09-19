;;; emanix-arc-test.el --- ARC compatibility bridge contracts -*- lexical-binding: t; -*-
;;
;; These tests intentionally load the distro glue without loading ARC. The
;; installed package is pinned to an older revision while the retrieval UI is
;; landing, so the bridge must choose the new surface when it exists and keep
;; the old commands usable when it does not. No Ollama, database, embedding
;; extension or ARC package is part of this test.

(require 'ert)
(require 'cl-lib)

(defconst emanix-arc-test--root
  (expand-file-name ".." (file-name-directory
                           (or load-file-name buffer-file-name))))
(add-to-list 'load-path emanix-arc-test--root)
(add-to-list 'load-path (file-name-directory (or load-file-name buffer-file-name)))
;; These are normally declared by ARC. Declaring them here makes the test's
;; dynamic `let' bindings work even when no ARC package is installed.
(defvar arc-vault-collections nil)
(defvar arc-option-collections nil)
(require 'emanix-arc)

(defun emanix-arc-test--config-file ()
  "Return the config.el path, with a Nix-check override when needed."
  (or (getenv "EMANIX_ARC_CONFIG")
      (expand-file-name "config.el" emanix-arc-test--root)))

(defun emanix-arc-test--with-config-text (needle)
  "Return non-nil when config.el contains NEEDLE literally."
  (with-temp-buffer
    (insert-file-contents (emanix-arc-test--config-file))
    (goto-char (point-min))
    (search-forward needle nil t)))

(ert-deftest emanix-arc-old-package-fallbacks-do-not-need-ollama ()
  "The pinned answer package remains reachable when search is absent."
  (let (general vault options)
    (cl-letf (((symbol-function 'arc-search-show) nil)
              ((symbol-function 'emanix/arc--ollama-running-p)
               (lambda () t))
              ((symbol-function 'arc-ask)
               (lambda (query) (setq general query)))
              ((symbol-function 'arc-ask-vault)
               (lambda (query) (setq vault query)))
              ((symbol-function 'arc-ask-options)
               (lambda (query) (setq options query))))
      ;; Keep the real `emanix/arc-ask' wrapper in this test. Only its external
      ;; Ollama probe and ARC command are stubbed, so the guard and call are
      ;; both exercised rather than bypassed by stubbing the bridge itself.
      (emanix/arc-search "general")
      (emanix/arc-search-vault "vault")
      (emanix/arc-search-options "options"))
    (should (equal general "general"))
    (should (equal vault "vault"))
    (should (equal options "options"))))

(ert-deftest emanix-arc-new-package-dispatches-to-search-show ()
  "The newer package owns the retrieval call when its UI is present."
  (let (calls)
    (cl-letf (((symbol-function 'arc-search-show)
               (lambda (query &optional scope)
                 (push (list query scope) calls)))
              ((symbol-function 'arc-ask)
               (lambda (&rest _) (error "old arc-ask path selected")))
              ((symbol-function 'emanix/arc-ask)
               (lambda (&rest _) (error "Emanix fallback selected"))))
      (emanix/arc-search "general"))
    (should (equal calls '(("general" nil))))))

(ert-deftest emanix-arc-scoped-search-builds-collection-scope ()
  "Vault and options dispatch pass their configured collections exactly."
  (let (calls)
    (cl-letf (((symbol-function 'arc-search-show)
               (lambda (query &optional scope)
                 (push (list query scope) calls)))
              ((symbol-function 'arc-scope)
               (lambda (&rest keys) keys))
              ((symbol-function 'arc-ask-vault)
               (lambda (&rest _) (error "vault fallback selected")))
              ((symbol-function 'arc-ask-options)
               (lambda (&rest _) (error "options fallback selected"))))
      (let ((arc-vault-collections '("vault"))
            (arc-option-collections '("nix options" "hm options")))
        (emanix/arc-search-vault "v")
        (emanix/arc-search-options "o")))
    (should (equal calls
                   '(("o" (:collections ("nix options" "hm options")))
                     ("v" (:collections ("vault"))))))))

(ert-deftest emanix-arc-scoped-search-falls-back-without-scope-constructor ()
  "Nonempty configured scopes must not broaden when `arc-scope' is absent."
  (let (vault options)
    (cl-letf (((symbol-function 'arc-search-show)
               (lambda (&rest _)
                 (error "unscoped retrieval path selected")))
              ((symbol-function 'arc-scope) nil)
              ((symbol-function 'arc-ask-vault)
               (lambda (query) (setq vault query)))
              ((symbol-function 'arc-ask-options)
               (lambda (query) (setq options query))))
      (should-not (fboundp 'arc-scope))
      (let ((arc-vault-collections '("vault"))
            (arc-option-collections '("nix options" "hm options")))
        (emanix/arc-search-vault "vault")
        (emanix/arc-search-options "options")))
    (should (equal vault "vault"))
    (should (equal options "options"))))

(ert-deftest emanix-arc-owned-map-has-the-live-i-n-o-r-c-targets ()
  "The distro, not ARC internals, owns the documented command map."
  (dolist (binding '( ("i" . emanix/arc-search)
                      ("n" . emanix/arc-search-vault)
                      ("o" . emanix/arc-search-options)
                      ("R" . emanix/arc-reindex)
                      ("c" . emanix/arc-cancel-reindex)))
    (should (eq (lookup-key emanix/arc-command-map (kbd (car binding)))
                (cdr binding)))))

(ert-deftest emanix-arc-ewm-s-i-targets-retrieval-wrapper ()
  "The intercepted EWM key must point at the same distro-owned wrapper."
  (should
   (emanix-arc-test--with-config-text
    "(define-key ewm-mode-map (kbd \"s-i\") #'emanix/arc-search)")))

(provide 'emanix-arc-test)
;;; emanix-arc-test.el ends here
