;;; scott-quarterly.el --- Quarterly tracker notes -*- lexical-binding: t; -*-

;;; Commentary:
;; The quarterly tracker is the "main page" tying together a quarter's work.
;; Two scopes share one command: `personal' notes live at the org root,
;; `work' notes under work/Quarterly/.  Extracted from init.el 2026-08-06.

;;; Code:

(require 'org-id)

(defvar org-directory)

(defun scott-quarterly-name (&optional time)
  "Return the quarter name for TIME in YYYY-QN format.
TIME defaults to now."
  (let* ((time (or time (current-time)))
         (month (string-to-number (format-time-string "%m" time)))
         (quarter (1+ (/ (1- month) 3))))
    (format "%s-Q%d" (format-time-string "%Y" time) quarter)))

(defun scott-quarterly--prev-name (name)
  "Return the quarter name preceding NAME, wrapping across the year."
  (let ((year (string-to-number (substring name 0 4)))
        (quarter (string-to-number (substring name 6 7))))
    (if (= quarter 1)
        (format "%d-Q4" (1- year))
      (format "%d-Q%d" year (1- quarter)))))

(defun scott-quarterly--dir (scope)
  "Return the quarterly directory for SCOPE (`personal' or `work')."
  (pcase scope
    ('work (expand-file-name "work/Quarterly" org-directory))
    ('personal (expand-file-name "Quarterly" org-directory))
    (_ (error "Unknown quarterly scope: %S" scope))))

(defun scott-quarterly--file (scope &optional name)
  "Return the note path for quarter NAME in SCOPE.
NAME defaults to the current quarter.  Work notes have exactly one
location.  Personal notes keep their historical resolution: the org root
holds the current quarter, Quarterly/ holds archived ones."
  (let ((name (or name (scott-quarterly-name))))
    (pcase scope
      ('work (expand-file-name (concat name ".org") (scott-quarterly--dir 'work)))
      ('personal
       (let ((root (expand-file-name (concat name ".org") org-directory))
             (archived (expand-file-name (concat name ".org")
                                         (scott-quarterly--dir 'personal))))
         (cond ((file-exists-p root) root)
               ((file-exists-p archived) archived)
               (t root))))
      (_ (error "Unknown quarterly scope: %S" scope)))))

(defun scott-quarterly--scope-available-p (scope)
  "Return non-nil when SCOPE's note tree exists on this machine.
This asks whether the tree is here at all, not whether this quarter's
note has been written yet — otherwise the first `scott-quarterly-open'
of a new quarter would resolve to the wrong scope."
  (pcase scope
    ('work (file-directory-p (scott-quarterly--dir 'work)))
    ('personal
     (or (file-directory-p (scott-quarterly--dir 'personal))
         (and (file-directory-p org-directory)
              (consp (directory-files
                      org-directory nil "\\`[0-9]\\{4\\}-Q[1-4]\\.org\\'" t)))))
    (_ (error "Unknown quarterly scope: %S" scope))))

(defun scott-quarterly--default-scope ()
  "Return `personal' when that tree is present here, otherwise `work'."
  (if (scott-quarterly--scope-available-p 'personal) 'personal 'work))

(defun scott-quarterly-open ()
  "Open the current-quarter tracker note.
If the note does not exist on this machine, do NOT silently create and
save an empty template — that races with Syncthing: on a freshly-synced
box the empty file can win the conflict and quarantine the real,
populated note (happened 2026-07-16 with 2026-Q3). Instead confirm
first, so an unsynced note gets a chance to arrive rather than be
clobbered; only a genuinely new quarter gets a fresh template."
  (interactive)
  (let* ((name (scott-quarterly-name))
         (file (scott-quarterly--file (scott-quarterly--default-scope) name)))
    (if (file-exists-p file)
        (find-file file)
      (if (yes-or-no-p
           (format "No %s note here — create it? (choose no if it may just be unsynced) "
                   name))
          (progn
            (find-file file)
            (when (zerop (buffer-size))
              (insert ":PROPERTIES:\n:ID:       " (org-id-new) "\n:END:\n")
              (insert "#+title: " name "\n\n")
              (insert "* Goals\n\n")
              (insert "* Active work\n\n")
              (insert "* Notes\n\n")
              (save-buffer)))
        (message
         "Not creating %s — waiting for sync. Re-run C-c q once it arrives."
         name)))))

(provide 'scott-quarterly)
;;; scott-quarterly.el ends here
