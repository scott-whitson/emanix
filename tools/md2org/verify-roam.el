;;; verify-roam.el --- gate 2: every converted note is a registered org-roam node
;; Run: emacs --batch -l tools/md2org/verify-roam.el
;; Exits non-zero and names the missing IDs if any uuid from the conversion
;; map is absent from the org-roam DB after a full sync.
(require 'org-roam)
(setq org-roam-directory (expand-file-name "~/docs/org"))
(org-roam-db-sync)
(let* ((map-file (expand-file-name "~/docs/org/work/.conversion-map.tsv"))
       (lines (split-string (with-temp-buffer
                              (insert-file-contents map-file)
                              (buffer-string))
                            "\n" t))
       (missing '()))
  (dolist (line lines)
    (let ((uuid (nth 1 (split-string line "\t"))))
      (unless (org-roam-db-query
               [:select id :from nodes :where (= id $s1)] uuid)
        (push uuid missing))))
  (if missing
      (progn (message "MISSING %d IDs: %S" (length missing) missing)
             (kill-emacs 1))
    (message "ALL-REGISTERED: %d nodes" (length lines))))
