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

;;; Apply steps.

(defvar emanix-theme-test--calls nil
  "Calls recorded by `emanix-theme-test--recording'.")

(defmacro emanix-theme-test--recording (&rest body)
  "Run BODY with `call-process' and `make-symbolic-link' stubbed.
Returns the calls made, in order: (:process PROGRAM ARGS...) and
(:link SOURCE TARGET). The value is RETURNED rather than bound into a
caller-named variable, so assertions live outside the stubs -- a
`should' that runs while `call-process' is stubbed reports failures
through a crippled environment."
  (declare (indent 0))
  `(let ((emanix-theme-test--calls nil))
     (cl-letf (((symbol-function 'call-process)
                (lambda (program &optional _in _buf _disp &rest args)
                  (push (cons :process (cons program args))
                        emanix-theme-test--calls)
                  0))
               ((symbol-function 'make-symbolic-link)
                (lambda (source target &optional _ok)
                  (push (list :link source target) emanix-theme-test--calls)
                  nil)))
       ,@body)
     (nreverse emanix-theme-test--calls)))

(ert-deftest emanix-theme-apply-links-symlinks-every-planned-pair ()
  (emanix-theme-test--with-tree
    (let* ((plan (emanix-theme--plan "duskthorn"))
           (failures nil)
           (calls (emanix-theme-test--recording
                    (setq failures (emanix-theme--apply-links plan))))
           (links (seq-filter (lambda (c) (eq (car c) :link)) calls)))
      (should-not failures)
      (should (= (length links) (length (plist-get plan :links)))))))

(ert-deftest emanix-theme-apply-links-reports-a-failure-without-signalling ()
  "One unwritable target must not cost the other links, or the Emacs theme."
  (emanix-theme-test--with-tree
    (let ((plan (emanix-theme--plan "duskthorn"))
          (n 0))
      (cl-letf (((symbol-function 'make-symbolic-link)
                 (lambda (_s _t &optional _ok)
                   (setq n (1+ n))
                   (when (= n 1) (error "read-only file system")))))
        (let ((failures (emanix-theme--apply-links plan)))
          (should (= 1 (length failures)))
          ;; The remaining links were still attempted.
          (should (= n (length (plist-get plan :links)))))))))

(ert-deftest emanix-theme-apply-gtk-sets-each-key-through-gsettings ()
  (emanix-theme-test--with-tree
    (let* ((plan (emanix-theme--plan "duskthorn"))
           (calls (emanix-theme-test--recording (emanix-theme--apply-gtk plan)))
           (cmds (mapcar #'cdr (seq-filter (lambda (c) (eq (car c) :process)) calls))))
      (should (= 2 (length cmds)))
      (should (cl-every (lambda (c) (equal (car c) "gsettings")) cmds))
      (should (seq-find (lambda (c) (member "color-scheme" c)) cmds))
      (should (seq-find (lambda (c) (member "prefer-dark" c)) cmds)))))

(ert-deftest emanix-theme-apply-gtk-tolerates-a-missing-gsettings ()
  "Headless hosts have no GTK to theme; the switch must continue anyway.
Emacs cannot see `emanix.gui' -- see the 2026-09-11 spec -- so the step
runs everywhere and its failure is reported, not raised."
  (emanix-theme-test--with-tree
    (let ((plan (emanix-theme--plan "duskthorn")))
      (cl-letf (((symbol-function 'call-process)
                 (lambda (&rest _) (error "No such file or directory, gsettings"))))
        (let ((failures (emanix-theme--apply-gtk plan)))
          (should (= 2 (length failures)))
          (should (cl-every #'stringp failures)))))))

(ert-deftest emanix-theme-write-state-writes-both-markers ()
  (emanix-theme-test--with-tree
    (let ((plan (emanix-theme--plan "duskthorn")))
      (should-not (emanix-theme--write-state plan))
      (should (equal "duskthorn" (emanix-theme--read (emanix-theme--state-file))))
      (should (equal "duskthorn" (emanix-theme--read (emanix-theme--last-file "dark"))))
      (should-not (file-exists-p (emanix-theme--last-file "light"))))))

(ert-deftest emanix-theme-reload-apps-signals-ghostty ()
  (let ((calls (emanix-theme-test--recording (emanix-theme--reload-apps))))
    (should (seq-find (lambda (c) (and (eq (car c) :process)
                                       (equal (cadr c) "pkill")))
                      calls))))

;;; Orchestration.

(ert-deftest emanix-theme-set-rejects-an-unknown-name-without-touching-anything ()
  "A bad name from a shell argument must not disable the working theme."
  (emanix-theme-test--with-tree
    (let* (result
           (calls (emanix-theme-test--recording
                    (setq result (emanix/theme-set "nosuchtheme")))))
      (should-not result)
      (should-not calls)
      (should-not (file-exists-p (emanix-theme--state-file))))))

(ert-deftest emanix-theme-set-runs-state-links-gtk-and-reload ()
  (emanix-theme-test--with-tree
    (let ((calls (cl-letf (((symbol-function 'emanix-theme--apply-emacs)
                            (lambda (_) 'catppuccin)))
                   (emanix-theme-test--recording
                     (emanix/theme-set "duskthorn")))))
      (should (equal "duskthorn" (emanix-theme--read (emanix-theme--state-file))))
      (should (seq-find (lambda (c) (eq (car c) :link)) calls))
      (should (seq-find (lambda (c) (and (eq (car c) :process)
                                         (equal (cadr c) "gsettings")))
                        calls))
      (should (seq-find (lambda (c) (and (eq (car c) :process)
                                         (equal (cadr c) "pkill")))
                        calls)))))

(ert-deftest emanix-theme-set-calls-the-consumer-hook-with-the-plan ()
  (emanix-theme-test--with-tree
    (let* ((seen nil)
           (emanix/theme-apply-functions (list (lambda (plan) (setq seen plan)))))
      (cl-letf (((symbol-function 'emanix-theme--apply-emacs) (lambda (_) 'catppuccin)))
        (emanix-theme-test--recording
          (emanix/theme-set "duskthorn")))
      (should (equal (plist-get seen :name) "duskthorn"))
      (should (equal (plist-get seen :variant) "dark")))))

(ert-deftest emanix-theme-set-survives-a-signalling-hook-function ()
  "A consumer's broken registration must not stop the ones after it."
  (emanix-theme-test--with-tree
    (let* ((ran nil)
           (emanix/theme-apply-functions
            (list (lambda (_plan) (error "boom"))
                  (lambda (_plan) (setq ran t)))))
      (let (result)
        (cl-letf (((symbol-function 'emanix-theme--apply-emacs)
                   (lambda (_) 'catppuccin)))
          (emanix-theme-test--recording
            (setq result (emanix/theme-set "duskthorn"))))
        (should (eq 'catppuccin result)))
      (should ran))))

(ert-deftest emanix-theme-set-returns-the-theme-even-when-side-effects-fail ()
  "The colours are the part the user sees; a failed symlink must not mask them."
  (emanix-theme-test--with-tree
    (let (result)
      (cl-letf (((symbol-function 'emanix-theme--apply-emacs) (lambda (_) 'catppuccin))
                ((symbol-function 'make-symbolic-link)
                 (lambda (&rest _) (error "read-only file system")))
                ((symbol-function 'call-process)
                 (lambda (&rest _) (error "not found"))))
        (setq result (emanix/theme-set "duskthorn")))
      (should (eq 'catppuccin result)))))

(ert-deftest emanix-theme-set-returns-nil-when-the-emacs-theme-fails-while-side-effects-still-run ()
  "A failed load must not be masked as success, and must not skip the rest."
  (emanix-theme-test--with-tree
    (let (result)
      (let ((calls (cl-letf (((symbol-function 'emanix-theme--apply-emacs) (lambda (_) nil)))
                     (emanix-theme-test--recording
                       (setq result (emanix/theme-set "duskthorn"))))))
        (should-not result)
        (should (equal "duskthorn" (emanix-theme--read (emanix-theme--state-file))))
        (should (seq-find (lambda (c) (eq (car c) :link)) calls))))))

(ert-deftest emanix-theme-apply-functions-defaults-empty ()
  "The distribution registers none of its own; this seam is the consumer's."
  (should (null (default-value 'emanix/theme-apply-functions))))

;;; The toggle.

(ert-deftest emanix-theme-toggle-uses-the-counterpart-marker ()
  (emanix-theme-test--with-tree
    (make-directory emanix/theme-state-dir t)
    (write-region "duskthorn\n" nil (emanix-theme--state-file))
    (write-region "dawnthorn\n" nil (emanix-theme--last-file "light"))
    (let (switched)
      (cl-letf (((symbol-function 'emanix/theme-set)
                 (lambda (name) (setq switched name) 'stub)))
        (should (eq 'stub (emanix/theme-toggle))))
      (should (equal "dawnthorn" switched)))))

(ert-deftest emanix-theme-toggle-falls-back-to-any-opposite-variant ()
  "First toggle on a fresh machine has no counterpart marker yet."
  (emanix-theme-test--with-tree
    (make-directory emanix/theme-state-dir t)
    (write-region "dawnthorn\n" nil (emanix-theme--state-file))
    (let (switched)
      (cl-letf (((symbol-function 'emanix/theme-set)
                 (lambda (name) (setq switched name) 'stub)))
        (emanix/theme-toggle))
      (should (equal "duskthorn" switched)))))

(ert-deftest emanix-theme-toggle-ignores-a-stale-counterpart-marker ()
  "A marker naming a theme that has since been deleted must not be used."
  (emanix-theme-test--with-tree
    (make-directory emanix/theme-state-dir t)
    (write-region "duskthorn\n" nil (emanix-theme--state-file))
    (write-region "deletedtheme\n" nil (emanix-theme--last-file "light"))
    (let (switched)
      (cl-letf (((symbol-function 'emanix/theme-set)
                 (lambda (name) (setq switched name) 'stub)))
        (emanix/theme-toggle))
      (should (equal "dawnthorn" switched)))))

(ert-deftest emanix-theme-toggle-returns-nil-when-there-is-no-counterpart ()
  (emanix-theme-test--with-tree
    (delete-directory (expand-file-name "dawnthorn" emanix-theme--themes-dir) t)
    (make-directory emanix/theme-state-dir t)
    (write-region "duskthorn\n" nil (emanix-theme--state-file))
    (should-not (emanix/theme-toggle))))
