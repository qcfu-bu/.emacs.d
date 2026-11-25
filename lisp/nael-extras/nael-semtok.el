;;; nael-semtok.el --- Make Eglot semantic tokens work with Lean  -*- lexical-binding: t; -*-

;; Part of nael-extras; see nael-extras.el.

;;; Commentary:
;;
;; Lean answers `textDocument/semanticTokens/full' with tokens only for the
;; part of the file elaborated so far, waiting up to 3 s for more, and then
;; sends `workspace/semanticTokens/refresh' every 2 s until a client request
;; gets a complete answer (Lean's Server/ProtocolOverview.lean and
;; FileWorker.lean).  Two things in Emacs 31's Eglot break this:
;;
;; 1. Eglot deliberately ignores refresh, so the first, near-empty answer
;;    stays cached until the buffer is edited.  We honour refresh in Lean
;;    buffers by invalidating the cached document version and refontifying.
;;
;; 2. Eglot sends one request per jit-lock chunk whenever its cache is
;;    stale: a dozen at once after a refresh.  Lean serves them one after
;;    another, 3 s apiece, so most exceed jsonrpc's 10 s timeout and their
;;    (complete) answers are dropped; Lean, having answered completely,
;;    stops refreshing, and the buffer is stuck with partial tokens until
;;    "Restart File".  We let only one request per document version be in
;;    flight; further chunks just add their region to it, and its answer
;;    refontifies them all.  A timed-out request is retried.
;;
;; Both fixes are active while the global `nael-semtok-mode' is on, which
;; `nael-extras-mode' turns on.

;;; Code:

(require 'cl-lib)
(require 'eglot)

(defgroup nael-semtok nil
  "Eglot semantic tokens fixes for Lean."
  :group 'nael-extras
  :prefix "nael-semtok-")

(defcustom nael-semtok-timeout 30
  "Seconds to wait for Lean's answer to a semantic tokens request."
  :type 'number)

(defvar nael-semtok-mode)               ; Defined at the end of the file.

(defvar-local nael-semtok--inflight nil
  "`eglot--docver' of the in-flight semantic tokens request, or nil.")

(defun nael-semtok--lean-buffer-p ()
  "Non-nil in a Lean buffer with Eglot semantic tokens on."
  (and nael-semtok-mode
       (derived-mode-p 'nael-mode)
       (bound-and-true-p eglot-semantic-tokens-mode)))

(defun nael-semtok--invalidate ()
  "Make the next font-lock pass request fresh tokens."
  (setf (plist-get eglot--semtok-state :docver) nil)
  (save-restriction (widen) (font-lock-flush)))

(cl-defmethod eglot-handle-request :after
  (server (_method (eql workspace/semanticTokens/refresh)) &rest _)
  "Honour Lean's refresh requests, which Eglot itself ignores."
  (dolist (buf (eglot--managed-buffers server))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (nael-semtok--lean-buffer-p)
          (nael-semtok--invalidate))))))

(defun nael-semtok--request (orig beg end)
  "Around advice for `eglot--semtok-request' (ORIG) on BEG..END.
In Lean buffers, coalesce requests for the same document version."
  (cond
   ((not (nael-semtok--lean-buffer-p))
    (funcall orig beg end))
   ((eql nael-semtok--inflight eglot--docver)
    ;; Its answer flushes every region recorded here.
    (push (cons (copy-marker beg) (copy-marker end))
          (plist-get eglot--semtok-state :regions))
    'coalesced)
   (t
    (let* ((buf (current-buffer))
           (docver eglot--docver)
           (done (lambda (&optional retry)
                   (when (buffer-live-p buf)
                     (with-current-buffer buf
                       (when (eql nael-semtok--inflight docver)
                         (setq nael-semtok--inflight nil)
                         (when (and retry (nael-semtok--lean-buffer-p))
                           (nael-semtok--invalidate)))))))
           (async (symbol-function 'eglot--async-request)))
      (cl-letf (((symbol-function 'eglot--async-request)
                 (lambda (server method params &rest kw)
                   (setq nael-semtok--inflight docver)
                   (let ((success (plist-get kw :success-fn)))
                     (funcall async server method params
                              :success-fn (lambda (r)
                                            (funcall done)
                                            (funcall success r))
                              :error-fn (lambda (_) (funcall done))
                              :timeout-fn (lambda () (funcall done t))
                              :timeout nael-semtok-timeout
                              :hint (plist-get kw :hint))))))
        (funcall orig beg end))))))

;;;###autoload
(define-minor-mode nael-semtok-mode
  "Global minor mode making Eglot's semantic tokens reliable with Lean.
See the commentary of nael-semtok.el."
  :global t
  :group 'nael-semtok
  (if nael-semtok-mode
      (advice-add 'eglot--semtok-request :around #'nael-semtok--request)
    (advice-remove 'eglot--semtok-request #'nael-semtok--request)))

(provide 'nael-semtok)
;;; nael-semtok.el ends here
