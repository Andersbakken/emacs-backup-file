emacs-backup-file
=================

Automatically back up all changes made from emacs to a git repo in ~/.backups

To use:

    (require 'backup-file)
    (add-hook 'after-save-hook 'backup-file)
    (define-key global-map (kbd "C-c b") (function backup-file-log))
    ;; Or another key of your choosing

The repo in ~/.backups might eventually get really big so it might be
a good idea to have a cronjob or something do something along the
lines of this, e.g. in a cronjob

    cd ~/.backups
    commit=$(git log --since="1 week ago" --reverse --pretty=%h | head -n1)
    if [ -n "$commit" ]; then
       git checkout --orphan temp_remove_old_history "$commit"
       git commit -m "Truncated history" --allow-empty
       git rebase --onto temp_remove_old_history "$commit" master
       git branch -D temp_remove_old_history
       git prune --progress
       git gc --aggressive
    fi

You can also now also do this from elisp using:

(backup-file-truncate-history)

Example:

https://www.youtube.com/watch?v=NwdRFmVhEIo&feature=youtu.be