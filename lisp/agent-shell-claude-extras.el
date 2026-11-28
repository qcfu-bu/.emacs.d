;;; agent-shell-claude-extras.el --- Extensions to agent-shell's Claude shells  -*- lexical-binding: t; -*-

;;; Commentary:
;;
;; `agent-shell-claude-extras-mode' turns on the extras below.
;;
;;;; Remote Control
;;
;; Claude Code's Remote Control (`/remote-control' in a Claude agent-shell)
;; lets the session be driven from claude.ai/code or the Claude mobile app.
;; A message typed there reaches Emacs as a `user_message_chunk' that no
;; Emacs request owns, and agent-shell has no rendering for that:
;;
;;   - between turns it draws an "Out of turn user_message_chunk - ACP
;;     server bug" block with the raw JSON, and
;;   - during a turn Emacs started, it drops the message.
;;
;; Either way the message is missing from the transcript file.  The mode
;; renders it as the user prompt it is, marked with
;; `agent-shell-claude-extras-remote-prefix', the way agent-shell renders
;; a steered prompt (see `agent-shell-experimental--render-steered-prompt').
;; Claude's answer already renders: only the user's side was missing.
;;
;; It also drops the adapter's "Unexpected case: {...}" notices for the
;; Remote Control bridge's own messages
;; (`agent-shell-claude-extras-hidden-notice-subtypes'), which otherwise
;; pile up under "Notices" every turn.
;;
;; The handler goes in through the Claude agent config's documented
;; `:notification-handler' slot, so only Claude shells are affected.  It
;; calls agent-shell internals to render, and if those change it reports
;; the error and hands the message back to agent-shell's own handling
;; rather than losing it.
;;
;; Not handled: the shell does not show as busy while a phone-started turn
;; runs.  The adapter sends no signal when such a turn ends
;; (claude-agent-acp#903), so there is nothing to clear a busy state with.

;;; Code:

(require 'agent-shell)
(require 'agent-shell-anthropic)
(require 'agent-shell-experimental)
(require 'map)
(require 'seq)
(require 'subr-x)

(defgroup agent-shell-claude-extras nil
  "Extensions to agent-shell's Claude shells."
  :group 'agent-shell)

(defcustom agent-shell-claude-extras-remote-prefix "[remote] "
  "Text marking a prompt that came in over Remote Control.
Inserted between the shell prompt and the message, like agent-shell's
own \"[steer] \" marker."
  :type 'string
  :group 'agent-shell-claude-extras)

(defcustom agent-shell-claude-extras-hidden-notice-subtypes
  '("bridge_state" "task_summary" "post_turn_summary")
  "Claude Code `system' message subtypes whose notices are dropped.
claude-agent-acp logs SDK messages it does not handle as
\"Unexpected case: {\"type\":\"system\",\"subtype\":...}\" on stderr,
which agent-shell shows under \"Notices\".  With Remote Control on,
these subtypes arrive every turn and carry nothing to act on."
  :type '(repeat string)
  :group 'agent-shell-claude-extras)

(defvar agent-shell-claude-extras--previous-notice-filter nil
  "`agent-shell-notice-filter-function' as it was before the mode was enabled.
Called for every notice the mode does not drop, and restored on disable.")

(defvar-local agent-shell-claude-extras--last-message-id nil
  "The `messageId' of the last Remote Control message rendered in this shell.
A message of several content blocks arrives as several chunks with one
id; they render into one prompt.")

;;; Rendering

(defun agent-shell-claude-extras--remote-message-p (state notification)
  "Return non-nil if NOTIFICATION is a Remote Control message for STATE.

That is a `user_message_chunk' that agent-shell would not render
itself: one arriving outside a `session/load' or `session/push',
whose replays it renders.  In a live Claude session the adapter
sends `user_message_chunk' only for messages typed in another
client; it does not echo the prompts Emacs sends."
  (and (equal (map-elt notification 'method) "session/update")
       (equal (map-nested-elt notification '(params update sessionUpdate))
              "user_message_chunk")
       (not (map-elt state :pending-restore))
       (let ((replay-methods (cons "session/load" (agent-shell-experimental--methods))))
         (not (seq-find (lambda (request)
                          (member (map-elt request :method) replay-methods))
                        (map-elt state :active-requests))))))

(defun agent-shell-claude-extras--chunk-text (update)
  "Return the text of user message chunk UPDATE.
A non-text block (an image, say) is shown by its type, as agent-shell
shows one in a replayed prompt."
  (or (map-nested-elt update '(content text))
      (format "[%s]" (or (map-nested-elt update '(content type)) "unknown"))))

(defun agent-shell-claude-extras--render (state notification)
  "Render Remote Control NOTIFICATION into STATE's shell as a user prompt.

Follows `agent-shell-experimental--render-steered-prompt': the prompt
takes the field/face shape of a live comint prompt, so prompt
navigation and chat mode treat it as a user turn, and an end-of-prompt
marker closes it.  It lands above the live input prompt, leaving
anything typed there in place.  A further chunk of the same message is
appended to the prompt already drawn."
  (let* ((update (map-nested-elt notification '(params update)))
         (message-id (map-elt update 'messageId))
         (text (agent-shell-claude-extras--chunk-text update)))
    (with-current-buffer (map-elt state :buffer)
      (let* ((continuing (and message-id
                              (equal message-id agent-shell-claude-extras--last-message-id)
                              (equal (map-elt state :last-entry-type)
                                     "remote_user_message")))
             (late-prompt-start (and (or agent-shell-persistent-prompt-enabled
                                         (not (shell-maker-busy)))
                                     (agent-shell--live-prompt-start))))
        (unless continuing
          (map-put! state :chunked-group-count
                    (1+ (map-elt state :chunked-group-count))))
        (agent-shell--append-transcript
         :text (if continuing
                   (format "%s\n\n" (agent-shell--indent-markdown-headers text))
                 (format "## User (remote) (%s)\n\n%s\n\n"
                         (format-time-string "%F %T")
                         (agent-shell--indent-markdown-headers text)))
         :file-path agent-shell--transcript-file)
        (agent-shell--with-buffer-narrowed-to late-prompt-start
          (agent-shell--update-text
           :state state
           :block-id (format "%s-remote-user_message_chunk"
                             (map-elt state :chunked-group-count))
           :text (if continuing
                     (propertize text 'font-lock-face 'agent-shell-input)
                   (concat (propertize (map-nested-elt state '(:agent-config :shell-prompt))
                                       'font-lock-face 'agent-shell-prompt
                                       'field 'output)
                           (propertize agent-shell-claude-extras-remote-prefix
                                       'font-lock-face 'agent-shell-input
                                       'agent-shell-claude-extras-remote-prefix t)
                           (propertize text 'font-lock-face 'agent-shell-input)))
           :create-new (not continuing)
           :append continuing)
          (unless continuing
            (shell-maker-insert-end-of-prompt-marker)
            ;; Under the narrowing `point-max' is the live prompt's start,
            ;; so this keeps that prompt on its own line.
            (when late-prompt-start
              (let ((inhibit-read-only t))
                (goto-char (point-max))
                (insert "\n")))))
        (when late-prompt-start
          ;; Rendering above the prompt pushed any unsubmitted input down,
          ;; so undo entries recorded for it point at the shifted text.
          (agent-shell--reset-undo-history))
        (unless continuing
          ;; A user submission, if not an Emacs one.  Chat mode relabels on it.
          (agent-shell--emit-event
           :event 'input-submitted
           :data (list (cons :prompt (substring-no-properties text)))))
        (setq agent-shell-claude-extras--last-message-id message-id)
        ;; Not "user_message_chunk": that asks agent-shell's replay path to
        ;; insert the end-of-prompt marker on the next notification, and one
        ;; has gone in above.
        (map-put! state :last-entry-type "remote_user_message")))))

(defun agent-shell-claude-extras--handle-notification (event)
  "Render EVENT's notification if it is a Remote Control message.

EVENT is the alist of `:state' and `:acp-notification' that agent-shell
passes an agent config's `:notification-handler'.  Return non-nil when
handled, which skips agent-shell's own handling.  A render that fails is
reported and returns nil, so agent-shell still shows the message its own
way."
  (let ((state (map-elt event :state))
        (notification (map-elt event :acp-notification)))
    (when (agent-shell-claude-extras--remote-message-p state notification)
      (condition-case err
          (progn
            (agent-shell-claude-extras--render state notification)
            t)
        (error
         (message "agent-shell-claude-extras-mode: could not render a Remote Control message: %s"
                  (error-message-string err))
         nil)))))

;;; Notices

(defun agent-shell-claude-extras--bridge-notice-p (text)
  "Return non-nil if notice TEXT reports a Remote Control bridge message."
  (and (stringp text)
       agent-shell-claude-extras-hidden-notice-subtypes
       (string-match-p
        (concat "\\`Unexpected case: {\"type\":\"system\",\"subtype\":\""
                (regexp-opt agent-shell-claude-extras-hidden-notice-subtypes)
                "\"")
        text)))

(defun agent-shell-claude-extras--filter-notice (notice)
  "Drop Remote Control bridge NOTICE, else pass it to the previous filter.
A value for `agent-shell-notice-filter-function'."
  (let ((text (map-elt notice :text)))
    (cond ((agent-shell-claude-extras--bridge-notice-p text) nil)
          (agent-shell-claude-extras--previous-notice-filter
           (funcall agent-shell-claude-extras--previous-notice-filter notice))
          (t text))))

;;; Installation

(defun agent-shell-claude-extras--add-handler (config)
  "Return Claude agent CONFIG with the Remote Control handler installed.
A handler someone else installed is left alone."
  (if (alist-get :notification-handler config)
      config
    (let ((config (copy-alist config)))
      (setf (alist-get :notification-handler config)
            #'agent-shell-claude-extras--handle-notification)
      config)))

(defun agent-shell-claude-extras--claude-shells ()
  "Return the live Claude agent-shell buffers."
  (seq-filter (lambda (buffer)
                (with-current-buffer buffer
                  (and (derived-mode-p 'agent-shell-mode)
                       (eq (map-nested-elt agent-shell--state
                                           '(:agent-config :identifier))
                           'claude-code))))
              (buffer-list)))

(defun agent-shell-claude-extras--set-shell-handler (buffer handler)
  "Set the notification handler of Claude shell BUFFER to HANDLER.
Only when the slot is empty or holds this mode's handler."
  (with-current-buffer buffer
    (when-let* ((cell (assq :notification-handler
                            (map-elt agent-shell--state :agent-config))))
      (when (memq (cdr cell) '(nil agent-shell-claude-extras--handle-notification))
        (setcdr cell handler)))))

;;;###autoload
(define-minor-mode agent-shell-claude-extras-mode
  "Extras for agent-shell's Claude shells.

Renders Remote Control messages (typed in the Claude mobile app or
claude.ai) as user prompts, and drops the Remote Control bridge's
notices.  Applies to Claude shells started from now on, and to those
already open.  See the commentary of agent-shell-claude-extras.el."
  :global t
  :group 'agent-shell-claude-extras
  (if agent-shell-claude-extras-mode
      (progn
        (advice-add 'agent-shell-anthropic-make-claude-code-config
                    :filter-return #'agent-shell-claude-extras--add-handler)
        (dolist (buffer (agent-shell-claude-extras--claude-shells))
          (agent-shell-claude-extras--set-shell-handler
           buffer #'agent-shell-claude-extras--handle-notification))
        (unless (eq agent-shell-notice-filter-function #'agent-shell-claude-extras--filter-notice)
          (setq agent-shell-claude-extras--previous-notice-filter agent-shell-notice-filter-function
                agent-shell-notice-filter-function #'agent-shell-claude-extras--filter-notice)))
    (advice-remove 'agent-shell-anthropic-make-claude-code-config
                   #'agent-shell-claude-extras--add-handler)
    (dolist (buffer (agent-shell-claude-extras--claude-shells))
      (agent-shell-claude-extras--set-shell-handler buffer nil))
    (when (eq agent-shell-notice-filter-function #'agent-shell-claude-extras--filter-notice)
      (setq agent-shell-notice-filter-function agent-shell-claude-extras--previous-notice-filter
            agent-shell-claude-extras--previous-notice-filter nil))))

(provide 'agent-shell-claude-extras)

;;; agent-shell-claude-extras.el ends here
