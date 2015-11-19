;; backup-file.el --- Back up all files that were modified by emacs in a private git repo

;; Copyright (C) 2011-2014  Anders Bakken

;; Author: Anders Bakken <agbakken@gmail.com>
;; URL: https://github.com/Andersbakken/emacs-backup-file

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(defconst backup-file-buffer-name "*Backup file*")
(defconst backup-file-bookmark-name "Backup file Bookmark")
(defvar backup-file-last-file nil)
(defvar backup-file-last-data nil)
(defvar backup-file-showing-inline-diffs nil)
(defvar backup-file-last-temp-buffer nil)
(defvar backup-file-mode-hook nil)
(defgroup backup-file nil "Backup file." :group 'tools :prefix "backup-file-")

(defcustom backup-file-reuse-temp-buffers t "Whether to reuse temp buffers for backup-file"
  :group 'backup-file
  :type 'boolean)
(defcustom backup-file-log t "Whether to log commands to a temp buffer called *Backup-file-log*" :type 'boolean)

(defvar backup-file-buffer-local-mode nil)
(make-variable-buffer-local 'backup-file-buffer-local-mode)

(defun backup-file-buffer-local-mode-keymap (mode-sym)
  (symbol-value (intern (concat (symbol-name mode-sym) "-map"))))

(defun* backup-file-buffer-local-buffer-local-set-key (key action)
  (when backup-file-buffer-local-mode
    (define-key (backup-file-buffer-local-mode-keymap backup-file-buffer-local-mode)
      key action)
    (return-from backup-file-buffer-local-buffer-local-set-key))
  (let* ((mode-name-loc (cl-gensym "-blm")))
    (eval `(define-minor-mode ,mode-name-loc nil nil nil (make-sparse-keymap)))
    (setq backup-file-buffer-local-mode mode-name-loc)
    (funcall mode-name-loc 1)
    (define-key (backup-file-buffer-local-mode-keymap mode-name-loc) key action)))

(defcustom backup-file-location (expand-file-name "~/.backups") "Where to store backup repo" :group 'backup-file :type 'string)

;; (add-hook 'after-save-hook 'backup-file)

(defvar backup-file-mode-map nil)
(setq backup-file-mode-map (make-sparse-keymap))
(set-keymap-parent backup-file-mode-map diff-mode-map)

(define-key backup-file-mode-map (kbd "q") (function bury-buffer))
(define-key backup-file-mode-map (kbd "Q") (function backup-file-kill-current-buffer))
(define-key backup-file-mode-map (kbd "=") (function backup-file-show-diff))
(define-key backup-file-mode-map (kbd ".") (function backup-file-show-diff-inline-prev))
(define-key backup-file-mode-map (kbd "k") (function backup-file-show-diff-inline-prev))
(define-key backup-file-mode-map (kbd "p") (function backup-file-show-diff-inline-prev))
(define-key backup-file-mode-map (kbd ",") (function backup-file-show-diff-inline-next))
(define-key backup-file-mode-map (kbd "j") (function backup-file-show-diff-inline-next))
(define-key backup-file-mode-map (kbd "n") (function backup-file-show-diff-inline-next))
(define-key backup-file-mode-map (kbd "d") (function backup-file-show-diff-inline))
(define-key backup-file-mode-map (kbd "+") (function backup-file-show-diff-inline))
(define-key backup-file-mode-map (kbd "o") (function backup-file-select-revision-at-point))
(define-key backup-file-mode-map (kbd "g") (function bury-buffer))
(define-key backup-file-mode-map (kbd "f") (function backup-file-select-revision-at-point))
(define-key backup-file-mode-map (kbd "r") (function backup-file-revert-to-revision-at-point))
(define-key backup-file-mode-map (kbd "D") (function backup-file-toggle-showing-inline-diffs))
(define-key backup-file-mode-map (kbd "RET") (function backup-file-select-revision-at-point-or-diff-goto-source))
(define-key backup-file-mode-map (kbd "ENTER") (function backup-file-select-revision-at-point-or-diff-goto-source))

(defun backup-file/.git ()
  (concat (expand-file-name backup-file-location) "/.git"))

(defun backup-file/--git-dir ()
  (concat "--git-dir=" (backup-file/.git)))

(defun backup-file-bury ()
  (interactive)
  (if (> (length (window-list)) 1)
      (delete-window)
    (backup-file-bury))
  (switch-to-buffer backup-file-buffer-name))

(defun backup-file-apply-show-revision-map ()
  (backup-file-buffer-local-buffer-local-set-key (kbd "q") (function bury-buffer))
  (backup-file-buffer-local-buffer-local-set-key (kbd "n") (function backup-file-next))
  (backup-file-buffer-local-buffer-local-set-key (kbd "p") (function backup-file-prev))
  (backup-file-buffer-local-buffer-local-set-key (kbd "Q") (function backup-file-kill-current-buffer)))

(define-derived-mode backup-file-mode text-mode
  (setq font-lock-defaults diff-font-lock-defaults)
  (setq mode-name "backup-file")
  (use-local-map backup-file-mode-map)
  (run-hooks 'backup-file-mode-hook))

(defun backup-file-replace-regexp (rx to)
  (save-excursion
    (while (re-search-forward rx nil t)
      (replace-match to nil nil))))

(defun backup-file-git (output &rest arguments)
  (let ((old default-directory)
        (outbuf (or output (and backup-file-log (get-buffer-create "*Backup-file-log*")))))
    (cd backup-file-location)
    (unless output
      (with-current-buffer outbuf
        (goto-char (point-max))
        (insert "git " (combine-and-quote-strings arguments) " =>\n")))
    (message default-directory)
    (apply #'call-process "git"
           nil
           outbuf
           nil
           arguments)
    (cd old)))

(defun backup-file-ensure-depot ()
  (when (not (file-directory-p (backup-file/.git)))
    (mkdir (expand-file-name backup-file-location) t)
    (backup-file-git nil "init")))

(defun backup-file-file-path (file)
  (and file (concat (expand-file-name backup-file-location) (replace-regexp-in-string "/\.git/" "/dot.git/" (file-truename file)))))

(defun backup-file ()
  (interactive)
  (let* ((path (backup-file-file-path (buffer-file-name))))
    (when path
      (backup-file-ensure-depot)
      (mkdir (file-name-directory path) t)
      (save-restriction
        (widen)
        (write-region (point-min) (point-max) path))
      (let ((old default-directory))
        ;; (setq default-directory backup-file-location)
        (cd backup-file-location)
        (call-process "git" nil nil nil "add" path)
        ;; (setq default-directory old)
        (start-process "git-backup-file" nil "git" (backup-file/--git-dir) "commit" "-m" (format "Update %s from emacs" (file-name-nondirectory (buffer-file-name))))
        (cd old)))))

(defun backup-file-switch-to-log ()
  (interactive)
  (let ((buf (get-buffer backup-file-buffer-name)))
    (when buf
      (switch-to-buffer buf))))

(defun backup-file-git-log-sentinel (process state)
  (when (string= state "finished\n")
    (let ((buf (process-buffer process)))
      (when buf
        (with-current-buffer buf
          (setq buffer-read-only nil)
          (goto-char (point-min))
          (goto-char(point-min))
          (setq backup-file-showing-inline-diffs nil)
          (setq backup-file-last-data (list))
          (while (not (eobp))
            (push (cons (buffer-substring (point-at-bol) (+ (point-at-bol) 7))
                        (buffer-substring (+ (point-at-bol) 7) (point-at-eol)))
                  backup-file-last-data)
            (if (< (point-at-eol) (point-max))
                (forward-line)
              (goto-char (point-max))))

          (backup-file-mode)
          (backup-file-redisplay)
          (setq buffer-read-only t))))))

(defun backup-file-buffer-file-name (&optional buffer)
  (let ((nam (buffer-file-name buffer)))
    (and nam (file-truename nam))))

(defun backup-file-log (&optional file)
  (interactive)
  (cond ((bufferp file) (setq file (backup-file-buffer-file-name file)))
        ((stringp file) (setq file (file-truename file)))
        (t (setq file (backup-file-buffer-file-name))))

  (unless (stringp file)
    (error "Backup-file needs a file"))

  (let* ((old default-directory)
         (git-filepath (backup-file-file-path file)))
    (if (not (file-exists-p git-filepath))
        (message "Backup-file: No backups for \"%s\"" file)
      (when (get-buffer backup-file-buffer-name)
        (kill-buffer backup-file-buffer-name))
      (switch-to-buffer (get-buffer-create backup-file-buffer-name))
      (cd backup-file-location)
      (let ((proc (start-process "git backup-file"
                                 (current-buffer)
                                 "git"
                                 (backup-file/--git-dir)
                                 "--no-pager"
                                 "log"
                                 "--pretty=format:%h%ar"
                                 "--" git-filepath)))
        (cd old)
        (set-process-query-on-exit-flag proc nil)
        ;; (set-process-filter proc (car async))
        (setq backup-file-last-file file)
        (set-process-sentinel proc (function backup-file-git-log-sentinel))))))

(defun backup-file-redisplay ()
  (setq buffer-read-only nil)
  (erase-buffer)
  (let ((i 1)
        (replace)
        (filename (file-name-nondirectory backup-file-last-file))
        (revformat (format "%%0%dd" (length (int-to-string (length backup-file-last-data))))))
    (dolist (data backup-file-last-data)
      (insert "Revision #" (format revformat i) " -- " (car data) " -- " filename " -- " (cdr data) "\n")
      (when (cond ((integerp backup-file-showing-inline-diffs) (= backup-file-showing-inline-diffs i))
                  (t backup-file-showing-inline-diffs))
        (backup-file-git (current-buffer) "show" (car data))
        (setq replace t)
        (insert "\n"))
      (incf i)
      (goto-char (point-min)))
    (when (> (point-max) (point-min))
      (goto-char (point-max))
      (backward-delete-char 1)
      (goto-char (point-min)))
    (when replace
      (backup-file-replace-regexp "^--- a/" "--- /")
      (backup-file-replace-regexp "^+++ b/" "+++ /")))
  (setq buffer-read-only t))

(defun backup-file-toggle-showing-inline-diffs (&optional arg)
  (interactive)
  (setq backup-file-showing-inline-diffs
        (cond ((not arg)
               (not backup-file-showing-inline-diffs))
              ((= arg 0) nil)
              (t t)))
  (save-excursion
    (backup-file-redisplay)))

(defun backup-file-data-index (&optional pos)
  (save-excursion
    (when pos
      (goto-char pos))
    (goto-char (point-at-bol))
    (when (looking-at "Revision #\\([0-9]+\\) -- ")
      (string-to-number (match-string 1)))))

(defun backup-file-data-nth (index)
  (nth (- index 1) backup-file-last-data))

(defun backup-file-show-diff (&optional pos)
  (interactive)
  (let ((index (backup-file-data-index)))
    (when index
      (let ((bufname (format "*%s#%d - Diff*" backup-file-last-file index)))
        (when (get-buffer bufname)
          (kill-buffer bufname))
        (when (and backup-file-reuse-temp-buffers backup-file-last-temp-buffer)
          (kill-buffer backup-file-last-temp-buffer))
        (switch-to-buffer (get-buffer-create bufname))
        (setq backup-file-last-temp-buffer (current-buffer))
        (backup-file-git (current-buffer) "show" (car (backup-file-data-nth index)))
        (goto-char (point-min))
        (backup-file-replace-regexp "^--- a/" "--- /")
        (backup-file-replace-regexp "^+++ b/" "+++ /")
        (diff-mode)
        (backup-file-buffer-local-buffer-local-set-key (kbd "q") (function bury-buffer))
        (setq buffer-read-only t)))))

(defun backup-file-show-diff-inline (&optional pos)
  (interactive)
  (let ((line (buffer-substring (point-at-bol) (point-at-eol)))
        (index (backup-file-data-index)))
    (if (eq index backup-file-showing-inline-diffs)
        (setq backup-file-showing-inline-diffs nil)
      (setq backup-file-showing-inline-diffs index))
    (backup-file-redisplay)
    (when (search-forward line)
      (beginning-of-line))))

(defun backup-file-show-diff-inline-jump (offset)
  (when (integerp backup-file-showing-inline-diffs)
    (let ((idx (+ backup-file-showing-inline-diffs offset)))
      (when (and (>= idx 0) (< idx (length backup-file-last-data)))
        (setq backup-file-showing-inline-diffs idx)
        (backup-file-redisplay)
        (when (search-forward (format "Revision #%d -- " idx))
          (beginning-of-line))))))

(defun backup-file-show-diff-inline-next ()
  (interactive)
  (backup-file-show-diff-inline-jump 1))

(defun backup-file-show-diff-inline-prev ()
  (interactive)
  (backup-file-show-diff-inline-jump -1))

(defun backup-file-kill-current-buffer ()
  (interactive)
  (kill-buffer (current-buffer)))

(defun backup-file-show-revision (index)
  (interactive)
  (when (and (stringp backup-file-last-file) (integerp index))
    (let ((bufname (format "*%s#%d*" backup-file-last-file index)))
      (when (get-buffer bufname)
        (kill-buffer bufname))
      (when (and backup-file-reuse-temp-buffers backup-file-last-temp-buffer)
        (kill-buffer backup-file-last-temp-buffer))
      (switch-to-buffer (get-buffer-create bufname))
      (setq backup-file-last-temp-buffer (current-buffer))
      (backup-file-git (current-buffer) "show" (concat (car (backup-file-data-nth index)) ":." backup-file-last-file))
      (setq buffer-file-name backup-file-last-file)
      (set-auto-mode)
      (setq buffer-file-name nil)
      (goto-char (point-min))
      (font-lock-fontify-buffer)
      (backup-file-apply-show-revision-map)
      (setq buffer-read-only t))))

(defun backup-file-select-revision-at-point ()
  (interactive)
  (let ((index (backup-file-data-index)))
    (when index
      (backup-file-show-revision index))))

(defun backup-file-select-revision-at-point-or-diff-goto-source ()
  (interactive)
  (let ((index (backup-file-data-index)))
    (if index
        (backup-file-show-revision index)
      (diff-goto-source))))

(defun backup-file-update ()
  (interactive)
  (when backup-file-last-file
    (backup-file-log backup-file-last-file)))

(defun backup-file-revert-to-revision-at-point ()
  (interactive)
  (let ((index (backup-file-data-index))
        (buf (get-file-buffer backup-file-last-file)))
    (when (or (not buf)
              (not (buffer-modified-p buf))
              (y-or-n-p (format "%s is modified. Are you sure you want to discard your changes? " backup-file-last-file)))
      (find-file backup-file-last-file)
      (erase-buffer)
      (backup-file-git (current-buffer) "show" (concat (car (backup-file-data-nth index)) ":." backup-file-last-file))
      (goto-char (point-min))
      (message "Reverted to revision #%d - %s - %s"
               index
               (car (backup-file-data-nth index))
               (cdr (backup-file-data-nth index))))))

(defun backup-file-jump (offset)
  (when (and (string-match "\\*\\(.*\\)#\\([0-9]+\\)\\*" (buffer-name))
             (string= (match-string 1 (buffer-name)) backup-file-last-file))
    (let ((idx (+ (string-to-number (match-string 2 (buffer-name))) offset)))
      (when (and (>= idx 0) (< idx (length backup-file-last-data)))
        (backup-file-show-revision idx)))))

(defun backup-file-next ()
  (interactive)
  (backup-file-jump 1))

(defun backup-file-prev ()
  (interactive)
  (backup-file-jump -1))

(defun backup-file-truncate-history (&optional date)
  (interactive)
  (let ((temp "temp_remove_old_history")
        (commit (or (with-temp-buffer
                      (backup-file-git (current-buffer) "log" "--reverse" (concat "--since=" (or date "1 week ago")) "--pretty=%h")
                      (and (> (point-max) (point-min))
                           (goto-char (point-min))
                           (buffer-substring-no-properties (point-min) (point-at-eol))))
                    (with-temp-buffer
                      (backup-file-git (current-buffer) "rev-parse" "--short" "HEAD")
                      (buffer-substring-no-properties (point-min) (1- (point-max)))))))
    (unless commit
      (error "Can't find a commit to reset to"))
    (backup-file-git nil "checkout" "--orphan" temp commit)
    (backup-file-git nil "commit" "--allow-empty" "-m" "Truncated history")
    (backup-file-git nil "rebase" "--onto" temp commit "master")
    (backup-file-git nil "branch" "-D" temp)
    (backup-file-git nil "prune" "--progress")
    (backup-file-git nil "gc" "--aggressive")))

(provide 'backup-file)
