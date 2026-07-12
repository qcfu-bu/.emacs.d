;;; minimap-frame.el --- Child-frame minimap overlay  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Qiancheng Fu

;; Author: Qiancheng Fu <qf59@cornell.edu>
;; Maintainer: Qiancheng Fu <qf59@cornell.edu>
;; Keywords: convenience
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; A VSCode-style code minimap rendered as a child frame floating over
;; the right edge of the window -- not a side window, so it never
;; interacts with `display-buffer-alist', popper, or window layout.
;;
;; Design (shared with the local yascroll rewrite):
;;
;; * One child frame per tracked window, registered in a window
;;   parameter, positioned in pixel coordinates over the window's right
;;   edge.  Being viewport-fixed, it does not ride with the text under
;;   `pixel-scroll-precision-mode'.
;; * Content is never rendered by hand: the frame's window displays an
;;   *indirect buffer* of the tracked buffer with a buffer-local
;;   `face-remapping-alist' shrinking the default face.  Indirect
;;   buffers share text *and* text properties, so font-lock colors are
;;   inherited live and stay in sync for free.  Overlays are not
;;   shared, which is equally welcome: region highlights, eglot
;;   flashes, and diff-hl marks stay out of the minimap.
;; * The current viewport is a background overlay in the mini buffer
;;   spanning the tracked window's `window-start'..`window-end',
;;   scoped to the mini window via the overlay `window' property.
;; * Scroll sync maps the tracked window's character-position fraction
;;   (the mode line's `%p' arithmetic, hardened in yascroll) onto the
;;   minimap's own displayable span, so large files scroll the minimap
;;   proportionally.
;; * The minimap is purely visual, like the yascroll thumb: its keymap
;;   swallows mouse events everywhere, and on macOS its NSWindow is
;;   additionally set to ignore the mouse entirely, so clicks and
;;   scrolls pass through to the code beneath.
;; * Updates are coalesced through a 0-second timer; per-redisplay work
;;   (viewport overlay, scroll sync) is keyed and cheap, mirroring
;;   yascroll's glide path.
;;
;; Known limitations, accepted for v1:
;;
;; * Display properties are shared along with the text, so inline
;;   images render full-size in the minimap.  Fine for code; enable
;;   selectively for org/markdown.
;; * Pixel-tuned face tricks (indent-bars stipples) do not scale
;;   gracefully at minimap font sizes.
;; * No fade animation: NS applies alpha changes to visible child
;;   frames erratically (the yascroll lesson), and color-blend fades do
;;   not generalize to multicolor content.  The minimap is always-on.
;;
;; Usage:
;;
;;   (require 'minimap-frame)
;;   (global-minimap-frame-mode 1)   ; prog-mode buffers by default

;;; Code:

(require 'cl-lib)

(declare-function yascroll-bar-mode "yascroll")

;;; Customization

(defgroup minimap-frame nil
  "Child-frame code minimap."
  :group 'convenience
  :prefix "minimap-frame-")

(defface minimap-frame-viewport
  '((t :inherit hl-line :extend t))
  "Face of the viewport region in the minimap.
Only the background matters.  `:extend' paints past line ends so the
viewport reads as a solid block."
  :group 'minimap-frame)

(defcustom minimap-frame-width 73
  "Pixel width of the minimap child frame."
  :type 'integer
  :group 'minimap-frame)

(defcustom minimap-frame-scale 0.14
  "Height of the minimap text relative to the buffer's default face.
Applied through a buffer-local `face-remapping-alist' in the indirect
buffer; around 0.10-0.20 gives the classic unreadable-but-shapely
minimap look."
  :type 'number
  :group 'minimap-frame)

(defcustom minimap-frame-text-dim 0.0
  "Fraction to fade minimap text toward the background, 0.0 .. 1.0.
Faces have no opacity, so \"transparent text\" is emulated by
remapping every face's explicit foreground toward the default
background by this fraction, buffer-locally in the mini buffer.  0.0
leaves text at full strength; around 0.2 lowers the minimap's visual
weight without flattening the syntax colors."
  :type 'number
  :group 'minimap-frame)

(defcustom minimap-frame-font-family nil
  "Font family for minimap text, or nil to inherit the buffer's font.
Real glyph shapes read as dense noise at minimap sizes; an abstract
block font such as Minimap <https://github.com/davestewart/minimap-font>
renders each character as a featureless block, giving the clean
VSCode-style look.  Silently ignored when the family is not installed."
  :type '(choice (const :tag "Inherit buffer font" nil)
                 (string :tag "Font family"))
  :group 'minimap-frame)

(defcustom minimap-frame-minimum-window-width 70
  "Do not show a minimap in windows narrower than this many columns.
The minimap floats over the window's text area; in narrow windows it
would cover too much of the code."
  :type 'integer
  :group 'minimap-frame)

(defcustom minimap-frame-max-buffer-size 1000000
  "Do not enable the minimap in buffers larger than this many characters."
  :type 'integer
  :group 'minimap-frame)

(defcustom minimap-frame-fontify-ahead t
  "When non-nil, fontify the region the minimap displays.
jit-lock only fontifies what the tracked window has shown, so without
this, code not yet visited appears colorless in the minimap.  The cost
is bounded by one minimap-full of text per scroll."
  :type 'boolean
  :group 'minimap-frame)

(defcustom minimap-frame-global-modes '(prog-mode)
  "Major modes (with descendants) `global-minimap-frame-mode' enables in."
  :type '(repeat symbol)
  :group 'minimap-frame)

(defvar minimap-frame-debug nil
  "When non-nil, re-signal rendering errors instead of swallowing them.")

;;; Internal state

(defvar minimap-frame-mode)             ; defined by `define-minor-mode' below

(defvar-local minimap-frame--mini-buffer nil
  "The indirect minimap buffer of this base buffer, or nil.")

(defvar-local minimap-frame--update-timer nil
  "Pending coalesced update timer, or nil.")

(defvar-local minimap-frame--line-count nil
  "Cached `count-lines' over the accessible buffer.")

(defvar-local minimap-frame--line-count-key nil
  "Cache key `minimap-frame--line-count' was computed for.")

(defvar minimap-frame--mini-keymap
  (let ((map (make-sparse-keymap)))
    ;; The minimap is an indicator, not a control.  Swallow every mouse
    ;; event that reaches the mini window (none can on macOS, where the
    ;; frame's NSWindow ignores the mouse entirely): default bindings
    ;; like `mouse-drag-region' or mwheel scrolling would otherwise
    ;; select or scroll the mini window.
    (dolist (key '([down-mouse-1] [mouse-1] [drag-mouse-1] [double-mouse-1]
                   [triple-mouse-1] [down-mouse-2] [mouse-2]
                   [down-mouse-3] [mouse-3]
                   [wheel-up] [wheel-down] [wheel-left] [wheel-right]
                   [mouse-4] [mouse-5] [mouse-6] [mouse-7]))
      (define-key map key #'ignore))
    map)
  "Keymap of minimap mini buffers.")

(defmacro minimap-frame--with-no-redisplay (&rest body)
  "Run BODY with redisplay and layout-change hooks inhibited."
  (declare (indent 0) (debug t))
  `(let ((inhibit-redisplay t)
         after-focus-change-function
         buffer-list-update-hook
         display-buffer-alist
         window-configuration-change-hook
         window-size-change-functions
         window-state-change-hook)
     ,@body))

;;; Line count (for span estimates only)

(defun minimap-frame--buffer-line-count ()
  "Number of lines in the accessible buffer, cached by modification tick."
  (let ((key (list (buffer-chars-modified-tick) (point-min) (point-max))))
    (if (equal key minimap-frame--line-count-key)
        minimap-frame--line-count
      (setq minimap-frame--line-count-key key
            minimap-frame--line-count (count-lines (point-min) (point-max))))))

;;; Mini (indirect) buffer

(defun minimap-frame--base-buffer (&optional buffer)
  "The base buffer BUFFER's minimap should track (resolves indirection)."
  (let ((buffer (or buffer (current-buffer))))
    (or (buffer-base-buffer buffer) buffer)))

(defun minimap-frame--blend (from to fraction)
  "Blend color FROM toward color TO by FRACTION (0.0 .. 1.0)."
  (let ((f (color-values from))
        (h (color-values to)))
    (if (and f h)
        (apply #'format "#%04x%04x%04x"
               (cl-mapcar (lambda (a b)
                            (round (+ (* a (- 1.0 fraction)) (* b fraction))))
                          f h))
      from)))

(defun minimap-frame--apply-remaps (mini)
  "Install MINI's buffer-local face remappings: shrink plus optional dim.
The four base faces are remapped to the minimap font and scale
\(faces built on `fixed-pitch'/`variable-pitch' often carry explicit
pixel fonts that a `default' remap alone leaves full-size).  When
`minimap-frame-text-dim' is positive, every face with an explicit
foreground is additionally remapped toward the default background --
the closest Emacs equivalent of lowering text opacity, computed here
and re-computed on theme changes."
  (with-current-buffer mini
    (let ((shrink `(,@(and minimap-frame-font-family
                           (find-font (font-spec
                                       :family minimap-frame-font-family))
                           (list :family minimap-frame-font-family))
                    :height ,minimap-frame-scale))
          (remaps
           (when (> minimap-frame-text-dim 0.0)
             (let ((bg (face-background 'default nil t))
                   entries)
               (dolist (face (face-list))
                 (let ((fg (ignore-errors (face-foreground face nil nil))))
                   (when (and (stringp fg) (stringp bg))
                     (push (list face :foreground
                                 (minimap-frame--blend
                                  fg bg minimap-frame-text-dim))
                           entries))))
               entries))))
      (dolist (base '(default fixed-pitch fixed-pitch-serif variable-pitch))
        (let ((entry (assq base remaps)))
          (if entry
              (setcdr entry (append shrink (cdr entry)))
            (push (cons base shrink) remaps))))
      (setq-local face-remapping-alist remaps))))

(defun minimap-frame--mini-buffer (base)
  "Return BASE's minimap indirect buffer, creating it if needed."
  (with-current-buffer base
    (unless (buffer-live-p minimap-frame--mini-buffer)
      (let ((mini (make-indirect-buffer
                   base
                   (generate-new-buffer-name
                    (format " *minimap: %s*" (buffer-name base))))))
        (minimap-frame--apply-remaps mini)
        (with-current-buffer mini
          ;; Independent buffer-locals: strip chrome.
          (setq-local line-spacing 0
                      mode-line-format nil
                      header-line-format nil
                      cursor-type nil
                      cursor-in-non-selected-windows nil
                      truncate-lines t
                      ;; Never hscroll: long truncated lines must clip
                      ;; at the right edge, VSCode-style, not shift the
                      ;; whole minimap to chase a high-column point.
                      auto-hscroll-mode nil
                      buffer-read-only t)
          ;; Text properties come from the base buffer; running
          ;; font-lock here as well would double the work.
          (font-lock-mode -1)
          ;; Keep sibling packages out of the mini buffer: yascroll
          ;; thumbs on minimap frames were the exact recursion class
          ;; yascroll 1.7.2 fixed for its own bar buffer.
          (when (bound-and-true-p yascroll-bar-mode)
            (yascroll-bar-mode -1))
          (use-local-map minimap-frame--mini-keymap))
        (setq minimap-frame--mini-buffer mini)))
    minimap-frame--mini-buffer))

;;; Child frame

(declare-function ns-do-applescript "nsfns.m" (script))

(defvar minimap-frame--transparency-timer nil
  "Pending coalesced mouse-transparency sweep, or nil.")

(defun minimap-frame--request-mouse-transparency ()
  "Schedule a coalesced `minimap-frame--make-frames-mouse-transparent'.
Deferring keeps the AppleScript engine (not reentrant) out of
frame-creation call stacks; a burst of creations costs one sweep."
  (when (and (fboundp 'ns-do-applescript)
             (not (timerp minimap-frame--transparency-timer)))
    (setq minimap-frame--transparency-timer
          (run-with-timer
           0 nil
           (lambda ()
             (setq minimap-frame--transparency-timer nil)
             (minimap-frame--make-frames-mouse-transparent))))))

(defun minimap-frame--make-frames-mouse-transparent ()
  "Make every minimap frame's NSWindow ignore the mouse (macOS).
Same mechanism as the yascroll thumb: Emacs Lisp exposes neither
`ignoresMouseEvents' nor the style mask, but AppleScriptObjC inside
the Emacs process reaches both.  Afterwards the window server no
longer targets the minimap at all -- clicks, scrolls, and hovers pass
through to the code beneath, and the mouse cannot natively resize the
frame.  Minimap windows are recognized by the explicit
\"minimap-frame\" frame name.  A failure is harmless; the keymap and
the self-healing geometry still contain any interference."
  (when (fboundp 'ns-do-applescript)
    (ignore-errors
      (ns-do-applescript "use framework \"AppKit\"
set theWins to (current application's NSApplication's sharedApplication())'s |windows|()
repeat with i from 1 to ((theWins's |count|()) as integer)
  set w to (theWins's objectAtIndex:(i - 1))
  if ((w's title()) as text) contains \"minimap-frame\" then
    (w's setIgnoresMouseEvents:true)
    set m to (w's styleMask()) as integer
    if (m div 8) mod 2 is 1 then (w's setStyleMask:(m - 8))
  end if
end repeat"))))

(defun minimap-frame--frame (window)
  "Return WINDOW's minimap child frame, creating it invisibly if needed."
  (let ((frame (window-parameter window 'minimap-frame--frame)))
    (unless (frame-live-p frame)
      (let ((frame-inhibit-implied-resize t)
            (after-make-frame-functions nil))
        (setq frame
              (make-frame
               `((parent-frame . ,(window-frame window))
                 (minimap-frame--parent-window . ,window)
                 (name . "minimap-frame")
                 (undecorated . t)
                 (no-accept-focus . t)
                 (no-focus-on-map . t)
                 (no-other-frame . t)
                 (unsplittable . t)
                 (minibuffer . nil)
                 (min-width . 0)
                 (min-height . 0)
                 (width . (text-pixels . ,minimap-frame-width))
                 (height . (text-pixels . 100))
                 (internal-border-width . 0)
                 (child-frame-border-width . 1)
                 (left-fringe . 0)
                 (right-fringe . 0)
                 (vertical-scroll-bars . nil)
                 (horizontal-scroll-bars . nil)
                 (menu-bar-lines . 0)
                 (tool-bar-lines . 0)
                 (tab-bar-lines . 0)
                 (cursor-type . nil)
                 (visibility . nil)
                 (desktop-dont-save . t)))))
      (set-window-parameter window 'minimap-frame--frame frame)
      (minimap-frame--request-mouse-transparency))
    frame))

(defun minimap-frame--sync-frame-buffer (window frame)
  "Make FRAME's window display the mini buffer of WINDOW's buffer."
  (let ((mini (minimap-frame--mini-buffer
               (minimap-frame--base-buffer (window-buffer window))))
        (root (frame-root-window frame)))
    (unless (eq (window-buffer root) mini)
      (set-window-dedicated-p root nil)
      (set-window-buffer root mini)
      (set-window-dedicated-p root t)
      (set-window-fringes root 0 0))
    mini))

;;; Geometry

(defun minimap-frame--realized-geometry (frame)
  "FRAME's realized pixel geometry: (WIDTH HEIGHT POSITION)."
  (list (frame-pixel-width frame)
        (frame-pixel-height frame)
        (frame-position frame)))

(defun minimap-frame--position (window frame)
  "Apply FRAME's geometry over WINDOW's right edge.
Keyed by the derived geometry so repeated calls are free; the realized
geometry is re-asserted when it drifts (macOS makes undecorated frames
natively resizable -- the same self-heal as the yascroll thumb)."
  (let* ((edges (window-inside-pixel-edges window))
         (width minimap-frame-width)
         (height (- (nth 3 edges) (nth 1 edges)))
         (x (- (nth 2 edges) width))
         (y (nth 1 edges))
         (key (list x y width height)))
    (unless (and (equal key (window-parameter window
                                              'minimap-frame--geometry))
                 (equal (cdr (frame-parameter frame
                                              'minimap-frame--applied-geometry))
                        (minimap-frame--realized-geometry frame)))
      (set-window-parameter window 'minimap-frame--geometry key)
      (let ((frame-resize-pixelwise t))
        (set-frame-size frame width height t)
        (set-frame-position frame x y))
      (let ((record (frame-parameter frame 'minimap-frame--applied-geometry)))
        (unless (equal key (car record))
          (set-frame-parameter
           frame 'minimap-frame--applied-geometry
           (cons key (minimap-frame--realized-geometry frame))))))))

;;; Content sync

(defun minimap-frame--track-fraction (window)
  "WINDOW's scroll position as a fraction 0.0 .. 1.0.
Character-based with Top/Bot snaps, and WINDOW's sub-line pixel
vscroll folded in via the window's character density -- the same
arithmetic as the yascroll thumb, so the minimap glides through
`pixel-scroll-precision-mode' animation instead of stepping once per
line."
  (with-current-buffer (window-buffer window)
    (let* ((total (- (point-max) (point-min)))
           (start (window-start window))
           (end (min (or (window-end window) (point-max)) (point-max)))
           (visible (max 0 (- end start)))
           (vscroll (window-vscroll window t)))
      (cond ((>= end (point-max)) 1.0)
            ((and (<= start (point-min)) (zerop vscroll)) 0.0)
            (t
             (let ((scrollable (max 1 (- total visible)))
                   (vscroll-chars
                    (* visible
                       (/ vscroll
                          (float (max 1 (window-body-height window t)))))))
               (min 1.0 (max 0.0 (/ (+ (- start (point-min)) vscroll-chars)
                                    (float scrollable))))))))))

(defvar-local minimap-frame--row-height nil
  "Cached plain-row pixel height of this mini buffer, or nil.")

(defun minimap-frame--mini-line-height (mini-window frame)
  "Base pixel height of one minimap row in MINI-WINDOW.
Measured as the MINIMUM over a sample of laid-out rows and cached in
the mini buffer: rows whose glyphs fall back to non-minimap fonts
(math symbols, subscripts) realize taller than plain rows, and
re-measuring whatever row sat at `window-start' made every scroll
quantity oscillate as tall rows crossed the top edge.  The minimum of
a sample is the plain row height, which is a font metric, not
content, so the cache never needs invalidating.  Falls back to
scaling the parent frame's char height before the first layout.
\(`window-default-line-height' is unusable here: it ignores face
remapping and reports the full-size font.)"
  (with-current-buffer (window-buffer mini-window)
    (or minimap-frame--row-height
        (let (min-height)
          (save-excursion
            (goto-char (point-min))
            (let ((prev (point)))
              (dotimes (_ 20)
                (forward-line 1)
                (when (> (point) prev)
                  (when-let* ((size (ignore-errors
                                      (window-text-pixel-size
                                       mini-window prev (point))))
                              (height (cdr size))
                              ((> height 0)))
                    (setq min-height (if min-height
                                         (min min-height height)
                                       height)))
                  (setq prev (point))))))
          (setq minimap-frame--row-height min-height))
        (max 1 (round (* (frame-char-height (frame-parent frame))
                         minimap-frame-scale))))))

(defun minimap-frame--sync-content (window frame)
  "Sync FRAME's minimap content with WINDOW: viewport overlay and scroll.
Keyed on WINDOW's scroll state so per-redisplay calls are free while
nothing moved."
  (let* ((base (minimap-frame--base-buffer (window-buffer window)))
         (mini (minimap-frame--sync-frame-buffer window frame))
         (mini-window (frame-root-window frame)))
    (with-current-buffer base
      (let* ((start (window-start window))
             (end (min (or (window-end window) (point-max)) (point-max)))
             (end (max end start))
             ;; MINI identifies the buffer: without it, two buffers
             ;; with coincidentally equal scroll state (fresh files of
             ;; similar size) collide and the swap is skipped.  The
             ;; tracked vscroll must be in the key or pixel-scroll
             ;; animation frames are skipped and the minimap stutters.
             (key (list mini start end (window-vscroll window t)
                        (buffer-chars-modified-tick)
                        (point-min) (point-max)
                        (frame-pixel-height frame))))
        (unless (equal key (window-parameter window
                                             'minimap-frame--content-key))
          (set-window-parameter window 'minimap-frame--content-key key)
          ;; Viewport overlay, scoped to this frame's window.
          (let ((overlay (window-parameter window
                                           'minimap-frame--viewport-overlay)))
            (unless (and (overlayp overlay)
                         (eq (overlay-buffer overlay) mini))
              ;; Delete, don't abandon: an overlay left in the previous
              ;; buffer's mini becomes a ghost viewport when this
              ;; window shows that buffer again.
              (when (overlayp overlay)
                (delete-overlay overlay))
              (setq overlay (make-overlay start end mini))
              (overlay-put overlay 'face 'minimap-frame-viewport)
              (overlay-put overlay 'window mini-window)
              (set-window-parameter window 'minimap-frame--viewport-overlay
                                    overlay))
            (move-overlay overlay start end mini))
          ;; Proportional scroll computed in row space END TO END, with
          ;; sub-row pixel glide.  The mini buffer truncates, so
          ;; physical lines map 1:1 onto minimap rows.  Nothing here
          ;; measures the visible character span: files with huge
          ;; single lines (multi-window-full table rows) made any
          ;; char-fraction denominator balloon and collapse as those
          ;; lines crossed the viewport, oscillating the target by
          ;; dozens of rows.  Row position is stable by construction:
          ;; rows above `window-start' plus smooth within-line
          ;; progress (which also glides while a wrapped monster line
          ;; crawls past).  The scale factor uses the window's stable
          ;; screen-line height as the page estimate; the visibility
          ;; clamps below keep the tracked region on the minimap and
          ;; land the ends flush.
          (let* ((rows (minimap-frame--buffer-line-count))
                 (line-height (minimap-frame--mini-line-height
                               mini-window frame))
                 (mini-rows (/ (frame-pixel-height frame)
                               (float line-height)))
                 (scrollable (max 0.0 (- rows mini-rows)))
                 (bol (save-excursion (goto-char start)
                                      (line-beginning-position)))
                 (line-chars (max 1 (- (save-excursion (goto-char start)
                                                       (line-end-position))
                                       bol)))
                 (vscroll (window-vscroll window t))
                 (body-height (max 1 (window-body-height window t)))
                 ;; Sub-line pixels -> chars via typical line width;
                 ;; only smooths within-row progress, so a rough
                 ;; estimate is fine.
                 (vscroll-chars (* (window-body-width window)
                                   (/ vscroll (float body-height))))
                 (row (+ (count-lines (point-min) bol)
                         (min 0.999 (/ (+ (- start bol) vscroll-chars)
                                       (float line-chars)))))
                 (page (count-lines start end))
                 (page-estimate (max 1 (window-body-height window)))
                 (target (* row (/ scrollable
                                   (max 1.0 (- rows page-estimate)))))
                 ;; Visibility clamps: the viewport region must be on
                 ;; the minimap screen.  At buffer end row + page
                 ;; reaches ROWS, so the lower clamp lands the scroll
                 ;; flush at the bottom exactly.
                 (target (min target row scrollable))
                 (target (max target (- (+ row page) mini-rows) 0.0))
                 (whole (floor target))
                 (subpixels (round (* (- target whole) line-height)))
                 (pos (save-excursion
                        (goto-char (point-min))
                        (forward-line whole)
                        (point))))
            (set-window-start mini-window pos)
            (set-window-vscroll mini-window subpixels t)
            ;; Keep the mini window's point inside the displayed
            ;; region (on the viewport), or the next redisplay
            ;; recenters around it and undoes the scroll.  Snap it to a
            ;; line beginning: under `visual-line-mode' the tracked
            ;; `window-start' can sit mid-line at a huge column, which
            ;; would otherwise hscroll the minimap to the line's tail.
            (set-window-point mini-window
                              (save-excursion
                                (goto-char (min (max start pos)
                                                (point-max)))
                                (line-beginning-position)))
            (set-window-hscroll mini-window 0)
            ;; The minimap displays regions the tracked window may
            ;; never have shown; fontify them or they stay colorless.
            (when (and minimap-frame-fontify-ahead
                       (bound-and-true-p jit-lock-mode))
              (ignore-errors
                (jit-lock-fontify-now
                 pos
                 (save-excursion
                   (goto-char pos)
                   (forward-line (ceiling mini-rows))
                   (point)))))))))))

;;; Eligibility

(defun minimap-frame--utility-frame-p (frame)
  "Non-nil when FRAME is a minimap or other package's utility child frame."
  (or (frame-parameter frame 'minimap-frame--parent-window)
      (frame-parameter frame 'yascroll--parent-window)))

(defun minimap-frame--window-eligible-p (window)
  "Non-nil when WINDOW should carry a minimap."
  (and (window-live-p window)
       (not (window-minibuffer-p window))
       (display-graphic-p (window-frame window))
       (not (minimap-frame--utility-frame-p (window-frame window)))
       (buffer-local-value 'minimap-frame-mode (window-buffer window))
       (>= (window-body-width window) minimap-frame-minimum-window-width)))

;;; Show / hide / update

(defun minimap-frame--hide (window)
  "Hide WINDOW's minimap frame if it is visible."
  (let ((frame (window-parameter window 'minimap-frame--frame)))
    (when (and (frame-live-p frame) (frame-visible-p frame))
      (make-frame-invisible frame))))

(defun minimap-frame--delete (window)
  "Delete WINDOW's minimap frame entirely."
  (let ((frame (window-parameter window 'minimap-frame--frame))
        (overlay (window-parameter window 'minimap-frame--viewport-overlay)))
    (when (overlayp overlay)
      (delete-overlay overlay))
    (set-window-parameter window 'minimap-frame--viewport-overlay nil)
    (set-window-parameter window 'minimap-frame--frame nil)
    (set-window-parameter window 'minimap-frame--geometry nil)
    (set-window-parameter window 'minimap-frame--content-key nil)
    (when (frame-live-p frame)
      (delete-frame frame t))))

(defun minimap-frame--cleanup-frames ()
  "Delete minimap frames whose parent window is gone."
  (dolist (frame (frame-list))
    (let ((window (frame-parameter frame 'minimap-frame--parent-window)))
      (when (and window (not (window-live-p window)))
        (delete-frame frame t)))))

(defun minimap-frame--update-window (window)
  "Show, place, and sync WINDOW's minimap, or hide it if ineligible."
  (if (not (minimap-frame--window-eligible-p window))
      (minimap-frame--hide window)
    (let ((frame (minimap-frame--frame window)))
      (minimap-frame--position window frame)
      (minimap-frame--sync-content window frame)
      (unless (frame-visible-p frame)
        (make-frame-visible frame)))))

(defun minimap-frame--update-buffer (buffer)
  "Re-render the minimaps of every window showing BUFFER."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq minimap-frame--update-timer nil)
      (minimap-frame--with-no-redisplay
        (condition-case err
            (progn
              (minimap-frame--cleanup-frames)
              (dolist (window (get-buffer-window-list buffer nil t))
                (minimap-frame--update-window window)))
          (error
           (if minimap-frame-debug
               (signal (car err) (cdr err))
             (message "minimap-frame: %S" err))))))))

(defun minimap-frame--request-update (&optional buffer)
  "Schedule a coalesced minimap update for BUFFER."
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (unless minimap-frame--update-timer
          (setq minimap-frame--update-timer
                (run-with-timer 0 nil #'minimap-frame--update-buffer
                                buffer)))))))

;;; Hooks

(defun minimap-frame--pre-redisplay (window)
  "Cheap per-redisplay sync of WINDOW's visible minimap.
Frame creation, visibility, and geometry stay in the deferred path;
this only moves the viewport overlay and minimap scroll, both keyed."
  (when (windowp window)
    (let ((frame (window-parameter window 'minimap-frame--frame)))
      (when (and (frame-live-p frame) (frame-visible-p frame))
        (if minimap-frame-debug
            (minimap-frame--sync-content window frame)
          (ignore-errors (minimap-frame--sync-content window frame)))))))

(defun minimap-frame--after-change (&rest _)
  "Refresh minimaps after a buffer modification."
  (minimap-frame--request-update))

(defun minimap-frame--after-window-scroll (window _start)
  "Schedule an update after WINDOW scrolls (runs during redisplay)."
  (minimap-frame--request-update (window-buffer window)))

(defun minimap-frame--after-window-configuration-change ()
  "Reconcile minimap frames after a layout change."
  (minimap-frame--request-update))

(defun minimap-frame--on-window-buffer-change (frame-or-window)
  "Hide minimaps of windows that stopped showing enabled buffers."
  (dolist (window (if (windowp frame-or-window)
                      (list frame-or-window)
                    (window-list frame-or-window 'nomini)))
    (if (minimap-frame--window-eligible-p window)
        (minimap-frame--request-update (window-buffer window))
      (minimap-frame--hide window))))

(defun minimap-frame--on-frame-size-change (frame)
  "Re-assert geometry when a minimap FRAME is externally resized."
  (when (framep frame)
    (let ((window (frame-parameter frame 'minimap-frame--parent-window)))
      (when (and (window-live-p window) (frame-visible-p frame))
        (if minimap-frame-debug
            (minimap-frame--position window frame)
          (ignore-errors (minimap-frame--position window frame)))))))

(defun minimap-frame--on-kill-buffer ()
  "Delete this buffer's minimap frames before the buffer dies.
Killing the base buffer auto-kills the indirect mini buffer, but the
child frames would survive parked on live windows; the buffer-change
hook only hides them, so delete them here."
  (dolist (window (get-buffer-window-list (current-buffer) nil t))
    (minimap-frame--delete window)))

(defun minimap-frame--on-theme-change (_theme)
  "Refresh minimap frame backgrounds and dim remaps after a theme change."
  (dolist (frame (frame-list))
    (when (frame-parameter frame 'minimap-frame--parent-window)
      (set-frame-parameter frame 'background-color
                           (face-background 'default nil t))
      (let ((mini (window-buffer (frame-root-window frame))))
        (when (buffer-live-p mini)
          (minimap-frame--apply-remaps mini))))))

;;; Minor modes

(defun minimap-frame--any-buffer-enabled-p ()
  "Return non-nil when some live buffer has `minimap-frame-mode' on."
  (cl-some (lambda (buffer)
             (buffer-local-value 'minimap-frame-mode buffer))
           (buffer-list)))

;;;###autoload
(define-minor-mode minimap-frame-mode
  "Toggle a child-frame minimap for this buffer."
  :group 'minimap-frame
  (cond
   ;; Refuse in indirect buffers: their base carries the minimap.
   ((and minimap-frame-mode (buffer-base-buffer))
    (setq minimap-frame-mode nil)
    (message "minimap-frame: enable in the base buffer instead"))
   (minimap-frame-mode
    (add-hook 'after-change-functions #'minimap-frame--after-change nil t)
    (add-hook 'window-scroll-functions
              #'minimap-frame--after-window-scroll nil t)
    (add-hook 'pre-redisplay-functions #'minimap-frame--pre-redisplay nil t)
    (add-hook 'window-configuration-change-hook
              #'minimap-frame--after-window-configuration-change nil t)
    (add-hook 'kill-buffer-hook #'minimap-frame--on-kill-buffer nil t)
    (add-hook 'window-buffer-change-functions
              #'minimap-frame--on-window-buffer-change)
    (add-hook 'window-size-change-functions
              #'minimap-frame--on-frame-size-change)
    (when (boundp 'enable-theme-functions)
      (add-hook 'enable-theme-functions #'minimap-frame--on-theme-change))
    (minimap-frame--request-update))
   (t
    (when (timerp minimap-frame--update-timer)
      (cancel-timer minimap-frame--update-timer))
    (setq minimap-frame--update-timer nil)
    ;; Quiet teardown: frame deletion fires buffer-list/window hooks,
    ;; and third-party reactions mid `global-minimap-frame-mode' sweep
    ;; can kill buffers out of the sweep's buffer-list snapshot.
    (minimap-frame--with-no-redisplay
      (dolist (window (get-buffer-window-list (current-buffer) nil t))
        (minimap-frame--delete window)))
    (when (buffer-live-p minimap-frame--mini-buffer)
      ;; Deferred: `global-minimap-frame-mode' disables by sweeping a
      ;; snapshot of `buffer-list', and killing the mini buffer here
      ;; would hand the rest of that sweep a dead buffer.
      (run-with-timer 0 nil
                      (lambda (mini)
                        (when (buffer-live-p mini)
                          (kill-buffer mini)))
                      minimap-frame--mini-buffer))
    (setq minimap-frame--mini-buffer nil)
    (remove-hook 'after-change-functions #'minimap-frame--after-change t)
    (remove-hook 'window-scroll-functions
                 #'minimap-frame--after-window-scroll t)
    (remove-hook 'pre-redisplay-functions #'minimap-frame--pre-redisplay t)
    (remove-hook 'window-configuration-change-hook
                 #'minimap-frame--after-window-configuration-change t)
    (remove-hook 'kill-buffer-hook #'minimap-frame--on-kill-buffer t)
    (unless (minimap-frame--any-buffer-enabled-p)
      ;; Last enabled buffer: sweep frames parked on windows now
      ;; showing other buffers, then drop the global hooks.
      (minimap-frame--with-no-redisplay
        (dolist (frame (frame-list))
          (when (frame-parameter frame 'minimap-frame--parent-window)
            (delete-frame frame t))))
      (remove-hook 'window-buffer-change-functions
                   #'minimap-frame--on-window-buffer-change)
      (remove-hook 'window-size-change-functions
                   #'minimap-frame--on-frame-size-change)
      (when (boundp 'enable-theme-functions)
        (remove-hook 'enable-theme-functions
                     #'minimap-frame--on-theme-change))))))

(defun minimap-frame--enabled-buffer-p (buffer)
  "Return non-nil when the global mode should enable in BUFFER."
  (with-current-buffer buffer
    (and (not (minibufferp))
         (not (buffer-base-buffer))
         (apply #'derived-mode-p minimap-frame-global-modes)
         (<= (buffer-size) minimap-frame-max-buffer-size))))

(defun minimap-frame--turn-on ()
  "Turn on `minimap-frame-mode' where appropriate."
  (when (minimap-frame--enabled-buffer-p (current-buffer))
    (minimap-frame-mode 1)))

;;;###autoload
(define-minor-mode global-minimap-frame-mode
  "Toggle `minimap-frame-mode' in all eligible buffers.
Hand-rolled rather than `define-globalized-minor-mode': the generated
global mode sweeps a `buffer-list' snapshot with no liveness check,
and background process filters (LSP servers, copilot) can kill
transient buffers out of that snapshot mid-sweep, crashing the toggle
with \"Selecting deleted buffer\".  This sweep skips dead buffers."
  :global t
  :group 'minimap-frame
  (if global-minimap-frame-mode
      (progn
        (add-hook 'after-change-major-mode-hook #'minimap-frame--turn-on)
        (dolist (buffer (buffer-list))
          (when (buffer-live-p buffer)
            (with-current-buffer buffer
              (minimap-frame--turn-on)))))
    (remove-hook 'after-change-major-mode-hook #'minimap-frame--turn-on)
    (dolist (buffer (buffer-list))
      (when (buffer-live-p buffer)
        (with-current-buffer buffer
          (when minimap-frame-mode
            (minimap-frame-mode -1)))))))

(provide 'minimap-frame)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; minimap-frame.el ends here
