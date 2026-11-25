;;; nael-extras.el --- Extensions for nael: infoview, Lake, semantic tokens  -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "31.1") (nael "0") (eglot "1.17"))
;; Keywords: languages, lean

;;; Commentary:
;;
;; Extensions bringing nael (Lean 4 + Eglot) closer to the VS Code Lean
;; extension.  Modules:
;;
;;   nael-infoview.el  VS Code-style infoview: goals, expected type, lake
;;                     build progress and messages at point
;;   nael-lake.el      lake build / update / clean / cache get / any command
;;                     in a compilation buffer
;;   nael-semtok.el    makes Eglot's semantic tokens work with Lean's
;;                     partial answers
;;
;; This file loads them and adds the Lean server commands:
;;
;;   `nael-extras-restart-file'    "Lean 4: Restart File"
;;   `nael-extras-restart-server'  "Lean 4: Restart Server"
;;
;; Usage:
;;
;;   (use-package nael-extras
;;     :load-path "lisp/nael-extras"
;;     :after nael
;;     :config (nael-extras-mode 1))

;;; Code:

(require 'eglot)
(require 'nael-infoview)
(require 'nael-lake)
(require 'nael-semtok)

(defgroup nael-extras nil
  "Extensions for `nael-mode'."
  :group 'nael
  :prefix "nael-extras-")

;;;; Lean server commands

;;;###autoload
(defun nael-extras-restart-file ()
  "Restart Lean's worker for the current file, like VS Code's Restart File.
Sends didClose and didOpen; the new worker reruns `lake setup-file', which
rebuilds imports whose sources changed.  Use it after editing a file that
this one imports."
  (interactive)
  (unless (and (derived-mode-p 'nael-mode) (eglot-managed-p))
    (user-error "Not a Lean buffer managed by Eglot"))
  (eglot--signal-textDocument/didClose)
  (eglot--signal-textDocument/didOpen)
  ;; Drop state belonging to the old worker.
  (when (bound-and-true-p eglot-semantic-tokens-mode)
    (eglot-semantic-tokens-mode 1))
  (setq nael-infoview--lsp-diagnostics nil
        nael-infoview--build-status nil
        nael-infoview--build-done nil)
  (message "Restarted Lean file %s" (buffer-name)))

;;;###autoload
(defun nael-extras-restart-server ()
  "Restart the Lean language server of the current buffer."
  (interactive)
  (eglot-reconnect (eglot--current-server-or-lose)))

;;;; Global mode

;;;###autoload
(define-minor-mode nael-extras-mode
  "Global minor mode enabling all nael-extras modules.
Turns `nael-infoview-mode' and `nael-semtok-mode' on or off together;
the Lake and restart commands work regardless."
  :global t
  :group 'nael-extras
  (let ((arg (if nael-extras-mode 1 -1)))
    (nael-semtok-mode arg)
    (nael-infoview-mode arg)))

(provide 'nael-extras)
;;; nael-extras.el ends here
