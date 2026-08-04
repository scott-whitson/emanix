;;; scott-launcher.el --- XDG app launcher, EWM-s-d-style -*- lexical-binding: t; -*-

;; The launcher half of EWM's s-d, portable to non-EWM machines (whistle).
;; completing-read over XDG desktop entries, launch the pick. Under EWM the
;; new window becomes a buffer as usual; under WSLg it opens as its own
;; Wayland window — the launch UX is identical either way.

(defun scott/launcher--entries ()
  "Alist of (NAME . EXEC) from XDG desktop files visible to this profile."
  (let (entries)
    (dolist (dir (list (expand-file-name "~/.local/share/applications")
                       (concat "/etc/profiles/per-user/" (user-login-name)
                               "/share/applications")
                       (expand-file-name "~/.nix-profile/share/applications")
                       "/run/current-system/sw/share/applications"))
      (when (file-directory-p dir)
        (dolist (f (directory-files dir t "\\.desktop\\'"))
          (with-temp-buffer
            (insert-file-contents f)
            (let* ((name (and (re-search-forward "^Name=\\(.+\\)$" nil t)
                              (match-string 1)))
                   (exec (progn (goto-char (point-min))
                                (and (re-search-forward "^Exec=\\(.+\\)$" nil t)
                                     (match-string 1))))
                   (hidden (progn (goto-char (point-min))
                                  (re-search-forward "^NoDisplay=true" nil t))))
              (when (and name exec (not hidden) (not (assoc name entries)))
                (push (cons name exec) entries)))))))
    (nreverse entries)))

(defun scott/launch-app (name)
  "Launch the desktop application NAME (the s-d launcher, sans EWM)."
  (interactive
   (list (completing-read "Launch: "
                          (mapcar #'car (scott/launcher--entries))
                          nil t)))
  (let* ((exec (cdr (assoc name (scott/launcher--entries))))
         ;; Drop desktop-spec field codes (%u, %F, ...) — we pass no files.
         (cmd (string-trim (replace-regexp-in-string "%[a-zA-Z]" "" exec)))
         (process-environment
          (let ((env (copy-sequence process-environment))
                (xrd (or (getenv "XDG_RUNTIME_DIR")
                         (format "/run/user/%d" (user-uid)))))
            ;; WSLg: the daemon predates the session env; point children at
            ;; the wayland socket when the var is missing but the socket is up.
            (when (and (not (getenv "WAYLAND_DISPLAY"))
                       (file-exists-p (expand-file-name "wayland-0" xrd)))
              (push "WAYLAND_DISPLAY=wayland-0" env))
            env)))
    (start-process-shell-command name nil cmd)))

(provide 'scott-launcher)
;;; scott-launcher.el ends here
