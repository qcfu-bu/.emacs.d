;; Raise the GC threshold for the duration of startup so the garbage collector
;; does not fire repeatedly while packages load. `gcmh' (configured in init.el)
;; takes ownership of `gc-cons-threshold' once it activates, so this only covers
;; the small bootstrap window before then.
(setq gc-cons-threshold most-positive-fixnum)

;; Prevent package.el loading packages prior to init-file loading.
(setq package-enable-at-startup nil)
(setq package-quickstart nil)

;; emacs-plus bakes CC=/opt/homebrew/bin/gcc-16 into the app bundle's
;; Info.plist LSEnvironment so native compilation can find the Homebrew GCC
;; toolchain. That variable is inherited by every subprocess (vterm, compile,
;; cargo, ...). GCC on macOS can't emit native Apple TLS, so any cc-crate build
;; (e.g. mimalloc) compiles thread-locals to emulated TLS and then fails to link
;; under rustc's `-nodefaultlibs`. Native compilation only needs LIBRARY_PATH +
;; libgccjit, not CC, so unset CC here to let child builds use clang.
(setenv "CC" nil)

;; Prevent the glimpse of un-styled Emacs by disabling these UI elements early.
(push '(menu-bar-lines . 0)   default-frame-alist)
(push '(tool-bar-lines . 0)   default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

;; Resizing the Emacs frame can be a terribly expensive part of changing the
;; font. By inhibiting this, we easily halve startup times with fonts that are
;; larger than the system default.
(setq frame-inhibit-implied-resize t)

;; Disable GUI elements
(setq menu-bar-mode nil
      tool-bar-mode nil
      scroll-bar-mode nil)
(setq use-file-dialog nil
      use-dialog-box nil)
(setq ring-bell-function 'ignore)

;; Reduce *Message* noise at startup. An empty scratch buffer (or the
;; dashboard) is more than enough, and faster to display.
(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name)
(setq initial-buffer-choice nil
      inhibit-startup-buffer-menu t
      inhibit-x-resources t)

;; Suppress the vanilla startup screen completely. We've disabled it with
;; `inhibit-startup-screen', but it would still initialize anyway.
(advice-add 'display-startup-screen :override #'ignore)

;; The initial buffer is created during startup even in non-interactive
;; sessions, and its major mode is fully initialized. Modes like `text-mode',
;; `org-mode', or even the default `lisp-interaction-mode' load extra packages
;; and run hooks, which can slow down startup.
;;
;; Using `fundamental-mode' for the initial buffer to avoid unnecessary
;; startup overhead.
(setq initial-major-mode 'fundamental-mode)
