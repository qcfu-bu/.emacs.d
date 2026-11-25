;;; nael-lake.el --- Lake commands for nael  -*- lexical-binding: t; -*-

;; Part of nael-extras; see nael-extras.el.

;;; Commentary:
;;
;; Lake commands, modelled on the VS Code extension's command palette:
;;
;;   `nael-lake-build'       lake build [TARGETS]
;;   `nael-lake-update'      lake update [PACKAGES]
;;   `nael-lake-clean'       lake clean
;;   `nael-lake-cache-get'   lake exe cache get (Mathlib's prebuilt oleans)
;;   `nael-lake'             any lake command line
;;
;; Lake runs through `compilation-mode' in the root of the Lake package that
;; contains the current file, so errors are clickable and `recompile' works.
;; Files under .lake/packages/ belong to the workspace that vendors them,
;; not to the dependency's own package.

;;; Code:

(require 'ansi-color)
(require 'compile)
(require 'eglot)

(defgroup nael-lake nil
  "Lake commands for `nael-mode'."
  :group 'nael-extras
  :prefix "nael-lake-")

(defcustom nael-lake-program "lake"
  "Lake executable."
  :type 'string)

(defcustom nael-lake-global-args '("--no-ansi")
  "Options passed to lake before the command.
Lake colours its output even into a pipe and redraws its progress line
with escape codes, which would garble the compilation buffer and hide
error locations from `compilation-mode'."
  :type '(repeat string))

(defcustom nael-lake-restart-server-after '("update" "cache-get")
  "Lake commands after whose success the Lean server is restarted.
Members are \"update\", \"cache-get\", \"clean\" and \"build\".  Updating
dependencies or downloading oleans changes what running file workers
have loaded, so VS Code restarts the server after them as well."
  :type '(set (const "update") (const "cache-get")
              (const "clean") (const "build")))

;;;; Project root

(defconst nael-lake--config-files '("lakefile.lean" "lakefile.toml")
  "Files marking the root of a Lake package.")

(defun nael-lake--root ()
  "Return the root directory of the current Lake workspace.
Skips packages vendored under .lake/, so that from a dependency's file
the commands still act on the workspace you are working in."
  (let ((dir (expand-file-name default-directory)))
    (when-let* ((pos (string-search "/.lake/" dir)))
      (setq dir (substring dir 0 (1+ pos))))
    (or (locate-dominating-file
         dir (lambda (d)
               (seq-some (lambda (f) (file-exists-p (expand-file-name f d)))
                         nael-lake--config-files)))
        (user-error "Not inside a Lake package (no %s found)"
                    (string-join nael-lake--config-files " or ")))))

;;;; Running lake

(defconst nael-lake--error-regexp
  '(nael-lake
    "^\\(?:error\\|\\(warning\\)\\|\\(info\\)\\): \\(?:\\./\\)*\\([^:\n]+\\.lean\\):\\([0-9]+\\):\\([0-9]+\\)"
    3 4 5 (1 . 2))
  "Lake's `error: Foo/Bar.lean:LINE:COL: message' lines.
Lean reports 0-based columns, hence `compilation-first-column' 0 below.")

(define-compilation-mode nael-lake-compilation-mode "Lake"
  "Compilation mode for lake output."
  (setq-local compilation-error-regexp-alist '(nael-lake))
  (setq-local compilation-error-regexp-alist-alist
              (list nael-lake--error-regexp))
  (setq-local compilation-first-column 0)
  ;; Even with --no-ansi lake 5 still colours its closing "error: build
  ;; failed" line; render any such stray escapes.
  (add-hook 'compilation-filter-hook #'ansi-color-compilation-filter nil t)
  (setq-local compilation-scroll-output 'first-error))

(defun nael-lake--lean-buffers (root)
  "Return Eglot-managed Lean buffers whose files lie under ROOT."
  (seq-filter (lambda (b)
                (with-current-buffer b
                  (and (derived-mode-p 'nael-mode)
                       buffer-file-name
                       (eglot-managed-p)
                       (file-in-directory-p buffer-file-name root))))
              (buffer-list)))

(defun nael-lake--restart-servers (root)
  "Reconnect every Lean server managing a buffer under ROOT."
  (dolist (server (delete-dups
                   (mapcar (lambda (b) (with-current-buffer b
                                         (eglot-current-server)))
                           (nael-lake--lean-buffers root))))
    (when (jsonrpc-running-p server)
      (eglot-reconnect server))))

(defun nael-lake--run (args &optional kind)
  "Run lake with ARGS (a list of strings) at the workspace root.
KIND names the command for `nael-lake-restart-server-after'."
  (let* ((root (nael-lake--root))
         (default-directory root)
         (command (mapconcat #'shell-quote-argument
                             (append (list nael-lake-program)
                                     nael-lake-global-args args)
                             " "))
         (buffer (compilation-start
                  command #'nael-lake-compilation-mode
                  (lambda (_mode)
                    (format "*lake: %s*"
                            (file-name-nondirectory
                             (directory-file-name root)))))))
    (with-current-buffer buffer
      (setq-local compilation-finish-functions
                  (when (member kind nael-lake-restart-server-after)
                    (list (lambda (_buf status)
                            (when (string-prefix-p "finished" status)
                              (nael-lake--restart-servers root)))))))
    buffer))

(defun nael-lake--read-words (prompt)
  "Read a space-separated list of words with PROMPT."
  (split-string-and-unquote (read-string prompt)))

;;;###autoload
(defun nael-lake-build (&optional targets)
  "Run `lake build'.  With a prefix argument, prompt for TARGETS."
  (interactive (list (and current-prefix-arg
                          (nael-lake--read-words "lake build targets: "))))
  (nael-lake--run (cons "build" targets) "build"))

;;;###autoload
(defun nael-lake-update (&optional packages)
  "Run `lake update'.  With a prefix argument, prompt for PACKAGES.
Restarts the Lean server afterwards (see `nael-lake-restart-server-after')."
  (interactive (list (and current-prefix-arg
                          (nael-lake--read-words "lake update packages: "))))
  (nael-lake--run (cons "update" packages) "update"))

;;;###autoload
(defun nael-lake-clean ()
  "Run `lake clean' after confirmation."
  (interactive)
  (when (yes-or-no-p (format "Remove build outputs in %s? "
                             (abbreviate-file-name (nael-lake--root))))
    (nael-lake--run '("clean") "clean")))

;;;###autoload
(defun nael-lake-cache-get ()
  "Run `lake exe cache get' to download prebuilt Mathlib oleans."
  (interactive)
  (nael-lake--run '("exe" "cache" "get") "cache-get"))

;;;###autoload
(defun nael-lake (args)
  "Run lake with ARGS, read from the minibuffer."
  (interactive (list (nael-lake--read-words "lake ")))
  (nael-lake--run args))

(provide 'nael-lake)
;;; nael-lake.el ends here
