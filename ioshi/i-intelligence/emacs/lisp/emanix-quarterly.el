;;; emanix-quarterly.el --- Quarterly tracker notes -*- lexical-binding: t; -*-

;;; Commentary:
;; The quarterly tracker is the "main page" tying together a quarter's work.
;; Two scopes share one command: `personal' notes live at the org root,
;; `work' notes under work/Quarterly/.  Extracted from init.el 2026-08-06.

;;; Code:

(require 'org-id)

(defvar org-directory)

(defun emanix-quarterly--name (&optional time)
  "Return the quarter name for TIME in YYYY-QN format.
TIME defaults to now."
  (let* ((time (or time (current-time)))
         (month (string-to-number (format-time-string "%m" time)))
         (quarter (1+ (/ (1- month) 3))))
    (format "%s-Q%d" (format-time-string "%Y" time) quarter)))

(defun emanix-quarterly--prev-name (name)
  "Return the quarter name preceding NAME, wrapping across the year."
  (let ((year (string-to-number (substring name 0 4)))
        (quarter (string-to-number (substring name 6 7))))
    (if (= quarter 1)
        (format "%d-Q4" (1- year))
      (format "%d-Q%d" year (1- quarter)))))

(defun emanix-quarterly--dir (scope)
  "Return the quarterly directory for SCOPE (`personal' or `work')."
  (pcase scope
    ('work (expand-file-name "work/Quarterly" org-directory))
    ('personal (expand-file-name "Quarterly" org-directory))
    (_ (error "Unknown quarterly scope: %S" scope))))

(defun emanix-quarterly--file (scope &optional name)
  "Return the note path for quarter NAME in SCOPE.
NAME defaults to the current quarter.  Work notes have exactly one
location.  Personal notes keep their historical resolution: the org root
holds the current quarter, Quarterly/ holds archived ones."
  (let ((name (or name (emanix-quarterly--name))))
    (pcase scope
      ('work (expand-file-name (concat name ".org") (emanix-quarterly--dir 'work)))
      ('personal
       (let ((root (expand-file-name (concat name ".org") org-directory))
             (archived (expand-file-name (concat name ".org")
                                         (emanix-quarterly--dir 'personal))))
         (cond ((file-exists-p root) root)
               ((file-exists-p archived) archived)
               (t root))))
      (_ (error "Unknown quarterly scope: %S" scope)))))

(defun emanix-quarterly--scope-available-p (scope)
  "Return non-nil when SCOPE's note tree exists on this machine.
This asks whether the tree is here at all, not whether this quarter's
note has been written yet — otherwise the first `emanix-quarterly-open'
of a new quarter would resolve to the wrong scope."
  (pcase scope
    ('work (file-directory-p (emanix-quarterly--dir 'work)))
    ('personal
     (or (file-directory-p (emanix-quarterly--dir 'personal))
         (and (file-directory-p org-directory)
              (consp (directory-files
                      org-directory nil "\\`[0-9]\\{4\\}-Q[1-4]\\.org\\'" t)))))
    (_ (error "Unknown quarterly scope: %S" scope))))

(defun emanix-quarterly--default-scope ()
  "Return `personal' when that tree is present here, otherwise `work'."
  (if (emanix-quarterly--scope-available-p 'personal) 'personal 'work))

(defconst emanix-quarterly--sections
  '("Rock" "Top of Mind" "New This Quarter" "Workspace")
  "Top-level headings stamped into a new quarter note.
These are the sections past quarters converged on: Rock is the one big
thing, Top of Mind holds `[[id:]]' links to client and initiative nodes
with Context/P1/P2/Parking lot beneath each, New This Quarter is the
mid-quarter inbox, Workspace is tooling and environment work.")

(defun emanix-quarterly--file-id (file)
  "Return the file-level :ID: property of FILE, or nil if it has none.
Only the first 4096 bytes are read: the file-level property drawer is the
first thing in an org file, and this is called on notes that can be long.
The search also stops at the first heading — with `org-adapt-indentation'
nil (the default since Org 9.5) a subheading's property drawer sits at
column 0 too, so an unbounded search would return a heading's ID and the
back-link would land mid-file instead of at the note."
  (when (and file (file-readable-p file))
    (with-temp-buffer
      (insert-file-contents file nil 0 4096)
      (goto-char (point-min))
      (let ((limit (save-excursion
                     (if (re-search-forward "^\\*+ " nil t)
                         (match-beginning 0)
                       (point-max)))))
        (when (re-search-forward "^:ID:[ \t]+\\([^ \t\n]+\\)" limit t)
          (match-string 1))))))

(defun emanix-quarterly--template (scope name &optional prev-id prev-name)
  "Return the buffer text for a new quarter NAME note in SCOPE.
When PREV-ID and PREV-NAME are given, append a link back to that note."
  (concat ":PROPERTIES:\n:ID:       " (org-id-new) "\n:END:\n"
          "#+title: " name (if (eq scope 'work) " (Work)" "") "\n\n"
          (mapconcat (lambda (section) (format "* %s\n\n" section))
                     emanix-quarterly--sections "")
          (when (and prev-id prev-name)
            (format "[[id:%s][%s]]\n" prev-id prev-name))))

(defun emanix-quarterly--create (scope name file)
  "Create and visit the quarter NAME note for SCOPE at FILE."
  (make-directory (file-name-directory file) t)
  (let* ((prev-name (emanix-quarterly--prev-name name))
         (prev-file (emanix-quarterly--file scope prev-name))
         (prev-id (and (file-exists-p prev-file)
                       (emanix-quarterly--file-id prev-file))))
    (find-file file)
    (when (zerop (buffer-size))
      (insert (emanix-quarterly--template scope name prev-id prev-name))
      (save-buffer))))

(defun emanix-quarterly-open (&optional arg)
  "Open the current quarter's tracker note.

Scope is chosen by what is on this machine: personal when that tree is
present, work otherwise.  With prefix ARG, always open the work tracker
— that is how the work note is reached on a machine that has both.

If the note does not exist here, do NOT silently create and save an
empty template — that races with Syncthing: on a freshly-synced box the
empty file can win the conflict and quarantine the real, populated note
\(happened 2026-07-16 with 2026-Q3).  Confirm first, so an unsynced note
gets a chance to arrive rather than be clobbered; only a genuinely new
quarter gets a fresh template."
  (interactive "P")
  (let* ((scope (if arg 'work (emanix-quarterly--default-scope)))
         (name (emanix-quarterly--name))
         (file (emanix-quarterly--file scope name)))
    (if (file-exists-p file)
        (find-file file)
      (if (yes-or-no-p
           (format "No %s (%s) note here — create it? (choose no if it may just be unsynced) "
                   name scope))
          (emanix-quarterly--create scope name file)
        (message
         "Not creating %s — waiting for sync. Re-run C-c q once it arrives."
         name)))))

(provide 'emanix-quarterly)
;;; emanix-quarterly.el ends here
