;; Prevent package.el loading packages prior to init-file loading.
(setq package-enable-at-startup nil)
(setq package-quickstart nil)

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
(setq inhibit-splash-screen t)
(setq use-file-dialog nil)
(setq ring-bell-function 'ignore)
(setq-default frame-title-format "GNU Emacs")
