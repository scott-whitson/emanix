;;; emanix-theme-test.el --- ERT tests for the theme switch -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
(require 'emanix-theme)

;;; Fixtures.
;;
;; A theme tree exactly as lib/theme-tree.nix produces one. Built in a temp
;; directory: these tests must never read the real $EMANIX_THEMES_DIR nor write
;; the real ~/.config/dotfiles.

(defvar emanix-theme-test--dirs nil)

(defun emanix-theme-test--make-tree ()
  "Return a temp themes dir holding `duskthorn' (dark) and `dawnthorn' (light)."
  (let ((root (make-temp-file "emanix-theme-test-themes" t)))
    (push root emanix-theme-test--dirs)
    (dolist (spec '(("duskthorn" "dark"  "catppuccin")
                    ("dawnthorn" "light" "modus-operandi")))
      (cl-destructuring-bind (name variant emacs-theme) spec
        (let ((dir (expand-file-name name root)))
          (make-directory dir)
          (write-region (concat variant "\n") nil (expand-file-name "variant" dir))
          (write-region (concat emacs-theme "\n") nil
                        (expand-file-name "emacs-theme" dir))
          (write-region "btop\n" nil (expand-file-name "btop.theme" dir))
          (write-region "swaylock\n" nil (expand-file-name "swaylock.conf" dir))
          (write-region (format "COLOR_SCHEME=prefer-%s\nGTK_THEME=Adwaita%s\n"
                                variant (if (equal variant "dark") ":dark" ""))
                        nil (expand-file-name "gtk.conf" dir)))))
    root))

(defun emanix-theme-test--make-home ()
  "Return a temp HOME holding the ghostty and zellij sources a plan links.
Both live outside the theme tree -- ghostty renders per-palette files
into its own config dir, and zellij's two definitions are written by
zellij.nix -- so a fixture that omits them makes every link assertion
depend on whether the REAL home happens to have them."
  (let ((home (make-temp-file "emanix-theme-test-home" t)))
    (push home emanix-theme-test--dirs)
    (dolist (rel '(".config/ghostty/themes/duskthorn.conf"
                   ".config/ghostty/themes/dawnthorn.conf"
                   ".local/share/emanix/zellij-themes/available/emanix-dark.kdl"
                   ".local/share/emanix/zellij-themes/available/emanix-light.kdl"))
      (let ((path (expand-file-name rel home)))
        (make-directory (file-name-directory path) t)
        (write-region "fixture\n" nil path)))
    home))

(defmacro emanix-theme-test--with-tree (&rest body)
  "Run BODY with a fixture theme tree, temp HOME, and throwaway state dir.
HOME is bound through `process-environment' because the link plan uses
`~'-relative paths, and `expand-file-name' resolves those through
`getenv' -- so without this the tests would read and assert against the
real home directory."
  (declare (indent 0))
  `(let* ((emanix-theme--themes-dir (emanix-theme-test--make-tree))
          (emanix/theme-state-dir (make-temp-file "emanix-theme-test-state" t))
          (process-environment
           (cons (concat "HOME=" (emanix-theme-test--make-home))
                 process-environment)))
     (push emanix/theme-state-dir emanix-theme-test--dirs)
     ,@body))

;;; The state directory.

(ert-deftest emanix-theme-state-dir-defaults-to-the-dotfiles-path ()
  "The default is unchanged by this refactor; only its shape is."
  (should (equal (default-value 'emanix/theme-state-dir) "~/.config/dotfiles")))

(ert-deftest emanix-theme-state-file-resolves-under-the-state-dir ()
  (let ((emanix/theme-state-dir "/tmp/whatever"))
    (should (equal (emanix-theme--state-file)
                   (expand-file-name "active-theme" "/tmp/whatever")))
    (should (equal (emanix-theme--last-file "dark")
                   (expand-file-name "last-dark" "/tmp/whatever")))))

;;; The planner.

(ert-deftest emanix-theme-plan-reads-variant-and-emacs-theme ()
  (emanix-theme-test--with-tree
    (let ((plan (emanix-theme--plan "duskthorn")))
      (should (equal (plist-get plan :name) "duskthorn"))
      (should (equal (plist-get plan :variant) "dark"))
      (should (eq (plist-get plan :emacs-theme) 'catppuccin)))))

(ert-deftest emanix-theme-plan-rejects-an-unknown-theme ()
  "No directory, no plan -- and nothing written."
  (emanix-theme-test--with-tree
    (should-not (emanix-theme--plan "nosuchtheme"))))

(ert-deftest emanix-theme-plan-rejects-a-theme-with-no-variant ()
  "A half-written theme directory must not produce a plan."
  (emanix-theme-test--with-tree
    (make-directory (expand-file-name "halfbaked" emanix-theme--themes-dir))
    (should-not (emanix-theme--plan "halfbaked"))))

(ert-deftest emanix-theme-plan-links-btop-and-swaylock-from-the-theme-dir ()
  (emanix-theme-test--with-tree
    (let* ((plan (emanix-theme--plan "duskthorn"))
           (links (plist-get plan :links))
           (targets (mapcar #'cdr links)))
      (should (member (expand-file-name "~/.config/btop/themes/active.theme") targets))
      (should (member (expand-file-name "~/.config/swaylock/config") targets))
      ;; Sources come from the theme tree, not from a second copy somewhere.
      (should (equal (car (rassoc (expand-file-name "~/.config/btop/themes/active.theme") links))
                     (expand-file-name "btop.theme" (plist-get plan :dir)))))))

(ert-deftest emanix-theme-plan-links-zellij-by-variant-not-by-name ()
  "Both zellij theme definitions are named `emanix'; the variant picks the file."
  (emanix-theme-test--with-tree
    (let* ((plan (emanix-theme--plan "dawnthorn"))
           (links (plist-get plan :links))
           (zellij (seq-find (lambda (l) (string-match-p "zellij" (cdr l))) links)))
      (should zellij)
      (should (string-match-p "emanix-light\\.kdl\\'" (car zellij))))))

(ert-deftest emanix-theme-plan-omits-links-whose-source-is-absent ()
  "link_if_present, in plan form.
ghostty renders per-palette files only where `emanix.ghostty.enable' is
set, and zellij's tree exists only where `emanix.zellij.enable' is --
so a plan must not name a source that is not there."
  (emanix-theme-test--with-tree
    (let ((before (length (plist-get (emanix-theme--plan "duskthorn") :links))))
      (delete-file (expand-file-name "~/.config/ghostty/themes/duskthorn.conf"))
      (let* ((plan (emanix-theme--plan "duskthorn"))
             (links (plist-get plan :links)))
        (should (= (1- before) (length links)))
        (should (cl-every (lambda (l) (file-exists-p (car l))) links))))))

(ert-deftest emanix-theme-plan-parses-gtk-conf ()
  (emanix-theme-test--with-tree
    (let ((gtk (plist-get (emanix-theme--plan "duskthorn") :gtk)))
      (should (equal (alist-get "COLOR_SCHEME" gtk nil nil #'equal) "prefer-dark"))
      (should (equal (alist-get "GTK_THEME" gtk nil nil #'equal) "Adwaita:dark")))))

(ert-deftest emanix-theme-plan-writes-nothing ()
  "The planner is the half that must be safe to call on a bad name."
  (emanix-theme-test--with-tree
    (emanix-theme--plan "duskthorn")
    (emanix-theme--plan "nosuchtheme")
    (should-not (file-exists-p (emanix-theme--state-file)))))
