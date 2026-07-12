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

;; Open every frame maximized, with no beep and no visible resize.
;;
;; `(fullscreen . maximized)' in `default-frame-alist' (Spacemacs' approach)
;; beeps on macOS: the NS port applies it with -[NSWindow performZoom:]
;; while the window is still being ordered on screen, and AppKit beeps when
;; asked to zoom a window it does not yet consider zoomable. Setting the
;; parameter from a hook once the frame is visible is silent, but shows the
;; default-size frame for a split second before it grows. So instead:
;; create GUI frames invisible, size them to the monitor's work area with
;; plain geometry calls (AppKit zoom is never involved, so nothing can
;; beep), and only then show them — already full-size.
(defun my/frame-fill-workarea (frame)
  "Size FRAME to exactly fill its monitor's work area."
  (let ((wa (frame-monitor-workarea frame)))
    (set-frame-position frame (nth 0 wa) (nth 1 wa))
    (set-frame-size frame
                    (- (nth 2 wa) (- (frame-outer-width frame)
                                     (frame-text-width frame)))
                    (- (nth 3 wa) (- (frame-outer-height frame)
                                     (frame-text-height frame)))
                    t)))

(define-advice make-frame (:around (fn &optional params) my/open-maximized)
  "Create top-level GUI frames invisible, size to work area, then show."
  (if (or (assq 'visibility params)   ; caller manages visibility (corfu, ...)
          (assq 'parent-frame params) ; child frames size themselves
          (assq 'tty params))         ; terminal client frames
      (funcall fn params)
    (let ((frame (funcall fn (cons '(visibility . nil) params))))
      (unwind-protect
          (when (display-graphic-p frame)
            (my/frame-fill-workarea frame))
        (make-frame-visible frame))
      frame)))

;; A plain `emacs' launch creates the initial frame in C, bypassing
;; `make-frame'. That frame is already visible by `window-setup-hook' time,
;; so the silent-but-late maximize is the best available for it.
(add-hook 'window-setup-hook
          (lambda ()
            (when (display-graphic-p)
              (set-frame-parameter nil 'fullscreen 'maximized))))

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
