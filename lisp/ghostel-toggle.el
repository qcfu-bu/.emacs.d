;;; ghostel-toggle.el --- Per-project popup terminals for Ghostel  -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "29.1") (ghostel "0.32"))
;; Keywords: terminals

;;; Commentary:
;;
;; Two ways to open a Ghostel terminal:
;;
;;   `ghostel-toggle'       Show or hide the current project's popup
;;                          terminal.  There is one per project (one more for
;;                          buffers outside any project), created at the
;;                          project root on first use and reused afterwards.
;;                          With C-u, also `cd' it to the
;;                          current buffer's directory.
;;   `ghostel-toggle-here'  Open a new terminal in the selected window, as an
;;                          ordinary buffer (Doom's "terminal here").
;;
;; Where a popup terminal goes is left to `display-buffer', so a popup
;; manager such as popper decides; without one it opens at the bottom,
;; `ghostel-toggle-window-height' tall.  Popup rules should match Ghostel
;; buffers whose `ghostel-toggle-here-p' is nil.
;;
;; `ghostel-toggle-buffer-name' is meant for `ghostel-buffer-name-function':
;; it names terminals "*ghostel[PROJECT]*" / "*ghostel-here[PROJECT]*".

;;; Code:

(require 'ghostel)
(require 'project)

(defgroup ghostel-toggle nil
  "Per-project popup terminals for Ghostel."
  :group 'ghostel)

(defcustom ghostel-toggle-window-height 0.3
  "Height of a popup terminal when no `display-buffer-alist' rule places it.
A number of lines or a fraction of the frame, as for `window-height'."
  :type 'number)

;;;; Terminal state

(defvar-local ghostel-toggle-root nil
  "Project root the terminal was opened for, or nil outside any project.
Recorded at creation, so it does not drift when the shell changes directory.")
(put 'ghostel-toggle-root 'permanent-local t)

(defvar-local ghostel-toggle-here-p nil
  "Non-nil in a terminal from `ghostel-toggle-here', which is not a popup.")
(put 'ghostel-toggle-here-p 'permanent-local t)

(defvar ghostel-toggle--new-terminal nil
  "(ROOT . HERE-P) for the terminal being created, else nil.
`ghostel-mode-hook' applies it before the buffer is first displayed, so
display rules already see what kind of terminal it is.")

(defun ghostel-toggle--setup ()
  "Record the kind of terminal being created.  Runs in `ghostel-mode-hook'."
  (when ghostel-toggle--new-terminal
    (setq ghostel-toggle-root (car ghostel-toggle--new-terminal)
          ghostel-toggle-here-p (cdr ghostel-toggle--new-terminal))))

(add-hook 'ghostel-mode-hook #'ghostel-toggle--setup)

(defun ghostel-toggle--project-root ()
  "Return the current buffer's project root, or nil."
  (when-let* ((project (project-current)))
    (project-root project)))

(defun ghostel-toggle--popup-p (buffer)
  "Non-nil when BUFFER is a live popup terminal."
  (and (buffer-live-p buffer)
       (with-current-buffer buffer
         (and (derived-mode-p 'ghostel-mode)
              (not ghostel-toggle-here-p)))))

(defun ghostel-toggle--terminal (root)
  "Return the popup terminal for project ROOT, or nil."
  (seq-find (lambda (buffer)
              (and (ghostel-toggle--popup-p buffer)
                   (equal (buffer-local-value 'ghostel-toggle-root buffer)
                          root)))
            (buffer-list)))

;;;; Names

(defun ghostel-toggle--name (root here-p)
  "Return the buffer name for a terminal of ROOT (HERE-P: a here terminal)."
  (format (if here-p "*ghostel-here[%s]*" "*ghostel[%s]*")
          (if-let* ((project (and root (project-current nil root))))
              (project-name project)
            (file-name-nondirectory
             (directory-file-name default-directory)))))

(defun ghostel-toggle-buffer-name (_title)
  "Name the current terminal after its project.
A `ghostel-buffer-name-function'; ignores the terminal title."
  (ghostel-toggle--name ghostel-toggle-root ghostel-toggle-here-p))

;;;; Display

(defun ghostel-toggle--display-at-bottom (buffer alist)
  "Show BUFFER at the bottom, `ghostel-toggle-window-height' tall.
A `display-buffer' action function; ALIST as for `display-buffer-at-bottom'.
The height is added here rather than in the action alist: alist entries
reach whichever function displays the buffer, so they would override a
matching `display-buffer-alist' rule (such as popper's height)."
  (display-buffer-at-bottom
   buffer (append alist `((window-height . ,ghostel-toggle-window-height)))))

(defconst ghostel-toggle--display-action
  '((display-buffer-reuse-window ghostel-toggle--display-at-bottom))
  "Fallback action for popup terminals; `display-buffer-alist' comes first.")

(defun ghostel-toggle--new (root here-p display)
  "Create a terminal for ROOT in `default-directory', shown with DISPLAY.
HERE-P non-nil makes it a here terminal instead of a popup."
  (let ((ghostel-toggle--new-terminal (cons root here-p)))
    (ghostel-create (ghostel-toggle--name root here-p) display)))

;;;; Commands

(defun ghostel-toggle--cd (terminal dir)
  "Make the shell in TERMINAL `cd' to DIR, when on the same host."
  (when (and (equal (file-remote-p dir 'host)
                    (file-remote-p (buffer-local-value 'default-directory
                                                       terminal)
                                   'host))
             (not (equal (file-name-as-directory
                          (expand-file-name
                           (buffer-local-value 'default-directory terminal)))
                         (file-name-as-directory (expand-file-name dir)))))
    (with-current-buffer terminal
      ;; Clear any partly typed line first.
      (ghostel-send-key "a" "ctrl")
      (ghostel-send-key "k" "ctrl")
      (ghostel-send-string
       (concat "cd " (shell-quote-argument
                      (or (file-remote-p dir 'localname) dir))))
      (ghostel-send-key "return"))))

;;;###autoload
(defun ghostel-toggle (&optional cd)
  "Show or hide the current project's popup terminal.
Creates it at the project root if there is none.  With prefix argument
CD, show it and `cd' it to the current buffer's directory instead."
  (interactive "P")
  (let* ((dir default-directory)
         (root (if (ghostel-toggle--popup-p (current-buffer))
                   ghostel-toggle-root
                 (ghostel-toggle--project-root)))
         (terminal (ghostel-toggle--terminal root))
         (window (and terminal (get-buffer-window terminal))))
    (cond
     ((and window (not cd))
      (if (eq (window-deletable-p window) t)
          (delete-window window)
        (switch-to-prev-buffer window 'bury)))
     (terminal
      (pop-to-buffer terminal ghostel-toggle--display-action)
      (when cd (ghostel-toggle--cd terminal dir)))
     (t
      (let ((default-directory (if cd dir (or root dir))))
        (ghostel-toggle--new root nil ghostel-toggle--display-action))))))

;;;###autoload
(defun ghostel-toggle-here (&optional in-cwd)
  "Open a new terminal in the selected window, as an ordinary buffer.
It starts at the project root, or with prefix argument IN-CWD in the
current buffer's directory.  It is not a popup and `ghostel-toggle'
leaves it alone."
  (interactive "P")
  (let* ((root (ghostel-toggle--project-root))
         (default-directory (if in-cwd default-directory
                              (or root default-directory))))
    (ghostel-toggle--new root t '(display-buffer-same-window))))

;;;; Cleanup

(defun ghostel-toggle--close-windows ()
  "Close the windows of a popup terminal being killed (e.g. on shell exit).
Runs in `kill-buffer-hook'."
  (when (ghostel-toggle--popup-p (current-buffer))
    (dolist (window (get-buffer-window-list nil nil t))
      (when (eq (window-deletable-p window) t)
        (delete-window window)))))

(add-hook 'kill-buffer-hook #'ghostel-toggle--close-windows)

(provide 'ghostel-toggle)
;;; ghostel-toggle.el ends here
