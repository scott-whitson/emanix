;;; emanix-web.el --- Jinja2/HTML/CSS modes and gated formatting -*- lexical-binding: t; -*-

;; Jinja2 in this world is 134 plain `.html' files under `templates'
;; directories (FastAPI `Jinja2Templates' in pearl-platform, cd-audit and
;; distrosim).  There is not one `.j2' in the tree, so the file extension
;; cannot pick the major mode.  This file supplies the rule that can.
;;
;; It also gates format-on-save behind the repo's own declared config, and
;; the gate is the point: none of those repos declares any formatter config,
;; and `apheleia-global-mode' is already on.  The gate cannot be "leave
;; `apheleia-mode-alist' untouched" alone: apheleia ships its OWN non-nil
;; entries for `web-mode', `html-ts-mode', `css-ts-mode' and `css-mode' (all
;; prettier), and only `mhtml-mode' formats to nil.  Before this file, every
;; `.html' opened in `mhtml-mode' by the stock `auto-mode-alist' entry, so
;; the "leave it nil" mhtml behaviour was never tested against anything else.
;; Once this file routes `.html' to `web-mode'/`html-ts-mode' on path, that
;; accidental protection is gone, so `emanix-web--apheleia-skip-p' on
;; `apheleia-skip-functions' is the actual gate: it, not
;; `apheleia-mode-alist', decides whether a save formats at all.  The repo
;; owns its formatting — exactly as ruff + pyproject.toml already decides
;; Python line length per repo (pearl 88, distrosim 120) without this config
;; knowing either number.
;;
;; web-mode is soft-required.  A missing package must cost template-aware
;; editing and nothing else; on rafik this Emacs is the compositor.

(require 'treesit)
(require 'seq)
(require 'web-mode nil :no-error)
(require 'apheleia nil :no-error)
;; Loaded here, eagerly, for its SIDE EFFECT and not for any symbol.
;; `html-ts-mode.el' runs (add-to-list 'auto-mode-alist '("\\.html\\'" .
;; html-ts-mode)) at FILE LOAD time, and it is autoloaded — so without this
;; require it first loads the moment `emanix-web-html-mode' dispatches a
;; plain `.html' buffer to `html-ts-mode', and its entry lands AHEAD of the
;; one `emanix-web-setup' prepended.  Our dispatch is then never consulted
;; again: on a daemon, one plain `.html' visit permanently routes every
;; later `.html' — templates included — to `html-ts-mode'.  That is not
;; merely the wrong keymap; it sends templates to the PRETTIER half of the
;; gate, so a `[tool.djlint]'-only repo silently stops formatting and a repo
;; declaring both configs gets prettier run on Jinja2, joining `{% extends
;; %}' and `{% block %}' onto one line.  Requiring it up here means its
;; entry is already installed before ours is prepended, and ours stays in
;; front for the life of the session.
(require 'html-ts-mode nil :no-error)

(defgroup emanix-web nil
  "Major modes and gated format-on-save for Jinja2, HTML and CSS."
  :group 'tools)

(defcustom emanix-web-djlint-profile "jinja"
  "Template language passed to djlint's --profile.

Default suits Jinja2, which is every template tree here.  A tree using a
different template language sets this in .dir-locals.el rather than
patching the distro.

Note that a CLI --profile overrides one set in a repo's own djlint config.
That precedence is intended: the default is correct for every Jinja2 tree,
and a tree that needs otherwise says so locally."
  :type 'string :group 'emanix-web)

(defun emanix-web-template-file-p (file)
  "Non-nil when FILE sits under a directory named `templates'.

A pure function of the path: FILE need not exist.  That is what lets it be
called from `auto-mode-alist' before the buffer is fully set up, and tested
without touching disk.

The check is on path COMPONENTS, not a substring, so `templatesx/' does not
match.  Only the directory part is examined, so a plain file named
`templates' is correctly not a template."
  (and file
       (let ((dir (file-name-directory (expand-file-name file))))
         (and dir
              (member "templates"
                      (split-string (directory-file-name dir) "/" t))
              t))))

;; --- Is this repo asking to be formatted? -----------------------------
;;
;; The gate.  A repo that declares no formatter config is left alone, so
;; installing this feature reformats nothing and the decision to start
;; formatting a tree stays an explicit act in that tree.

(defconst emanix-web--prettier-config-files
  '(".prettierrc" ".prettierrc.json" ".prettierrc.yml" ".prettierrc.yaml"
    ".prettierrc.json5" ".prettierrc.js" ".prettierrc.cjs" ".prettierrc.mjs"
    ".prettierrc.toml" "prettier.config.js" "prettier.config.cjs"
    "prettier.config.mjs")
  "Config filenames prettier itself looks for.
Deliberately prettier's own list: the opt-in signal has to be something
prettier would also honour from the CLI, or editor and command line could
disagree about whether a tree is formatted at all.")

(defun emanix-web--locate-upward (dir predicate)
  "Return the first directory at or above DIR satisfying PREDICATE.

The walk examines directories from DIR upward and stops at whichever of
these comes first:

  - a directory containing a `.git' entry — the project root, which IS
    itself examined before the walk ends;
  - the home directory, which is NOT examined, nor is anything above it;
  - the filesystem root.

Returns nil when PREDICATE never matches.

Both stops exist for the same reason: a single stray ~/.djlintrc must not
silently opt in everything below it.  The `.git' stop alone does not
achieve that, because it only fires for files that are inside a repo at
all — a file with no enclosing repo would otherwise be walked all the way
to `/', and the weblorg trees under ~/docs/org/websites are exactly such
files.  The two rules do not collide: the home directory is not itself a
git repo here.

Written as an explicit walk rather than through `project-current' so the
predicates stay pure functions of a path, testable against a temporary
tree with no project.el state involved."
  (let ((dir (file-name-as-directory (expand-file-name dir)))
        (home (file-name-as-directory (expand-file-name "~")))
        (result nil)
        (done nil))
    (while (not done)
      (if (string= dir home)
          (setq done t)
        (when (funcall predicate dir)
          (setq result dir))
        (cond
         (result (setq done t))
         ((file-exists-p (expand-file-name ".git" dir)) (setq done t))
         (t
          (let ((parent (file-name-directory (directory-file-name dir))))
            (if (or (null parent) (string= parent dir))
                (setq done t)
              (setq dir parent)))))))
    result))

(defun emanix-web--pyproject-declares-djlint-p (dir)
  "Non-nil when DIR/pyproject.toml carries a [tool.djlint] section.
The section, not the file: every repo in play has a pyproject.toml, so the
file's mere presence says nothing about formatting."
  (let ((f (expand-file-name "pyproject.toml" dir)))
    (and (file-readable-p f)
         (with-temp-buffer
           (insert-file-contents f)
           (goto-char (point-min))
           (and (re-search-forward "^[ \t]*\\[tool\\.djlint\\]" nil t) t)))))

(defun emanix-web--package-json-declares-prettier-p (dir)
  "Non-nil when DIR/package.json carries a top-level `prettier' key.
Parsed, not grepped: \"prettier\" also appears as a dependency name, and a
devDependency is a build-tool choice, not a request to reformat on save.
Malformed JSON answers nil — this runs from a mode hook and must not
signal on a file someone is mid-edit.  So does JSON that parses but is
not an object (`5', `\"x\"', `[]', `true'): `json-parse-buffer' returns
those happily and `assq' would then signal `wrong-type-argument' out of
`find-file' and `after-save-hook' alike, which is why the `assq' sits
INSIDE the `ignore-errors' rather than after it."
  (let ((f (expand-file-name "package.json" dir)))
    (and (file-readable-p f)
         (with-temp-buffer
           (insert-file-contents f)
           (goto-char (point-min))
           (and (ignore-errors
                  (let ((json (json-parse-buffer :object-type 'alist)))
                    (assq 'prettier json)))
                t)))))

(defun emanix-web-djlint-configured-p (dir)
  "Non-nil when DIR or an ancestor declares djlint.
The ancestor walk is `emanix-web--locate-upward\='s: up to and including
a `.git\='-bearing project root, or up to but NOT including the home
directory, whichever comes first."
  (and dir
       (emanix-web--locate-upward
        dir
        (lambda (d)
          (or (file-exists-p (expand-file-name ".djlintrc" d))
              (emanix-web--pyproject-declares-djlint-p d))))
       t))

(defun emanix-web-prettier-configured-p (dir)
  "Non-nil when DIR or an ancestor declares prettier.
Same bounded ancestor walk as `emanix-web-djlint-configured-p\='."
  (and dir
       (emanix-web--locate-upward
        dir
        (lambda (d)
          (or (seq-some (lambda (name)
                          (file-exists-p (expand-file-name name d)))
                        emanix-web--prettier-config-files)
              (emanix-web--package-json-declares-prettier-p d))))
       t))

;; --- Major modes ------------------------------------------------------

(defun emanix-web-html-mode ()
  "Select a major mode for the `.html' file in this buffer.

Installed as the cdr of an `auto-mode-alist' entry, which Emacs calls with
no arguments.  Jinja2 templates and plain markup share the `.html'
extension here, so the choice is made on path.

Every branch activates a mode.  A fall-through would leave the buffer in
`fundamental-mode' with nothing to explain why, so the last clause is the
stock `mhtml-mode' rather than nothing."
  (cond
   ((and (emanix-web-template-file-p buffer-file-name)
         (fboundp 'web-mode))
    (web-mode))
   ((and (fboundp 'html-ts-mode) (treesit-language-available-p 'html))
    (html-ts-mode))
   (t (mhtml-mode))))

(defun emanix-web--set-djlint-formatter ()
  "Set djlint as this buffer's formatter.  Unconditional, by design.

Sets `apheleia-formatter' buffer-locally, and asks NOTHING about the
repo's config.  The two halves of this feature answer two different
questions, and this one only answers WHAT WITH: apheleia's own stock
`web-mode' entry in `apheleia-mode-alist' is plain prettier, which mangles
Jinja2's `{% %}', so a template that is going to be formatted at all must
be formatted with djlint.  WHETHER it is formatted at all is
`emanix-web--apheleia-skip-p' on `apheleia-skip-functions', and that is
the sole decider.

Asking the config question here too was a bug, not redundancy.  This runs
ONCE, in the mode hook; the skip function re-runs on EVERY save.  So for a
buffer already open when a `[tool.djlint]' or `.djlintrc' appeared, the
gate would open on the next save while this buffer-local was still nil —
and apheleia, finding no buffer-local, would fall through to its stock
`web-mode' entry and run PRETTIER on a Jinja2 template.  That is precisely
the mangling the gate exists to prevent, reached through the convenience
path the manual advertises (\"takes effect on the next save, with no need
to reopen the file\").  Setting the formatter unconditionally makes that
path safe: in an unconfigured repo the skip function still blocks the
save, so a buffer-local naming djlint costs nothing."
  (setq-local apheleia-formatter 'djlint))

(defun emanix-web--set-prettier-formatter ()
  "Set the right prettier parser as this buffer's formatter.
Unconditional for the same reason as `emanix-web--set-djlint-formatter';
see there for the division of labour with `emanix-web--apheleia-skip-p'."
  (setq-local apheleia-formatter
              (if (derived-mode-p 'css-base-mode)
                  'prettier-css
                'prettier-html)))

;; --- Format-on-save gate ------------------------------------------------
;;
;; Registered on `apheleia-skip-functions', not expressed through
;; `apheleia-mode-alist'.  Apheleia consults `apheleia-skip-functions'
;; before every format and skips the buffer if any of them return non-nil;
;; that is the only apheleia extension point this file uses, so
;; `apheleia-mode-alist' — and apheleia's own stock defaults in it — is
;; never touched.  This function is the SOLE decider of WHETHER to format;
;; the buffer-local `apheleia-formatter' the mode hooks set decides only
;; WHAT WITH (apheleia's stock `web-mode' entry is plain prettier, which
;; does not understand Jinja2's `{% %}', so the choice of formatter still
;; has to be ours even once the gate is open).  The split has to be exactly
;; there: this runs on every save, the hooks run once per buffer, so a hook
;; that also asked the config question would leave an already-open buffer
;; with a nil formatter the moment config appeared under it — and apheleia
;; would then fall through to prettier on a Jinja2 template.

(defun emanix-web--apheleia-skip-p ()
  "Non-nil when apheleia should skip formatting the current buffer.

Skips only when BOTH hold: the buffer is in a mode this file dispatches
to (`web-mode', `html-ts-mode', `mhtml-mode', or a `css-base-mode'
derivative), and the repo has declared no matching formatter config —
djlint for `web-mode' templates, prettier for the rest.  A buffer with no
`buffer-file-name' — nothing on disk to look an ancestor config up from —
answers nil rather than erroring, since `and' short-circuits before
`file-name-directory' ever sees a nil argument."
  (and buffer-file-name
       (derived-mode-p 'web-mode 'html-ts-mode 'mhtml-mode 'css-base-mode)
       (let ((dir (file-name-directory buffer-file-name)))
         (if (derived-mode-p 'web-mode)
             (not (emanix-web-djlint-configured-p dir))
           (not (emanix-web-prettier-configured-p dir))))))

(defun emanix-web-setup ()
  "Install the mode rules and the gated format-on-save hooks.
Idempotent: `add-to-list' and `add-hook' both no-op on a repeat, so this
is safe to re-run after `M-x load-file' on a live daemon."
  ;; web-mode resolves its engine during mode initialisation, so setting
  ;; `web-mode-engine' afterwards is too late. `web-mode-engines-alist' is
  ;; web-mode's own mechanism: the cdr is a regexp matched against the file
  ;; path. django is the engine name for the Jinja2 family.
  (when (boundp 'web-mode-engines-alist)
    (add-to-list 'web-mode-engines-alist '("django" . "/templates/")))
  ;; Prepend, so this beats both the stock `.html' -> mhtml-mode entry and
  ;; the `.html' -> html-ts-mode one that `html-ts-mode.el' installs when it
  ;; loads (which the eager require at the top of this file has already
  ;; forced to happen by now — see the comment there; without it that entry
  ;; would arrive LATER and land in front of this one). Both are
  ;; deliberately left in place: if this file ever fails to load, .html
  ;; still opens in a working mode.
  (add-to-list 'auto-mode-alist '("\\.html?\\'" . emanix-web-html-mode))
  (when (treesit-language-available-p 'css)
    (add-to-list 'major-mode-remap-alist '(css-mode . css-ts-mode)))
  ;; The actual gate — see the comment above `emanix-web--apheleia-skip-p'.
  ;; Soft-required: apheleia is expected everywhere in this distro
  ;; (config.el requires it unconditionally), but a unit test loading only
  ;; this file, or some future Emacs without it, must not error here.
  (when (boundp 'apheleia-skip-functions)
    (add-hook 'apheleia-skip-functions #'emanix-web--apheleia-skip-p))
  ;; One hook covers both CSS modes: `css-mode' and `css-ts-mode' both
  ;; derive from `css-base-mode' (verified 2026-08-20), and a derived mode
  ;; runs its parent's hooks.
  (add-hook 'web-mode-hook #'emanix-web--set-djlint-formatter)
  (add-hook 'html-ts-mode-hook #'emanix-web--set-prettier-formatter)
  (add-hook 'mhtml-mode-hook #'emanix-web--set-prettier-formatter)
  (add-hook 'css-base-mode-hook #'emanix-web--set-prettier-formatter))

;; djlint is the one formatter apheleia does not ship. prettier-html and
;; prettier-css are built in and need no definition; both route through
;; apheleia's bundled apheleia-npx script, which execs from $PATH when no
;; package.json sits above the file — so the Nix-installed prettier runs and
;; no node_modules is required.
;;
;; Three things here are load-bearing and must not be "tidied":
;;
;;   "-"                     djlint's read-from-stdin argument. apheleia's
;;                           default, absent input/inplace/file, is to write
;;                           the buffer to stdin and splice back stdout --
;;                           the same deal the bare ("nixpkgs-fmt") entry in
;;                           config.el relies on. Both halves must agree.
;;   emanix-web-djlint-profile   A BARE SYMBOL, not a string. apheleia
;;                           evaluates any list element that is not a string
;;                           and not one of its special forms (npx, input,
;;                           output, inplace, file, filepath, scratch), so
;;                           this splices in the defcustom's value at
;;                           invocation. Quoting it would hardcode the
;;                           profile and strip the .dir-locals.el override.
;;   "--quiet"               Suppresses the diff djlint prints by default,
;;                           which would otherwise land on stdout and be
;;                           spliced into the buffer as if it were content.
(with-eval-after-load 'apheleia
  (setf (alist-get 'djlint apheleia-formatters)
        '("djlint" "-" "--reformat"
          "--profile" emanix-web-djlint-profile
          "--quiet")))

(provide 'emanix-web)
;;; emanix-web.el ends here
