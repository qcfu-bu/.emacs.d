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
(straight-use-package 'use-package)

;;;; gc
(setq gc-cons-threshold (* 128 1024 1024))
(use-package gcmh
  :straight t
  :config
  (setq gcmh-idle-delay 'auto
        gcmh-auto-idle-delay-factor 10
        gcmh-high-cons-threshold (* 128 1024 1024))
  (gcmh-mode 1))

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
(setq delete-by-moving-to-trash t)

;;;; fonts
(set-face-attribute 'default        nil :font "JetBrains Mono-14")
(set-face-attribute 'fixed-pitch    nil :font "JetBrains Mono-14")
(set-face-attribute 'variable-pitch nil :font "JetBrains Mono-14")

;;;; theme
(use-package modus-themes
  :straight t
  :config (load-theme 'modus-operandi t))

;;;; dim-buffer
(use-package dimmer
  :straight t
  :hook (after-init . dimmer-mode))

;;;; modeline
(use-package doom-modeline
  :straight t
  :config
  (setq doom-modeline-bar-width nil
        doom-modeline-buffer-file-name-style 'buffer-name
        doom-modeline-check-simple-format t)
  (doom-modeline-mode t))

;;;; server
(use-package server
  :config (unless (server-running-p) (server-start)))

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
  (setq consult-preview-key nil)
  (add-to-list 'consult-buffer-filter "^\\*"))

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
        evil-escape-excluded-major-modes '(vterm)
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
  (treemacs-follow-mode -1)
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
          "^\\*vterm\\*" vterm-mode
          "^\\*utop\\*$"
          "^\\*haskell\\*$"
          "^\\*poly\\*$"
          "^\\*Python\\*$"))
  (popper-mode 1)
  (popper-echo-mode 1))

;;;; transpose-frame
(use-package transpose-frame
  :straight t)

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

(use-package highlight-indent-guides
  :straight t
  :defer t
  :custom
  (highlight-indent-guides-method 'fill)
  (highlight-indent-guides-bitmap-function
   'highlight-indent-guides--bitmap-line))

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
  :config
  (setq-default fill-column 90))

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

;;;; copilot
(use-package copilot
  :straight t
  :defer t
  :hook (after-init . copilot-setup)
  :bind (:map copilot-completion-map
              ("<tab>" . 'copilot-accept-completion)
              ("C-<tab>" . 'copilot-accept-completion-by-word))
  :init
  (setq copilot-indent-offset-warning-disable t)
  (defun copilot-setup ()
    (add-hook 'prog-mode-hook #'copilot-mode)
    (add-hook 'text-mode-hook #'copilot-mode))
  :config
  (add-to-list 'copilot-indentation-alist '(prog-mode 2))
  (add-to-list 'copilot-indentation-alist '(org-mode 2))
  (add-to-list 'copilot-indentation-alist '(text-mode 2)))

;;;; eldoc
(use-package eldoc
  :general
  (:states 'normal "K" 'eldoc-doc-buffer)
  :config
  (setq eldoc-display-functions '(eldoc-display-in-buffer)))

;;;; eglot
(use-package eglot
  :straight t
  :commands (eglot-ensure)
  :init
  (defun eglot-format-on-save ()
    (add-hook 'before-save-hook 'eglot-format-buffer))
  :config
  (setq eglot-ignored-server-capabilities '(:inlayHintProvider))
  (advice-add 'eglot-completion-at-point :around #'cape-wrap-buster)
  (add-to-list 'eglot-server-programs '((tex-mode context-mode texinfo-mode bibtex-mode) . ("texlab")))
  (add-to-list 'eglot-server-programs '((python-mode python-ts-mode) . ("pyright-langserver" "--stdio")))
  (add-to-list 'eglot-server-programs '((c-mode c-ts-mode c++-mode c++-ts-mode objc-mode) . ("clangd")))
  (add-to-list 'eglot-server-programs '((rust-mode rust-ts-mode) .
                                        ("rust-analyzer" :initializationOptions
                                         ( :procMacro (:enable t)
                                           :cargo ( :buildScripts (:enable t)
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

;;;; profiling
(use-package esup
  :straight t
  :config
  (setq esup-depth 0))

;;; term
;;;; vterm
(use-package vterm
  :straight t
  :defer t
  :hook
  (vterm-mode . (lambda () (setq confirm-kill-processes nil)))
  :config
  (setq vterm-kill-buffer-on-exit t
        vterm-max-scrollback 5000))

(use-package vterm-toggle
  :straight t
  :bind ("C-`" . vterm-toggle)
  :config (setq vterm-toggle-scope 'project))

;;; lang
;;;; markdown
(use-package markdown-mode
  :straight t
  :mode ("/README\\(?:\\.md\\)?\\'" . gfm-mode)
  :hook
  ((markdown-mode . visual-line-mode)
   (markdown-mode . flyspell-mode))
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
   (org-mode . flyspell-mode)
   (org-mode . (lambda ()
                 (modify-syntax-entry ?< "." org-mode-syntax-table)
                 (modify-syntax-entry ?> "." org-mode-syntax-table))))
  :config
  (setq org-startup-indented t
        org-hide-leading-stars t
        org-src-window-setup 'current-window
        org-html-validation-link nil))

(use-package htmlize
  :straight t)

;;;; latex
(use-package auctex
  :straight t
  :hook
  ((LaTeX-mode . eglot-ensure)
   (LaTeX-mode . visual-line-mode)
   (LaTeX-mode . flyspell-mode)
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
  (nael-mode . (lambda () (copilot-mode -1))))

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
(use-package rust-mode
  :straight t
  :hook (rust-mode . eglot-ensure)
  :init
  (setq rust-format-on-save t))

;;;; c/c++
(use-package cc
  :init
  (setq c-default-style "k&r")
  (setq-default c-basic-offset 2)
  :hook
  ((c-mode c++-mode) . eglot-ensure)
  ((c-mode c++-mode) . eglot-format-on-save))

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
  :demand t
  :hook (tll-mode . prettify-symbols-mode))

(use-package session-type-mode
  :demand t
  :hook (session-type-mode . prettify-symbols-mode))

;;; keybinds
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

;;;;; editor
(spc-leader-def
  "el" 'goto-line
  "ec" 'goto-char
  "es" 'consult-line
  "er" 'anzu-query-replace
  "ey" 'consult-yank-pop
  "ed" 'eglot-find-declaration
  "ei" 'eglot-find-implementation
  "et" 'eglot-find-typeDefinition)

;;;;; compile
(spc-leader-def
  "cc" 'compile
  "cr" 'recompile)

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
  "pr" 'treemacs-rename-project)

(general-def evil-treemacs-state-map
  ;; unset keys
  "w" nil
  ;; workspaces
  "ws" 'treemacs-switch-workspace
  "wa" 'treemacs-create-workspace
  "wd" 'treemacs-remove-workspace
  "wr" 'treemacs-rename-workspace
  "we" 'treemacs-edit-workspaces)

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
  "ti" 'highlight-indent-guides-mode
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

;;;;; coq
(spc-local-leader-def
  :keymaps 'coq-mode-map
  "." 'proof-goto-point
  "f" 'proof-assert-next-command-interactive
  "b" 'proof-undo-last-successful-command
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
