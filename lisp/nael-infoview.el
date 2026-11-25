;;; nael-infoview.el --- VS Code-style Lean infoview for nael + Eglot  -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "31.1") (nael "0") (eglot "1.17"))
;; Keywords: languages, lean

;;; Commentary:
;;
;; A dedicated Lean 4 infoview for `nael-mode' buffers managed by Eglot,
;; modelled on the VS Code extension's infoview panel.  For the cursor
;; position in the last selected Lean window it shows:
;;
;;   Foo.lean:12:4  Processing…
;;   Tactic state      goals from `$/lean/plainGoal', or "No goals"
;;   Expected type     from `$/lean/plainTermGoal'
;;   Building          lake's latest progress line while imports build
;;   Messages          diagnostics (errors, warnings, #eval output, ...)
;;                     whose range covers the cursor line
;;
;; It is independent of ElDoc.  Goals are requested directly over Eglot's
;; JSON-RPC connection, and refreshes are driven explicitly:
;;
;; - cursor movement or edits in the tracked Lean window (debounced);
;; - `$/lean/fileProgress': refetch when Lean finishes elaborating up to the
;;   cursor, and show a "Processing…" indicator meanwhile;
;; - `textDocument/publishDiagnostics': re-render the messages section;
;;   lake's output while building imports arrives this way too (see
;;   `nael-infoview--build-progress-p');
;; - selecting another Lean window.
;;
;; Replies to superseded requests are dropped, so a slow answer for an old
;; position never overwrites a newer one.  Nothing is requested while the
;; infoview is hidden.
;;
;; In Lean buffers nael's own goal ElDoc functions and Flymake's diagnostic
;; ElDoc function are removed, so ElDoc is left with plain hover/signature
;; documentation and nothing is shown twice.
;;
;; Visibility is explicit: the infoview opens when a Lean server connects
;; (see `nael-infoview-open-on-connect') and otherwise only through
;; `nael-infoview-toggle' / `nael-infoview-open' / `nael-infoview-close'.
;; Cursor movement never opens it, and `q' does not close it.
;;
;; Usage:
;;
;;   (use-package nael-infoview
;;     :after nael
;;     :config (nael-infoview-mode 1))

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'eglot)
(require 'flymake)
(require 'nael)
(require 'nael-eglot)

;;;; Customization

(defgroup nael-infoview nil
  "VS Code-style Lean infoview for `nael-mode'."
  :group 'nael
  :prefix "nael-infoview-")

(defcustom nael-infoview-buffer-name "*lean-infoview*"
  "Name of the Lean infoview buffer."
  :type 'string)

(defcustom nael-infoview-refresh-delay 0.1
  "Seconds of quiet after a change before the infoview refreshes."
  :type 'number)

(defcustom nael-infoview-open-on-connect t
  "Non-nil means open the infoview when a Lean language server connects.
This happens once per (re)connection, not per buffer, so a closed infoview
stays closed while you keep working."
  :type 'boolean)

(defcustom nael-infoview-display-action
  '((display-buffer-reuse-window display-buffer-in-direction)
    (direction . right)
    (window-width . 0.5)
    (preserve-size . (t . nil))
    (dedicated . t)
    (window-parameters . ((no-delete-other-windows . t))))
  "`display-buffer' action used to show the infoview.
The default puts it in an ordinary window to the right of the Lean window
\(not a side window, so a right-hand side window can still sit beyond it).
An entry for the infoview buffer in `display-buffer-alist' takes
precedence over this."
  :type 'sexp)

(defface nael-infoview-section
  '((t :inherit nael-eglot-eldoc-header :extend t))
  "Face for section headings in the infoview.")

(defface nael-infoview-location
  '((t :inherit shadow))
  "Face for the file:line:column heading in the infoview.")

(defface nael-infoview-processing
  '((t :inherit warning))
  "Face for the \"Processing…\" indicator.")

(defface nael-infoview-dim
  '((t :inherit shadow :slant italic))
  "Face for placeholder text such as \"No goals\".")

;;;; State

(defvar nael-infoview-mode)             ; Defined at the end of the file.

(defvar nael-infoview--source-window nil
  "The Lean window whose cursor position the infoview follows.")

(defvar nael-infoview--source-buffer nil
  "The Lean buffer the infoview follows.
Kept separately from the window so the infoview keeps working after that
window has been deleted or switched to another buffer.")

(defvar nael-infoview--timer nil
  "Pending debounced refresh timer.")

(defvar nael-infoview--pending nil
  "Strongest refresh requested since the last one ran.
One of nil, `check' (refetch only if the position or text changed),
`render' (also redraw from cached results) or `fetch' (always refetch).")

(defvar nael-infoview--last-key nil
  "(BUFFER POS TICK) of the most recent fetch, to skip redundant requests.")

(defvar nael-infoview--generation 0
  "Counter identifying the latest fetch; replies to older fetches are dropped.")

(defvar nael-infoview--goal nil
  "Last `$/lean/plainGoal' result, or nil.")

(defvar nael-infoview--term-goal nil
  "Last `$/lean/plainTermGoal' result, or nil.")

(defvar nael-infoview--busy nil
  "Non-nil when Lean was still processing the source position at last check.")

(defvar-local nael-infoview--processing nil
  "Latest `processing' ranges from `$/lean/fileProgress' for this buffer.")

(defvar-local nael-infoview--lsp-diagnostics nil
  "Latest raw LSP diagnostics published for this buffer, minus build output.")

(defvar-local nael-infoview--build-status nil
  "Latest lake output line of the current or last import build, or nil.
Each line replaces the previous one, like VS Code's infoview.  Lean clears
its build diagnostic the moment the build ends, often before the infoview
could draw it, so the last line is kept until Lean has finished processing
the file (or a new build starts).")

(defvar-local nael-infoview--build-done nil
  "Non-nil once the build in `nael-infoview--build-status' has ended.")

;;;; Infoview buffer

(defvar-keymap nael-infoview-buffer-mode-map
  :doc "Keymap for `nael-infoview-buffer-mode'."
  ;; `special-mode' binds `q' to `quit-window'; the infoview only closes
  ;; through `nael-infoview-toggle' / `nael-infoview-close'.
  "q" #'ignore)

(define-derived-mode nael-infoview-buffer-mode special-mode "Lean-Infoview"
  "Major mode of the Lean infoview buffer.
\\`q' deliberately does nothing; use `nael-infoview-toggle' to close it."
  (setq-local nobreak-char-display nil
              truncate-lines nil
              cursor-in-non-selected-windows nil))

;; evil-collection binds `q' to `quit-window' for `special-mode' buffers in
;; normal state, which the plain keymap above cannot override.
(with-eval-after-load 'evil
  (when (fboundp 'evil-define-key*)
    (evil-define-key* '(normal motion) nael-infoview-buffer-mode-map
      "q" #'ignore)))

(defun nael-infoview--buffer ()
  "Return the infoview buffer, creating it if needed."
  (let ((buffer (get-buffer-create nael-infoview-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'nael-infoview-buffer-mode)
        (nael-infoview-buffer-mode)))
    buffer))

(defun nael-infoview--windows ()
  "Return all live windows, on any frame, showing the infoview."
  (when-let* ((buffer (get-buffer nael-infoview-buffer-name)))
    (get-buffer-window-list buffer nil t)))

(defun nael-infoview--visible-p ()
  "Non-nil when the infoview is shown in some window."
  (and (nael-infoview--windows) t))

;;;; Source tracking

(defun nael-infoview--lean-window-p (window)
  "Non-nil when WINDOW is live and shows a Lean buffer."
  (and (window-live-p window)
       (with-current-buffer (window-buffer window)
         (derived-mode-p 'nael-mode))))

(defun nael-infoview--set-source (window)
  "Make the Lean WINDOW the one the infoview follows."
  (setq nael-infoview--source-window window
        nael-infoview--source-buffer (window-buffer window)))

(defun nael-infoview--source ()
  "Return (BUFFER . POS) for the position the infoview follows, or nil."
  (let ((window nael-infoview--source-window)
        (buffer nael-infoview--source-buffer))
    (cond
     ((and (window-live-p window) (buffer-live-p buffer)
           (eq (window-buffer window) buffer))
      (cons buffer (window-point window)))
     ((buffer-live-p buffer)
      (cons buffer (with-current-buffer buffer (point)))))))

(defun nael-infoview--on-window-change (_frame)
  "Follow the selected window when it is a different Lean window.
Member of `window-selection-change-functions' and
`window-buffer-change-functions'."
  (let ((window (selected-window)))
    (when (and (nael-infoview--lean-window-p window)
               (not (and (eq window nael-infoview--source-window)
                         (eq (window-buffer window)
                             nael-infoview--source-buffer))))
      (nael-infoview--set-source window)
      (nael-infoview--schedule 'check))))

(defun nael-infoview--post-command ()
  "Schedule a refresh after a command in the selected Lean window."
  (when (eq (current-buffer) (window-buffer (selected-window)))
    (nael-infoview--set-source (selected-window))
    (nael-infoview--schedule 'check)))

;;;; Refresh scheduling

(defconst nael-infoview--levels '(check render fetch)
  "Refresh levels, weakest first (see `nael-infoview--pending').")

(defun nael-infoview--schedule (level)
  "Request a refresh of at least LEVEL, debounced.
LEVEL is one of `nael-infoview--levels'.  Does nothing while the
infoview is hidden."
  (when (nael-infoview--visible-p)
    ;; Keep the stronger of the pending and the requested level.
    (when (and nael-infoview--pending
               (> (cl-position nael-infoview--pending nael-infoview--levels)
                  (cl-position level nael-infoview--levels)))
      (setq level nael-infoview--pending))
    (setq nael-infoview--pending level)
    (when (timerp nael-infoview--timer)
      (cancel-timer nael-infoview--timer))
    ;; A plain (not idle) timer: notifications arrive while Emacs is already
    ;; idle, when a fresh idle timer would not fire until the next command.
    (setq nael-infoview--timer
          (run-with-timer nael-infoview-refresh-delay nil
                          #'nael-infoview--run))))

(defun nael-infoview--run ()
  "Carry out the pending refresh."
  (let ((level nael-infoview--pending))
    (setq nael-infoview--timer nil
          nael-infoview--pending nil)
    (when-let* (((nael-infoview--visible-p))
                (source (nael-infoview--source)))
      (pcase-let ((`(,buffer . ,pos) source))
        (let ((key (list buffer pos
                         (buffer-chars-modified-tick buffer))))
          (cond
           ((or (eq level 'fetch)
                (not (equal key nael-infoview--last-key)))
            (setq nael-infoview--last-key key)
            (nael-infoview--fetch buffer pos))
           ((eq level 'render)
            (nael-infoview--render))))))))

;;;; Fetching goals

(defun nael-infoview--fetch (buffer pos)
  "Request goal and term goal at POS in BUFFER, then render.
Both requests go out together; the infoview is redrawn once when both
have answered, unless a newer fetch has started in the meantime."
  (let ((generation (cl-incf nael-infoview--generation)))
    (with-current-buffer buffer
      (if-let* ((server (eglot-current-server)))
          (let ((params (save-excursion
                          (goto-char pos)
                          (eglot--TextDocumentPositionParams)))
                (pending 2)
                goal term-goal)
            (cl-flet* ((done ()
                         (when (and (zerop (cl-decf pending))
                                    (= generation nael-infoview--generation))
                           (setq nael-infoview--goal goal
                                 nael-infoview--term-goal term-goal)
                           (nael-infoview--render)))
                       (send (method setter)
                         (jsonrpc-async-request
                          server method params
                          :success-fn (lambda (result)
                                        (funcall setter result)
                                        (done))
                          :error-fn (lambda (_) (done))
                          :timeout-fn (lambda () (done)))))
              ;; Make sure the server has our latest text before asking
              ;; about a position in it (Eglot sends edits lazily).
              (eglot--signal-textDocument/didChange)
              (send :$/lean/plainGoal (lambda (r) (setq goal r)))
              (send :$/lean/plainTermGoal (lambda (r) (setq term-goal r)))))
        (setq nael-infoview--goal nil
              nael-infoview--term-goal nil)
        (nael-infoview--render)))))

;;;; Server notifications

(defun nael-infoview--busy-at-p (buffer pos)
  "Non-nil when Lean is still processing BUFFER at or before POS."
  (with-current-buffer buffer
    (let ((line (1- (line-number-at-pos pos t))))
      (seq-some (lambda (item)
                  (<= (plist-get (plist-get (plist-get item :range) :start)
                                 :line)
                      line))
                nael-infoview--processing))))

(cl-defmethod eglot-handle-notification
  (server (_method (eql $/lean/fileProgress))
          &key textDocument processing &allow-other-keys)
  "Track Lean's elaboration progress for the infoview."
  (when-let* ((uri (plist-get textDocument :uri))
              (path (ignore-errors (expand-file-name (eglot-uri-to-path uri))))
              (buffer (eglot--find-buffer-visiting server path)))
    (with-current-buffer buffer
      (setq nael-infoview--processing processing)
      ;; File fully processed: the finished build's log has served its turn.
      (when (and nael-infoview--build-done (seq-empty-p processing))
        (setq nael-infoview--build-status nil
              nael-infoview--build-done nil)
        (when (eq buffer nael-infoview--source-buffer)
          (nael-infoview--schedule 'render))))
    (when-let* (((bound-and-true-p nael-infoview-mode))
                ((eq buffer nael-infoview--source-buffer))
                (source (nael-infoview--source)))
      (let ((was-busy nael-infoview--busy)
            (busy (nael-infoview--busy-at-p (car source) (cdr source))))
        (setq nael-infoview--busy busy)
        (cond
         ;; Elaboration just got past the cursor: goals there are final.
         ((and was-busy (not busy)) (nael-infoview--schedule 'fetch))
         ;; Just update the "Processing…" indicator.
         ((not (eq was-busy busy)) (nael-infoview--schedule 'render)))))))

(defun nael-infoview--build-progress-p (diags)
  "Non-nil when DIAGS is Lean's report of one line of lake output.
While `lake setup-file' builds the imports, the file worker publishes
each stderr line as the sole diagnostic: severity information, `range'
on the first line and a `fullRange' spanning the file (Lean's
FileWorker.lean, `setupImports').

The stale-dependency notice (\"Imports are out of date…\", from
`handleStaleDependency') has exactly the same shape but is a sticky
message that Lean re-publishes with every diagnostics update, so it is
excluded and shown as an ordinary message instead."
  (and (= (length diags) 1)
       (let* ((d (aref diags 0))
              (start (plist-get (plist-get d :range) :start))
              (end (plist-get (plist-get d :range) :end)))
         (and (eql (plist-get d :severity) 3)
              (plist-get d :fullRange)
              (not (string-prefix-p "Imports are out of date"
                                    (plist-get d :message)))
              (eql (plist-get start :line) 0)
              (eql (plist-get start :character) 0)
              (eql (plist-get end :line) 1)
              (eql (plist-get end :character) 0)))))

(cl-defmethod eglot-handle-notification :after
  (server (_method (eql textDocument/publishDiagnostics))
          &key uri diagnostics &allow-other-keys)
  "Record Lean's diagnostics and lake output; re-render the infoview."
  (when-let* ((path (ignore-errors (expand-file-name (eglot-uri-to-path uri))))
              (buffer (eglot--find-buffer-visiting server path))
              ((with-current-buffer buffer (derived-mode-p 'nael-mode))))
    (with-current-buffer buffer
      (if (nael-infoview--build-progress-p diagnostics)
          (let ((line (string-trim-right
                       (plist-get (aref diagnostics 0) :message))))
            (setq nael-infoview--lsp-diagnostics nil
                  nael-infoview--build-status line
                  nael-infoview--build-done nil))
        ;; Lean re-appends its sticky stale-dependency notice each time a
        ;; dependency changes, so identical messages can repeat.
        (setq nael-infoview--lsp-diagnostics (seq-uniq diagnostics))
        (when nael-infoview--build-status
          (setq nael-infoview--build-done t))))
    (when (and nael-infoview-mode
               (nael-infoview--visible-p)
               (eq buffer nael-infoview--source-buffer))
      (nael-infoview--schedule 'render))))

;;;; Rendering

(defun nael-infoview--fontify (string)
  "Return STRING fontified as Lean code."
  (nael-eglot-eldoc-fontify string))

(defun nael-infoview--indent (string)
  "Indent every line of STRING by two spaces."
  (replace-regexp-in-string "^" "  " string))

(defun nael-infoview--insert-section (title)
  "Insert a section heading TITLE."
  (insert (propertize (concat title "\n") 'face 'nael-infoview-section)))

(defun nael-infoview--diagnostic-kind (diag)
  "Return (LABEL . FACE) describing the severity of LSP DIAG."
  (pcase (plist-get diag :severity)
    (1 '("error" . error))
    (2 '("warning" . warning))
    (_ '("info" . success))))

(defun nael-infoview--diagnostics (buffer pos)
  "Return BUFFER's LSP diagnostics whose range covers the line of POS.
Like VS Code's infoview, use Lean's `fullRange' (the whole extent of
the message) when present, else the possibly trimmed `range'."
  (with-current-buffer buffer
    (let ((line (1- (line-number-at-pos pos t))))
      (sort (seq-filter
             (lambda (d)
               (let ((r (or (plist-get d :fullRange) (plist-get d :range))))
                 (<= (plist-get (plist-get r :start) :line)
                     line
                     (plist-get (plist-get r :end) :line))))
             nael-infoview--lsp-diagnostics)
            :key (lambda (d)
                   (let ((start (plist-get (plist-get d :range) :start)))
                     (cons (plist-get start :line)
                           (plist-get start :character))))
            :lessp (lambda (a b)
                     (or (< (car a) (car b))
                         (and (= (car a) (car b)) (< (cdr a) (cdr b)))))))))

(defun nael-infoview--insert-contents (buffer pos)
  "Insert infoview contents for POS in BUFFER into the current buffer."
  (let* ((line (with-current-buffer buffer (line-number-at-pos pos t)))
         (col (with-current-buffer buffer
                (save-excursion (goto-char pos) (current-column))))
         (connected (with-current-buffer buffer (eglot-current-server)))
         (goal nael-infoview--goal)
         (goals (and goal (plist-get goal :goals)))
         (term (and nael-infoview--term-goal
                    (plist-get nael-infoview--term-goal :goal)))
         (diags (nael-infoview--diagnostics buffer pos))
         (build-status (buffer-local-value 'nael-infoview--build-status buffer))
         (build-done (buffer-local-value 'nael-infoview--build-done buffer))
         (shown nil))
    ;; Header.
    (insert (propertize (format "%s:%d:%d" (buffer-name buffer) line col)
                        'face 'nael-infoview-location))
    (when (nael-infoview--busy-at-p buffer pos)
      (insert "  " (propertize "Processing…" 'face 'nael-infoview-processing)))
    (insert "\n\n")
    (unless connected
      (insert (propertize "Waiting for the Lean server…\n" 'face
                          'nael-infoview-dim)))
    ;; Lake's latest progress line while the imports build.
    (when build-status
      (setq shown t)
      (nael-infoview--insert-section
       (if build-done "Built imports" "Building imports…"))
      (insert (propertize (nael-infoview--indent build-status)
                          'face 'nael-infoview-dim)
              "\n\n"))
    ;; Tactic state: present only inside tactic blocks.
    (when goal
      (setq shown t)
      (nael-infoview--insert-section
       (if (seq-empty-p goals)
           "Tactic state"
         (format "Tactic state: %d goal%s"
                 (length goals) (if (= (length goals) 1) "" "s"))))
      (if (seq-empty-p goals)
          (insert (propertize "  No goals" 'face 'nael-infoview-dim) "\n")
        (insert (mapconcat (lambda (g)
                             (nael-infoview--indent (nael-infoview--fontify g)))
                           goals "\n\n")
                "\n"))
      (insert "\n"))
    ;; Expected type.
    (when (and term (not (string-empty-p term)))
      (setq shown t)
      (nael-infoview--insert-section "Expected type")
      (insert (nael-infoview--indent (nael-infoview--fontify term)) "\n\n"))
    ;; Messages on the cursor line.
    (when diags
      (setq shown t)
      (nael-infoview--insert-section (format "Messages (%d)" (length diags)))
      (dolist (diag diags)
        (pcase-let ((`(,label . ,face) (nael-infoview--diagnostic-kind diag))
                    (start (plist-get (plist-get diag :range) :start)))
          (insert "  "
                  (propertize (format "%d:%d %s:"
                                      (1+ (plist-get start :line))
                                      (plist-get start :character)
                                      label)
                              'face face)
                  "\n"
                  (replace-regexp-in-string
                   "^" "    " (string-trim-right (plist-get diag :message)))
                  "\n\n"))))
    (when (and connected (not shown))
      (insert (propertize "No info found at this position.\n"
                          'face 'nael-infoview-dim)))))

(defun nael-infoview--render ()
  "Redraw the infoview from cached results, keeping each window's scroll."
  (when-let* ((infoview (get-buffer nael-infoview-buffer-name))
              (source (nael-infoview--source)))
    (with-current-buffer infoview
      (let ((inhibit-read-only t)
            (old-point (point))
            (scrolls (mapcar (lambda (w) (list w (window-start w) (window-point w)))
                             (get-buffer-window-list infoview nil t))))
        (erase-buffer)
        (nael-infoview--insert-contents (car source) (cdr source))
        (goto-char (min old-point (point-max)))
        (pcase-dolist (`(,w ,start ,wpoint) scrolls)
          (set-window-start w (min start (point-max)) t)
          (set-window-point w (min wpoint (point-max))))))))

;;;; Windows and commands

;;;###autoload
(defun nael-infoview-open (&optional window)
  "Show the Lean infoview to the right of WINDOW.
WINDOW defaults to the Lean window the infoview follows, else the
selected window."
  (interactive)
  (let ((anchor (or window
                    (and (window-live-p nael-infoview--source-window)
                         nael-infoview--source-window)
                    (selected-window))))
    (when (nael-infoview--lean-window-p anchor)
      (nael-infoview--set-source anchor))
    (display-buffer (nael-infoview--buffer)
                    (cons (car nael-infoview-display-action)
                          (cons `(window . ,anchor)
                                (cdr nael-infoview-display-action))))
    (nael-infoview--schedule 'fetch)))

;;;###autoload
(defun nael-infoview-close ()
  "Close every window showing the Lean infoview.  The buffer is kept."
  (interactive)
  (dolist (window (nael-infoview--windows))
    (if (window-deletable-p window)
        (delete-window window)
      ;; The sole window of its frame: show something else in it instead.
      (set-window-dedicated-p window nil)
      (switch-to-prev-buffer window 'bury))))

;;;###autoload
(defun nael-infoview-toggle ()
  "Close the Lean infoview if it is shown, otherwise open it."
  (interactive)
  (if (nael-infoview--visible-p)
      (nael-infoview-close)
    (nael-infoview-open)))

(defun nael-infoview--on-connect (server)
  "Open the infoview when SERVER, a Lean language server, has connected.
Member of `eglot-connect-hook'."
  (when (and nael-infoview-open-on-connect
             (memq 'nael-mode (eglot--major-modes server)))
    ;; The connection completes asynchronously, so the selected window may
    ;; be elsewhere by now: anchor next to a window showing one of the
    ;; server's buffers.
    (when-let* ((window (seq-some (lambda (b) (get-buffer-window b t))
                                  (eglot--managed-buffers server))))
      (if (nael-infoview--visible-p)
          (progn (nael-infoview--set-source window)
                 (nael-infoview--schedule 'fetch))
        (nael-infoview-open window)))))

;;;; Per-buffer setup

(defun nael-infoview--strip-eldoc ()
  "Remove ElDoc sources the infoview already covers from this buffer."
  (dolist (fn '(nael-eglot-eldoc-goal
                nael-eglot-eldoc-term-goal
                flymake-eldoc-function))
    (remove-hook 'eldoc-documentation-functions fn t)))

(defun nael-infoview--restore-eldoc ()
  "Undo `nael-infoview--strip-eldoc' in this buffer."
  (when (bound-and-true-p eglot--managed-mode)
    (nael-eglot-configure-when-managed))
  (when (bound-and-true-p flymake-mode)
    (add-hook 'eldoc-documentation-functions #'flymake-eldoc-function t t)))

(defun nael-infoview--setup-buffer ()
  "Hook the current Lean buffer up to the infoview."
  (add-hook 'post-command-hook #'nael-infoview--post-command nil t)
  ;; Depth 90: run after nael's own `eglot-managed-mode-hook' function,
  ;; which is what adds the goal ElDoc functions.
  (add-hook 'eglot-managed-mode-hook #'nael-infoview--strip-eldoc 90 t)
  (add-hook 'flymake-mode-hook #'nael-infoview--strip-eldoc 90 t)
  (nael-infoview--strip-eldoc))

(defun nael-infoview--teardown-buffer ()
  "Disconnect the current Lean buffer from the infoview."
  (remove-hook 'post-command-hook #'nael-infoview--post-command t)
  (remove-hook 'eglot-managed-mode-hook #'nael-infoview--strip-eldoc t)
  (remove-hook 'flymake-mode-hook #'nael-infoview--strip-eldoc t)
  (nael-infoview--restore-eldoc))

(defun nael-infoview--lean-buffers ()
  "Return all live `nael-mode' buffers."
  (seq-filter (lambda (b) (with-current-buffer b (derived-mode-p 'nael-mode)))
              (buffer-list)))

;;;###autoload
(define-minor-mode nael-infoview-mode
  "Global minor mode providing a VS Code-style infoview for Lean buffers.
See the commentary of nael-infoview.el for details."
  :global t
  :group 'nael-infoview
  (if nael-infoview-mode
      (progn
        (add-hook 'nael-mode-hook #'nael-infoview--setup-buffer)
        (add-hook 'eglot-connect-hook #'nael-infoview--on-connect)
        (add-hook 'window-selection-change-functions
                  #'nael-infoview--on-window-change)
        (add-hook 'window-buffer-change-functions
                  #'nael-infoview--on-window-change)
        (dolist (b (nael-infoview--lean-buffers))
          (with-current-buffer b (nael-infoview--setup-buffer))))
    (remove-hook 'nael-mode-hook #'nael-infoview--setup-buffer)
    (remove-hook 'eglot-connect-hook #'nael-infoview--on-connect)
    (remove-hook 'window-selection-change-functions
                 #'nael-infoview--on-window-change)
    (remove-hook 'window-buffer-change-functions
                 #'nael-infoview--on-window-change)
    (when (timerp nael-infoview--timer)
      (cancel-timer nael-infoview--timer))
    (setq nael-infoview--timer nil
          nael-infoview--pending nil)
    (dolist (b (nael-infoview--lean-buffers))
      (with-current-buffer b (nael-infoview--teardown-buffer)))
    (nael-infoview-close)))

(provide 'nael-infoview)
;;; nael-infoview.el ends here
