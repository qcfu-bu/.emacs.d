;;; init.el --- emacs dotfile -*- lexical-binding: t -*-

;;; bootstrap
;;;; lisp
(add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory))

;;;; straight
(setq straight-check-for-modifications '(check-on-save)
      straight-cache-autoloads t)
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))
;; Emacs ships project/xref/jsonrpc/eldoc/flymake.  Left to itself straight
;; clones the GNU-ELPA copies whenever a package lists them as deps (rustic pulls
;; `project', copilot `jsonrpc'), shadowing the built-ins on `load-path' and
;; erroring with "Feature `project' is now provided by a different file".  Mark
;; them built-in so straight skips them.  Must be set before those packages load.
(setq straight-built-in-pseudo-packages
      (append '(project xref jsonrpc eldoc flymake external-completion)
              straight-built-in-pseudo-packages))
(straight-use-package 'use-package)

;;;; benchmark
(use-package benchmark-init
  :straight t
  :config
  (benchmark-init/activate)
  ;; Stop instrumenting `require'/`load' once startup is done so it does not add
  ;; overhead all session. `M-x benchmark-init/show-durations-tree' still works.
  (add-hook 'after-init-hook #'benchmark-init/deactivate))

;;;; gc
(use-package gcmh
  :straight t
  :config
  (setq gcmh-idle-delay 'auto
        gcmh-auto-idle-delay-factor 10
        gcmh-high-cons-threshold (* 128 1024 1024))
  (gcmh-mode 1))

;;;; path
(use-package exec-path-from-shell
  :straight t
  :config
  (when (eq system-type 'darwin)
    (setq exec-path-from-shell-arguments nil)
    (exec-path-from-shell-initialize)))

;;;; server
(use-package server
  :config (unless (server-running-p) (server-start)))

;;; system
;;;; info
(setq user-full-name "Qiancheng Fu"
      user-mail-address "qcfu@bu.edu")

;;;; defaults
(setq read-process-output-max (* 4 1024 1024)) ;; 4mb
(setq native-comp-async-report-warnings-errors nil)
(setq jit-lock-defer-time 0)

(setq use-short-answers t)
(setq frame-resize-pixelwise t)
(setq confirm-kill-emacs 'yes-or-no-p)
(setq-default line-spacing 0.1)
(setq-default truncate-lines t)
(setq-default tab-width 2)
(setq-default indent-tabs-mode nil)
(setq-default indent-line-function 'insert-tab)
(setq-default fill-column 90)
(setq delete-by-moving-to-trash t)

;;;; fonts
;; Guard on the font being installed so a fresh machine without "JetBrains Mono"
;; does not error out during startup (it just falls back to the default font).
(when (find-font (font-spec :family "JetBrains Mono"))
  (dolist (face '(default fixed-pitch variable-pitch))
    (set-face-attribute face nil :font "JetBrains Mono:pixelsize=14")))

;;;; theme
(use-package doom-themes
  :straight t
  :config (load-theme 'doom-one t))

(use-package solaire-mode
  :straight t
  :config 
  (solaire-global-mode t))

;;;; modeline
(use-package doom-modeline
  :straight t
  :config
  (setq doom-modeline-bar-width nil
        doom-modeline-buffer-file-name-style 'buffer-name
        doom-modeline-check-simple-format t)
  (doom-modeline-mode t))

;;;; titlebar
(use-package ns-auto-titlebar
  :straight t
  :config
  (when (eq system-type 'darwin)
    (ns-auto-titlebar-mode)))

;;;; minibuffer
(setq minibuffer-prompt-properties
      '(read-only t cursor-intangible t face minibuffer-prompt))
(add-hook 'minibuffer-setup-hook #'cursor-intangible-mode)
(setq enable-recursive-minibuffers t)

;;;; scrolling
(setq hscroll-margin 2
      hscroll-step 1
      ;; Emacs spends too much effort recentering the screen if you scroll the
      ;; cursor more than N lines past window edges (where N is the settings of
      ;; `scroll-conservatively'). This is especially slow in larger files
      ;; during large-scale scrolling commands. If kept over 100, the window is
      ;; never automatically recentered.
      scroll-conservatively 101
      scroll-margin 0
      scroll-preserve-screen-position t
      ;; Reduce cursor lag by a tiny bit by not auto-adjusting `window-vscroll'
      ;; for tall lines.
      auto-window-vscroll nil
      ;; mouse
      mouse-wheel-scroll-amount '(2 ((shift) . hscroll))
      mouse-wheel-scroll-amount-horizontal 2)
(pixel-scroll-precision-mode t)

;;;; yascroll
;; Local modernized rewrite of yascroll (lisp/yascroll.el): a non-intrusive
;; scroll bar that appears on scroll and auto-hides while idle.  The thumb
;; is a viewport-fixed child frame at the window's right edge: overlay-based
;; thumbs are anchored to buffer text and visibly ride along with it under
;; `pixel-scroll-precision-mode', and the fringes belong to diff-hl
;; (`diff-hl-side' is `right') — a child frame avoids both.  On macOS the
;; thumb is purely visual: its window ignores the mouse entirely.
(use-package yascroll
  :demand t
  :config
  (setq yascroll-scroll-bar '(child-frame text-area))
  (setq yascroll-delay-to-hide nil)
  (global-yascroll-bar-mode 1))

;;;; files
(use-package files
  :config
  (setq make-backup-files nil)
  (setq auto-save-default nil))

;;;; autorevert
(use-package autorevert
  :init (global-auto-revert-mode))

;;;; history
(use-package saveplace
  :init (save-place-mode))

(use-package savehist
  :init (savehist-mode))

(use-package recentf
  :hook (after-init . recentf-mode)
  :init
  (setq recentf-max-menu-items 40
        recentf-max-saved-items 40)
  :config
  (add-to-list 'recentf-exclude "~/.emacs.d/.cache/*")
  (add-to-list 'recentf-exclude "~/.emacs.d/bookmarks")
  (add-to-list 'recentf-exclude "/private/var/folders/*"))

;;; completion
;;;; orderless
(use-package orderless
  :straight t
  :config
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

;;;; vertico
(use-package vertico
  :straight t
  :config
  (setq vertico-resize nil
        vertico-count 17)
  (vertico-mode))

(use-package consult
  :straight t
  :defer t
  :after vertico
  :config
  (add-to-list 'consult-buffer-filter "^\\*")
  (setq consult-preview-key nil)
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref))

(use-package marginalia
  :straight t
  :after vertico
  :config
  (marginalia-mode))

(use-package embark
  :straight t
  :bind (("C-;" . embark-act))
  :config
  (setq embark-quit-after-action nil))

(use-package embark-consult
  :straight t
  :defer t)

;;;; corfu
(use-package corfu
  :straight t
  :config
  (setq corfu-auto t
        corfu-auto-prefix 2
        corfu-cycle t
        corfu-count 16
        corfu-max-width 120
        corfu-on-exact-match 'quit)
  (global-corfu-mode t)
  (corfu-history-mode t))

(use-package cape
  :straight t
  :config
  (setq cape-dabbrev-check-other-buffers nil)
  (add-to-list 'completion-at-point-functions #'cape-dabbrev)
  (add-to-list 'completion-at-point-functions #'cape-file))

;;; editor
;;;; evil
(use-package evil
  :straight t
  :hook (after-init . evil-mode)
  :init
  (setq evil-want-integration t
        evil-want-keybinding nil
        evil-want-C-u-scroll t
        evil-undo-system 'undo-fu
        evil-respect-visual-line-mode t)
  :config
  (setq evil-emacs-state-tag "E"
        evil-insert-state-tag "I"
        evil-motion-state-tag "M"
        evil-normal-state-tag "N"
        evil-operator-state-tag "O"
        evil-replace-state-tag "R"
        evil-visual-char-tag "V"
        evil-visual-block-tag "Vb"
        evil-visual-line-tag "Vl"
        evil-visual-screen-line-tag "Vs"
        evil-treemacs-state-tag "Tr"))

(use-package evil-collection
  :straight t
  :after evil
  :config (evil-collection-init))

(use-package evil-escape
  :straight t
  :after evil
  :hook (evil-mode . evil-escape-mode)
  :config
  (setq evil-escape-excluded-states '(normal visual multiedit emacs motion treemacs)
        evil-escape-excluded-major-modes '(ghostel-mode)
        evil-escape-key-sequence "jk"
        evil-escape-delay 0.2))

(use-package evil-surround
  :straight t
  :after evil
  :config
  (global-evil-surround-mode t))

(use-package evil-commentary
  :straight t
  :after evil
  :config
  (evil-commentary-mode))

(use-package evil-anzu
  :straight t
  :after evil
  :config
  (global-anzu-mode 1))

(use-package evil-easymotion
  :straight t
  :after evil
  :config
  (evilem-default-keybindings "gs"))

;;;; general
(use-package general
  :straight t
  :after evil
  :config
  (general-override-mode 1))

(general-create-definer spc-leader-def
  :states '(normal treemacs)
  :keymaps 'override
  :prefix "SPC")

;;;; which-key
(use-package which-key
  :straight t
  :config
  (which-key-setup-minibuffer)
  (which-key-mode))

;;;; word-wrap
(use-package adaptive-wrap
  :straight t
  :hook (visual-line-mode . adaptive-wrap-prefix-mode))

;;;; undo
(use-package undo-fu
  :straight t)

(use-package undo-fu-session
  :straight t
  :after undo-fu
  :config
  (undo-fu-session-global-mode))

;;;; snippets
(use-package yasnippet
  :straight t
  :hook (after-init . yas-global-mode))

;;;; format
(use-package reformatter
  :straight t
  :commands reformatter-define)

;;;; spell
(use-package flyspell
  :defer t
  :init
  (defun flyspell-mode-maybe ()
    "Enable `flyspell-mode', but only when a spell-checker is installed.
Avoids an error on systems without aspell/hunspell/ispell."
    (when (or (executable-find "aspell")
              (executable-find "hunspell")
              (executable-find "ispell"))
      (flyspell-mode 1))))

;;; ui
;;;; icons
(use-package nerd-icons-completion
  :straight t
  :after marginalia
  :config
  (nerd-icons-completion-mode)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package nerd-icons-corfu
  :straight t
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-dired
  :straight t
  :after dired
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package nerd-icons-ibuffer
  :straight t
  :after ibuffer
  :hook (ibuffer-mode . nerd-icons-ibuffer-mode))

;;;; dired
(use-package dired
  :hook (dired-mode . dired-omit-mode)
  :config
  (setq dired-omit-files "^\\(?:\\..*\\|.*~\\)$\\|\\.vo\\(?:k\\|s\\)$"
        dired-listing-switches "-alh"
        dired-use-ls-dired nil
        dired-dwim-target t))

(use-package dired-subtree
  :straight t
  :after dired)

(use-package diredfl
  :straight t
  :hook (dired-mode . diredfl-mode))

;;;; treemacs
(use-package treemacs
  :straight t
  :defer t
  :init
  (setq treemacs-follow-after-init t
        treemacs-expand-after-init nil
        treemacs-sorting 'alphabetic-case-insensitive-asc
        treemacs-width 30)
  :config
  (treemacs-project-follow-mode t)
  (treemacs-git-mode 'simple)
  (treemacs-hide-gitignored-files-mode 1))

(use-package treemacs-nerd-icons
  :straight t
  :after nerd-icons treemacs
  :config (treemacs-load-theme "nerd-icons"))

(use-package treemacs-evil
  :straight t
  :after treemacs evil)

(use-package treemacs-magit
  :straight t
  :after treemacs magit)

;;;; popup
(use-package popper
  :straight t
  :config
  (setq popper-window-height 20)
  (setq popper-reference-buffers
        '("\\*Messages\\*"
          "\\*Warnings\\*"
          "\\*compilation\\*" compilation-mode
          "\\*grep\\*"
          "Output\\*$"
          "\\*Async Shell Command\\*"
          "^\\*eldoc.\*"
          "^\\*xref\\*$"
          "^\\*Org Select\\*$"
          "^\\*TeX Help\\*$"
          "^\\*ghostel"
          "^\\*utop\\*$"
          "^\\*cargo-test\\*$"
          "^\\*haskell\\*$"
          "^\\*poly\\*$"
          "^\\*Python\\*$"))
  (popper-mode 1)
  (popper-echo-mode 1))

;;;; transpose-frame
(use-package transpose-frame
  :straight t
  :commands (transpose-frame))

;;;; tab-bar
(use-package tab-bar
  :init
  (setq tab-bar-show 1
        tab-bar-new-tab-choice "*scratch*"))

;;;; line-numbers
(use-package display-line-numbers
  :hook ((prog-mode text-mode conf-mode) . display-line-numbers-mode)
  :config
  (setq-default display-line-numbers-width 4))

;;;; vi-tilde
(use-package vi-tilde-fringe
  :straight t
  :hook
  ((prog-mode text-mode conf-mode) . vi-tilde-fringe-mode))

;;;; delimiter
(use-package electric
  :config
  (setq electric-pair-inhibit-predicate 'electric-pair-conservative-inhibit)
  (electric-pair-mode t))

(use-package rainbow-delimiters
  :straight t
  :hook (prog-mode . rainbow-delimiters-mode))

;;;; highlight
(use-package rainbow-mode
  :straight t
  :defer t)

(use-package indent-bars
  :straight t
  :defer t
  :hook ((prog-mode text-mode) . indent-bars-mode)
  :custom
  (indent-bars-pattern ".")
  (indent-bars-width-frac 0.1)
  ;; VSCode-style guides: dim monochrome bars everywhere, brighter inside the
  ;; treesit scope around point, brightest at point's own depth.
  (indent-bars-color '(default :blend 0.1))
  (indent-bars-color-by-depth nil)
  (indent-bars-highlight-current-depth '(:blend 0.3))
  (indent-bars-treesit-support t)
  ;; `in-scope' means the ts- variables style in-scope bars, and the plain
  ;; variables above style out-of-scope bars (and non-treesit buffers).
  (indent-bars-ts-styling-scope 'in-scope)
  (indent-bars-ts-color '(inherit unspecified :blend 0.1)))

(use-package hl-todo
  :straight t
  :hook ((prog-mode text-mode) . hl-todo-mode)
  :config
  (setq hl-todo-highlight-punctuation ":"
        hl-todo-keyword-faces
        '(("TODO" warning bold)
          ("FIXME" error bold)
          ("REVIEW" font-lock-keyword-face bold)
          ("HACK" font-lock-constant-face bold)
          ("DEPRECATED" font-lock-doc-face bold)
          ("NOTE" success bold)
          ("BUG" error bold))))

;;;; presentation
(use-package olivetti
  :straight t
  :defer t)

(use-package outli
  :straight
  (outli
   :type git
   :host github
   :repo "jdtsmith/outli")
  :hook (emacs-lisp-mode . outli-mode)
  :config
  (setq outli-default-nobar t))

;;; tools
;;;; magit
(use-package magit
  :straight t
  :defer t
  :config
  (setq magit-bury-buffer-function 'magit-restore-window-configuration
        magit-display-buffer-function #'magit-display-buffer-fullframe-status-v1))

(use-package diff-hl
  :straight t
  :config
  (add-hook 'magit-pre-refresh-hook 'diff-hl-magit-pre-refresh)
  (add-hook 'magit-post-refresh-hook 'diff-hl-magit-post-refresh)
  (setq diff-hl-side 'right)
  (global-diff-hl-mode))

(use-package gitignore-templates
  :straight t
  :defer t)

;;;; llm
(use-package copilot
  :straight t
  :defer t
  :hook (after-init . copilot-setup)
  :bind (:map copilot-completion-map
              ("<tab>" . 'copilot-accept-completion)
              ("C-<tab>" . 'copilot-accept-completion-by-word))
  :init
  (setq copilot-indent-offset-warning-disable t)
  (setq copilot-max-char-warning-disable t)
  (defun copilot-setup ()
    (add-hook 'prog-mode-hook #'copilot-mode)
    (add-hook 'text-mode-hook #'copilot-mode)
    (add-hook 'prog-mode-hook #'copilot-nes-mode)
    (add-hook 'text-mode-hook #'copilot-nes-mode))
  :config
  (add-to-list 'copilot-indentation-alist '(prog-mode 2))
  (add-to-list 'copilot-indentation-alist '(org-mode 2))
  (add-to-list 'copilot-indentation-alist '(text-mode 2)))

(use-package agent-shell
  :straight t
  :config
  (setq agent-shell-anthropic-authentication
        (agent-shell-anthropic-make-authentication :login t))
  (setq agent-shell-anthropic-default-session-mode-id "auto")
  ;; Display a freshly started shell immediately.  The default `prompt'
  ;; session strategy defers showing the buffer until a session is chosen,
  ;; so the first invocation after killing a shell looks like nothing
  ;; happened (`latest' would instead auto-resume the previous session).
  (setq agent-shell-session-strategy 'latest)
  ;; Side window at the frame edge: stays at the far right even when the Lean
  ;; infoview (a normal window in the main area) is open, giving
  ;; [code | infoview | shell].
  (setq agent-shell-display-action
        '(display-buffer-in-side-window
          (side . right)
          (window-width . 0.3)))
  (defun my/agent-shell-toggle-or-start ()
    "Toggle the agent shell, starting a new claude-code one if none exists."
    (interactive)
    (if (or (agent-shell--current-shell)
            (agent-shell-project-buffers)
            (agent-shell-buffers))
        (agent-shell-toggle)
      (agent-shell-anthropic-start-claude-code))))

;;;; eldoc
(use-package eldoc
  :general
  (:states 'normal "K" 'eldoc-doc-buffer)
  :config
  (setq eldoc-display-functions '(eldoc-display-in-buffer)))

;;;; project
(use-package project
  ;; Built-in — do NOT add `:straight t' (see the eglot note below).  Emacs
  ;; autoloads project.el on demand via its own commands, so this block only
  ;; houses project.el settings; the SPC-p leader keys live in `;;; keybinds'.
  :defer t
  :config
  ;; Also treat any directory containing a `.project' file as a project root.
  (setq project-vc-extra-root-markers '(".project")))

;;;; eglot
;; Built-in on Emacs 30 — do NOT add `:straight t'.  straight would build the
;; GNU-ELPA eglot plus its deps (project/xref/jsonrpc); eglot's load-time
;; `require-with-check' guard (eglot.el: "signal an error if the loaded file is
;; not the one that should have been loaded") then fails with "provided by a
;; different file".  `straight-built-in-pseudo-packages' in the bootstrap keeps
;; straight from shadowing these built-ins.
(use-package eglot
  :commands (eglot-ensure)
  :init
  (defun eglot-format-on-save ()
    ;; Buffer-local (nil t): format only THIS buffer on save.  Without the local
    ;; flag this lands on the GLOBAL `before-save-hook' and errors when saving
    ;; any buffer that has no eglot server.
    (add-hook 'before-save-hook #'eglot-format-buffer nil t))
  :config
  (setq eglot-ignored-server-capabilities '(:inlayHintProvider))
  (advice-add 'eglot-completion-at-point :around #'cape-wrap-buster)
  (add-to-list 'eglot-server-programs '((tex-mode context-mode texinfo-mode bibtex-mode) . ("texlab")))
  (add-to-list 'eglot-server-programs '((python-mode python-ts-mode) . ("pyright-langserver" "--stdio")))
  (add-to-list 'eglot-server-programs '((c-mode c-ts-mode c++-mode c++-ts-mode objc-mode) . ("clangd")))
  (add-to-list 'eglot-server-programs '((rust-mode rust-ts-mode) .
                                        ("rust-analyzer" :initializationOptions
                                         (:procMacro (:enable t)
                                          :cargo (:buildScripts (:enable t)
                                                  :features "all"))))))

;;;; compile
(use-package compile
  :commands (compile recompile)
  :config
  (setq compilation-scroll-output t
        compile-command "make"))

;;;; pdf
(use-package pdf-tools
  :straight t
  :defer t
  :hook
  ((pdf-view-mode
    . (lambda () (set (make-local-variable 'evil-normal-state-cursor) (list nil)))))
  :init (pdf-loader-install)
  :config
  (setq-default pdf-view-display-size 'fit-page)
  (setq pdf-view-use-scaling t
        pdf-view-use-imagemagick nil)
  (evil-define-key 'normal pdf-view-mode-map
    (kbd "zm") 'pdf-view-themed-minor-mode))

;;;; restart
(use-package restart-emacs
  :straight t
  :defer t)

;;; term
;;;; ghostel
(use-package ghostel
  :straight t
  :defer t
  :hook
  ((ghostel-mode . (lambda () (setq confirm-kill-processes nil))))
  :config
  ;; Terminals are named per-project by `ghostel-toggle-buffer-name-by-project'
  ;; (wired up in lisp/ghostel-toggle.el).
  (setq ghostel-kill-buffer-on-exit t
        ghostel-max-scrollback 5000))

;;;; ghostel-toggle
;; Local port of vterm-toggle (lisp/ghostel-toggle.el) replacing the old
;; hand-rolled popup.  Window placement is delegated to display-buffer, so it
;; reuses the popper rule for "*ghostel*".
(use-package ghostel-toggle
  :commands (ghostel-toggle ghostel-toggle-cd
             ghostel-toggle-forward ghostel-toggle-backward)
  :bind ("C-`" . ghostel-toggle)
  :config
  ;; Per-project scoping: one terminal per project, reused on toggle, with
  ;; project-aware show/hide.  All the logic lives in ghostel-toggle.el; this
  ;; single switch is the whole API (it overrides `ghostel-toggle-scope').
  (setq ghostel-toggle-scoped t))

;;; lang
;;;; treesit
(use-package treesit-auto
  :straight t
  :custom (treesit-auto-install 'prompt)
  :config
  (setq treesit-font-lock-level 3)
  (treesit-auto-add-to-auto-mode-alist 'all)
  (global-treesit-auto-mode))

;;;; markdown
(use-package markdown-mode
  :straight t
  :mode ("/README\\(?:\\.md\\)?\\'" . gfm-mode)
  :hook
  ((markdown-mode . visual-line-mode)
   (markdown-mode . flyspell-mode-maybe))
  :init
  (setq markdown-enable-math t
        markdown-enable-wiki-links t
        markdown-italic-underscore t
        markdown-asymmetric-header t
        markdown-gfm-additional-languages '("sh")
        markdown-make-gfm-checkboxes-buttons t
        markdown-fontify-whole-heading-line t
        markdown-fontify-code-blocks-natively t
        markdown-command "multimarkdown"))

;;;; org
(use-package org
  :hook
  ((org-mode . visual-line-mode)
   (org-mode . flyspell-mode-maybe)
   (org-mode . (lambda ()
                 (modify-syntax-entry ?< "." org-mode-syntax-table)
                 (modify-syntax-entry ?> "." org-mode-syntax-table))))
  :config
  (setq org-startup-indented t
        org-hide-leading-stars t
        org-src-window-setup 'current-window
        org-html-validation-link nil))

(use-package htmlize
  :straight t
  :defer t)

;;;; latex
(use-package auctex
  :straight t
  :hook
  ((LaTeX-mode . eglot-ensure)
   (LaTeX-mode . visual-line-mode)
   (LaTeX-mode . flyspell-mode-maybe)
   (LaTeX-mode . rainbow-delimiters-mode))
  :init
  (add-hook 'TeX-after-compilation-finished-functions #'TeX-revert-document-buffer)
  (setq TeX-PDF-mode t
        TeX-master nil
        TeX-parse-self t
        TeX-auto-save t
        TeX-save-query nil
        TeX-command-extra-options "-shell-escape"
        TeX-auto-local ".auctex-auto"
        TeX-style-local ".auctex-style"
        TeX-view-program-list '(("Skim" "/Applications/Skim.app/Contents/SharedSupport/displayline -g -b %n %o %b"))
        TeX-view-program-selection '((output-pdf "Skim"))
        ;; TeX-view-program-selection '((output-pdf "PDF Tools"))
        TeX-source-correlate-mode t
        TeX-source-correlate-method 'synctex
        TeX-electric-math '("$" . "$")
        TeX-electric-sub-and-superscript t)
  (setq font-latex-fontify-script nil))

;;;; ocaml
(use-package tuareg
  :straight t
  :hook
  (tuareg-mode . eglot-ensure)
  (tuareg-mode . eglot-format-on-save)
  (tuareg-mode . utop-minor-mode)
  (tuareg-mode . tuareg-compile-setup)
  (tuareg-menhir-mode . tuareg-compile-setup)
  :init
  (reformatter-define ocp-format
    :program "ocp-indent")
  (defun tuareg-compile-setup ()
    (setq-local compile-command "dune build --profile release"))
  :config
  (setq tuareg-opam-insinuate t)
  (tuareg-opam-update-env (tuareg-opam-current-compiler)))

(use-package reason-mode
  :straight t
  :hook
  (reason-mode . eglot-ensure)
  (reason-mode . reason-utop-setup)
  (reason-mode . reason-format-on-save-mode)
  (reason-mode . reason-compile-setup)
  :init
  (reformatter-define reason-format
    :program "refmt")
  (defun reason-compile-setup ()
    (setq-local compile-command "dune build --profile release"))
  (defun reason-utop-setup ()
    (setq-local utop-command "opam config exec -- rtop -emacs")
    (utop-minor-mode)))

(use-package utop
  :straight t
  :defer t)

(use-package dune
  :straight t
  :hook (dune-mode . dune-format-on-save-mode))

(use-package dune-format
  :straight t
  :defer t)

;;;; coq
(use-package company-coq
  :straight t
  :defer t
  :init
  ;; disable company and use corfu
  (setq company-coq-disabled-features '(company company-defaults))
  (defvar corfu-coq-backend
    (cape-company-to-capf #'company-coq-master-backend))
  (defvar corfu-math-backend
    (cape-company-to-capf #'company-coq-math-symbols-backend))
  (defun corfu-coq-init ()
    (setq-local completion-at-point-functions
                (list corfu-math-backend corfu-coq-backend #'cape-dabbrev)))
  :hook (company-coq-mode . corfu-coq-init))

(use-package proof-general
  :straight t
  :hook (coq-mode . company-coq-mode)
  :init
  (setq proof-splash-enable nil
        proof-three-window-mode-policy 'hybrid))

;;;; lean4
(use-package nael
  :straight
  (nael
   :type git
   :host codeberg
   :repo "mekeor/nael"
   :files ("nael/*.el"))
  :defer t
  :hook
  (nael-mode . eglot-ensure)
  (nael-mode . abbrev-mode)
  (nael-mode . nael-infoview-setup)
  (nael-mode . (lambda () (copilot-mode -1)))
  :config
  ;; Lean "infoview": nael renders proof goals through ElDoc.  Render them into
  ;; our own *lean-infoview* buffer (which popper does not match) and lock it to
  ;; a window on the right, like Proof General's goals panel, so it stays
  ;; independent of popper and coexists with popups such as the terminal.
  ;;
  ;; ElDoc dispatches its display from an async timer where `current-buffer' is
  ;; not the Lean buffer, which defeats buffer-local hooks and source-buffer
  ;; routing.  The *selected window*, however, still shows the Lean buffer, so
  ;; we advise `eldoc-display-in-buffer' (what actually renders the docs) and,
  ;; whenever the selected window holds a Lean buffer, redirect everything
  ;; (goals, term goals, hover/expected-type) to the infoview; otherwise the
  ;; original runs unchanged for other modes.
  (defconst nael-infoview-buffer-name "*lean-infoview*"
    "Name of the dedicated Lean infoview buffer.")

  (defun nael-infoview--buffer ()
    "Return the infoview buffer, creating it in `special-mode' if needed."
    (let ((buffer (get-buffer-create nael-infoview-buffer-name)))
      (with-current-buffer buffer
        (unless (derived-mode-p 'special-mode) (special-mode)))
      buffer))

  (defun nael-infoview--render (docs)
    "Render ElDoc DOCS into the infoview buffer; return the buffer.
Each element of DOCS is a (STRING . PLIST) pair; the strings are already
fontified by nael."
    (let ((buffer (nael-infoview--buffer)))
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (setq-local nobreak-char-display nil)
          (erase-buffer)
          (cl-loop for (item . rest) on docs
                   do (insert (car item))
                   when rest do (insert "\n\n"))
          (goto-char (point-min))))
      buffer))

  (defun nael-infoview-show (&optional window)
    "Pop up the Lean infoview to the right of WINDOW without changing its contents.
WINDOW defaults to the selected window; it anchors the
`display-buffer-in-direction' split (see `display-buffer-alist' below)."
    (interactive)
    (display-buffer (nael-infoview--buffer)
                    (and window `(nil (window . ,window)))))

  (defun nael--in-lean-window-p ()
    "Non-nil when the selected window is showing a Lean buffer."
    (with-current-buffer (window-buffer (selected-window))
      (derived-mode-p 'nael-mode)))

  (defun nael-eldoc-display-advice (orig-fn docs &rest args)
    "Redirect ElDoc rendering to the Lean infoview when editing a Lean buffer.
ORIG-FN is `eldoc-display-in-buffer'.  ElDoc renders asynchronously, but the
selected window still shows the Lean buffer at that point, so we key off it:
when it holds a Lean buffer, render DOCS in the *lean-infoview* window
\(re-showing it if hidden); otherwise call ORIG-FN unchanged."
    (if (nael--in-lean-window-p)
        (let ((buffer (nael-infoview--render docs)))
          (unless (get-buffer-window buffer t)
            (display-buffer buffer)))
      (apply orig-fn docs args)))
  (advice-add 'eldoc-display-in-buffer :around #'nael-eldoc-display-advice)

  (defun nael-infoview-setup ()
    "Pop up the Lean infoview when a Lean buffer is opened."
    (let ((source (current-buffer)))
      ;; Defer until after `find-file' has displayed the Lean buffer, so the
      ;; side window is added to the right of it rather than fighting the
      ;; in-progress file display.
      (run-with-timer
       0 nil
       (lambda ()
         ;; Anchor the split on the Lean buffer's window explicitly: by the
         ;; time the timer fires the selected window may be elsewhere.
         (when-let* (((buffer-live-p source))
                     (window (get-buffer-window source t)))
           (nael-infoview-show window))))))

  ;; A normal window in the main area (not a side window): right-side side
  ;; windows with different slots stack vertically, so sharing the side with
  ;; agent-shell could never give [code | infoview | shell].  In-direction
  ;; keeps the infoview glued to the right of the Lean window while
  ;; agent-shell docks at the frame edge beyond it.
  (add-to-list 'display-buffer-alist
               '("\\`\\*lean-infoview\\*\\'"
                 (display-buffer-reuse-window display-buffer-in-direction)
                 (direction . right)
                 (window-width . 0.3)
                 (preserve-size . (t . nil))
                 (dedicated . t)
                 (window-parameters . ((no-delete-other-windows . t)))))

  ;; In Lean buffers, `K' shows our infoview rather than the (now-unused)
  ;; *eldoc* buffer.
  (general-define-key
   :states 'normal :keymaps 'nael-mode-map
   "K" #'nael-infoview-show))

;;;; why3
(use-package why3
  :load-path "~/.opam/default/share/emacs/site-lisp"
  :mode ("\\.mlw$" . why3-mode))

;;;; z3
(use-package z3-mode
  :straight t
  :mode ("\\.smt[2]?$". z3-mode))

;;;; haskell
(use-package haskell-mode
  :straight t
  :hook (haskell-mode . eglot-ensure))

;;;; sml
(use-package sml-mode
  :straight t
  :defer t
  :hook (sml-mode . sml-format-on-save-mode)
  :config
  (reformatter-define sml-format
    :program "smlfmt"
    :args '("--stdio"))
  (setq sml-program-name "poly"))

;;;; ats
(use-package ats2-mode
  :straight
  (ats2-mode
   :type git
   :host github
   :repo "qcfu-bu/ATS2-emacs")
  :defer t
  :hook (ats2-mode . ats2-flymake-setup))

;;;; rust
(use-package rustic
  :straight t
  :defer t
  :init
  (setq rust-mode-treesitter-derive t)
  :config
  (setq rustic-lsp-client 'eglot
        rustic-format-on-save t))

;;;; c/c++
(use-package cc
  :init
  (setq c-default-style "k&r")
  (setq-default c-basic-offset 2)
  :hook
  ((c-mode c++-mode) . eglot-ensure)
  ((c-mode c++-mode) . eglot-format-on-save))

(use-package cmake-mode
  :straight t)

(use-package cmake-integration
  :straight 
  (cmake-integration
   :type git
   :host github
   :repo "darcamo/cmake-integration")
  :defer t
  :commands (cmake-integration-transient))

;;;; python
(use-package python
  :hook (python-mode . eglot-ensure)
  :config
  (setq python-shell-interpreter "python3"))

(use-package yaml-mode
  :straight t
  :defer t)

;;;; miscellaneous
(use-package tll-mode
  :mode ("\\.tll\\'" . tll-mode)
  :hook (tll-mode . prettify-symbols-mode))

(use-package session-type-mode
  :mode ("\\.st\\'" . session-type-mode)
  :hook (session-type-mode . prettify-symbols-mode))

(use-package sf-mode
  :load-path "~/Projects/SF/editor/emacs/"
  :mode ("\\.sf$" . sf-mode))

;;; devops
;;;; docker
(use-package docker
  :straight t
  :defer t)

(use-package dockerfile-mode
  :straight t
  :mode ("Dockerfile\\'" . dockerfile-mode))

;;; keybinds
;;;;; prefixes
;; which-key group labels for each leader prefix.  `:ignore t' makes general
;; register only the which-key description without binding the key, so these
;; never shadow the commands bound under each prefix (verified: `SPC m' stays
;; unbound here and falls through to the mode-local `SPC m ...' bindings).
(spc-leader-def
  "q"   '(:ignore t :which-key "quit")
  "h"   '(:ignore t :which-key "help")
  "a"   '(:ignore t :which-key "ai")
  "e"   '(:ignore t :which-key "editor")
  "f"   '(:ignore t :which-key "files")
  "b"   '(:ignore t :which-key "buffers")
  "w"   '(:ignore t :which-key "windows")
  "F"   '(:ignore t :which-key "frames")
  "p"   '(:ignore t :which-key "projects")
  "B"   '(:ignore t :which-key "bookmarks")
  "TAB" '(:ignore t :which-key "tabs")
  "t"   '(:ignore t :which-key "toggles")
  "g"   '(:ignore t :which-key "git")
  "m"   '(:ignore t :which-key "local"))

;;;;; core
(spc-leader-def
  "SPC" 'execute-extended-command
  "\\" 'toggle-input-method
  "qr" 'restart-emacs
  "qq" 'save-buffers-kill-emacs)

;;;;; help
(spc-leader-def
  "hv" 'describe-variable
  "hf" 'describe-function
  "hF" 'describe-face
  "hs" 'describe-symbol
  "hb" 'embark-bindings
  "ht" 'consult-theme
  "hk" 'describe-key
  "hm" 'describe-mode
  "hi" 'describe-input-method
  "hc" 'consult-flymake)

;;;;; ai
(spc-leader-def
  "ai" 'my/agent-shell-toggle-or-start)

;;;;; editor
(spc-leader-def
  "el" 'goto-line
  "ec" 'goto-char
  "es" 'consult-line
  "er" 'anzu-query-replace
  "ey" 'consult-yank-pop
  "ed" 'eglot-find-declaration
  "ei" 'eglot-find-implementation
  "et" 'eglot-find-typeDefinition
  "eb" 'xref-go-back)

;;;;; files
(spc-leader-def
  "ff" 'find-file
  "fr" 'consult-recent-file
  "fs" 'save-buffer)

;;;;; buffers
(spc-leader-def
  "bb" 'consult-buffer
  "bm" 'consult-imenu
  "bi" 'ibuffer
  "bo" 'mode-line-other-buffer
  "bn" 'evil-next-buffer
  "bp" 'evil-prev-buffer
  "bd" 'kill-current-buffer)

;;;;; windows
(spc-leader-def
  "ws" 'evil-window-split
  "wv" 'evil-window-vsplit
  "wh" 'evil-window-left
  "wj" 'evil-window-down
  "wk" 'evil-window-up
  "wl" 'evil-window-right
  "wp" 'evil-window-prev
  "wn" 'evil-window-next
  "wd" 'evil-window-delete
  "wt" 'transpose-frame)

;;;;; frames
(spc-leader-def
  "Fa" 'make-frame
  "Fo" 'other-frame
  "Fd" 'delete-frame)

;;;;; projects
(spc-leader-def
  "pp" 'project-switch-project
  "pb" 'consult-project-buffer
  "pf" 'project-find-file
  "pd" 'project-find-dir
  "pc" 'project-compile)

;;;;; treemacs
(general-def treemacs-mode-map
  ;; unset keys
  "q" nil
  "p" nil
  ;; projects
  "pa" 'treemacs-add-project-to-workspace
  "pd" 'treemacs-remove-project-from-workspace
  "pr" 'treemacs-rename-project
  "p" '(:ignore t :which-key "project"))

(general-def evil-treemacs-state-map
  ;; unset keys
  "w" nil
  ;; workspaces
  "ws" 'treemacs-switch-workspace
  "wa" 'treemacs-create-workspace
  "wd" 'treemacs-remove-workspace
  "wr" 'treemacs-rename-workspace
  "we" 'treemacs-edit-workspaces
  "w" '(:ignore t :which-key "workspace"))

;;;;; bookmarks
(spc-leader-def
  "Bb" 'consult-bookmark
  "Ba" 'bookmark-set
  "Bd" 'bookmark-delete)

;;;;; tab-bar
(spc-leader-def
  "TAB TAB" 'tab-bar-switch-to-tab
  "TAB a" 'tab-bar-new-tab
  "TAB n" 'tab-bar-switch-to-next-tab
  "TAB p" 'tab-bar-switch-to-prev-tab
  "TAB r" 'tab-bar-switch-to-recent-tab
  "TAB d" 'tab-bar-close-tab)

;;;;; toggles
(spc-leader-def
  "tt" 'popper-toggle
  "tT" 'popper-toggle-type
  "tn" 'popper-cycle
  "tp" 'popper-cycle-backwards
  "tr" 'treemacs
  "tl" 'display-line-numbers-mode
  "tc" 'olivetti-mode)

;;;;; git
(spc-leader-def
  "gg" 'magit
  "gr" 'consult-git-grep)

;;;; local
(general-create-definer spc-local-leader-def
  :states '(normal)
  :keymaps 'override
  :prefix "SPC m")

;;;;; elisp
(spc-local-leader-def
  :keymaps 'emacs-lisp-mode-map
  "e" 'eval-buffer)

;;;;; org
(spc-local-leader-def
  :keymaps 'org-mode-map
  "i" 'org-insert-structure-template
  "l" 'org-insert-link
  "e" 'org-edit-special
  "o" 'org-open-at-point
  "x" 'org-export-dispatch)

;;;;; latex
(spc-local-leader-def
  :keymaps 'LaTeX-mode-map
  "c" 'TeX-command-master
  "e" 'TeX-command-run-all
  "v" 'TeX-view)

;;;;; c/c++
(spc-local-leader-def
  :keymaps '(c-mode-map c++-mode-map)
  "t" 'cmake-integration-transient)

;;;;; rust
(spc-local-leader-def
  :keymaps 'rustic-mode-map
  "c" 'rustic-cargo-build
  "t" '(:ignore t :which-key "+test")
  "ta" 'rustic-cargo-test
  "tt" 'rustic-cargo-current-test)

;;;;; coq
(spc-local-leader-def
  :keymaps 'coq-mode-map
  "." 'proof-goto-point
  "f" 'proof-assert-next-command-interactive
  "b" 'proof-undo-last-successful-command
  "p" '(:ignore t :which-key "+proof")
  "pp" 'proof-process-buffer
  "pr" 'proof-retract-buffer
  "pk" 'proof-shell-exit)

;; ;;;;; lean4
;; (spc-local-leader-def
;;   :keymaps 'lean4-mode-map
;;   "b" 'lean4-lake-build
;;   "t" 'lean4-toggle-info
;;   "r" 'lean4-refresh-file-dependencies
;;   "k" 'quail-show-key)

;;;;; ocaml
(spc-local-leader-def
  :keymaps 'tuareg-mode-map
  "e" 'utop
  "b" 'utop-eval-buffer)

(spc-local-leader-def
  :keymaps 'reason-mode-map
  "e" 'utop
  "b" 'utop-eval-buffer)

;;;;; sml
(spc-local-leader-def
  :keymaps 'sml-mode-map
  "e" 'run-sml
  "b" 'sml-prog-proc-send-buffer)

;;;;; ats
(spc-local-leader-def
  :keymaps 'ats2-mode-map
  "c" 'ats-type-check-buffer)

;;;;; python
(spc-local-leader-def
  :keymaps 'python-mode-map
  "e" 'run-python
  "b" 'python-shell-send-buffer)
