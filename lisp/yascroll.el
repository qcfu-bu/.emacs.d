;;; yascroll.el --- Yet Another Scroll Bar Mode (modernized)  -*- lexical-binding: t; -*-

;; Copyright (C) 2011-2015 Tomohiro Matsuyama <m2ym.pub@gmail.com>
;; Copyright (C) 2020-2026 Shen, Jen-Chieh <jcs090218@gmail.com>
;; Copyright (C) 2026 Qiancheng Fu <qf59@cornell.edu>

;; Author: Tomohiro Matsuyama <m2ym.pub@gmail.com>
;; Maintainer: Qiancheng Fu <qf59@cornell.edu>
;; Keywords: convenience
;; Version: 1.8.0
;; Package-Requires: ((emacs "27.1"))
;; URL: https://github.com/emacsorphanage/yascroll

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

;; A modernized, robust rewrite of Tomohiro Matsuyama's `yascroll'.
;;
;; It shows a non-intrusive scroll bar "thumb" that appears on scroll and
;; (optionally) auto-hides while idle.  The thumb is purely visual: it is
;; an indicator, not a control, and does not respond to the mouse.
;;
;; Render targets, in the order you should prefer them:
;;
;; * `child-frame' (GUI only) -- a small undecorated child frame at the
;;   window's right edge, positioned in pixel coordinates.  Because it is
;;   fixed to the viewport rather than anchored to buffer text, it never
;;   rides along with the text during `pixel-scroll-precision-mode'
;;   animation the way overlay-based thumbs do, and it is repositioned
;;   from `pre-redisplay-functions' with sub-line vscroll folded in, so
;;   it glides pixel-smoothly with every rendered frame.  It occupies no
;;   fringe, margin, or text space, so it cannot conflict with diff-hl,
;;   flymake, or similar fringe packages.
;; * `right-margin' -- a 1-column reserved right window margin (tty-safe).
;; * `right-fringe' / `left-fringe' -- classic fringe bitmap thumb.
;;   Fringe candidates are auto-skipped when another package (e.g.
;;   diff-hl) owns that fringe; see `yascroll-fringe-occupied-functions'.
;; * `text-area' -- rightmost text column.
;;
;; The overlay-based targets (margin/fringe/text-area) are anchored to
;; buffer text, so during pixel-precision scrolling they visibly drift with
;; the text between updates.  Use `child-frame' on graphical displays.
;;
;; Other differences from the original:
;;
;; * Scroll/change hooks never mutate display state during redisplay; they
;;   schedule a coalescing 0-second timer, and a render-state signature
;;   skips redundant redraws during scroll event floods.
;; * The buffer line count is cached and invalidated by the modification
;;   tick, so scrolling large buffers does not re-count lines every event.
;; * `line-spacing'-aware, pixel-based window-height measurement.
;; * Theme-adaptive faces (light/dark) and a slim centered fringe bitmap.
;; * Naming modernized to dashes, `lexical-binding', Emacs 27.1+.
;; * A transient rendering error hides the bar instead of tearing the whole
;;   minor mode down.
;; * The child-frame thumb is translucent (`yascroll-child-frame-alpha'),
;;   faintly showing the text beneath it like a native overlay scroll bar.
;; * On macOS the child-frame thumb is mouse-transparent: its NSWindow is
;;   set to ignore mouse events (via in-process AppleScriptObjC, since no
;;   frame parameter reaches that switch), so it cannot be clicked,
;;   hovered, or resized, and clicks pass through to the text beneath.
;;   As a fallback the thumb also self-heals: macOS makes undecorated
;;   frames natively mouse-resizable, so any externally imposed resize or
;;   move snaps back on the next redisplay.
;;
;; Usage:
;;
;;   (global-yascroll-bar-mode 1)
;;   M-x customize-group RET yascroll RET

;;; Code:

(require 'cl-lib)

;;; Customization

(defgroup yascroll nil
  "Yet Another Scroll Bar Mode."
  :group 'convenience
  :prefix "yascroll-")

(defface yascroll-thumb-text-area
  '((((background dark))  :background "gray55")
    (((background light)) :background "gray70")
    (t :background "slateblue"))
  "Face for the text-area scroll bar thumb."
  :group 'yascroll)

(defface yascroll-thumb-fringe
  '((((background dark))  :foreground "gray55" :background "gray55")
    (((background light)) :foreground "gray70" :background "gray70")
    (t :foreground "slateblue" :background "slateblue"))
  "Face for the fringe scroll bar thumb.
For a fringe bitmap the foreground is what actually gets drawn."
  :group 'yascroll)

(defface yascroll-thumb-margin
  '((((background dark))  :background "gray55")
    (((background light)) :background "gray70")
    (t :background "slateblue"))
  "Face for the margin scroll bar thumb.
Only the background matters: the thumb is drawn as a plain space so
that no font-fallback glyph can change the pixel height of its rows
\(a taller row breaks `pixel-scroll-precision-mode' arithmetic)."
  :group 'yascroll)

(defface yascroll-thumb-child-frame
  '((((background dark))  :background "gray55")
    (((background light)) :background "gray70")
    (t :background "slateblue"))
  "Face whose background colors the child-frame scroll bar thumb."
  :group 'yascroll)

(defcustom yascroll-scroll-bar
  '(child-frame right-fringe left-fringe text-area)
  "Where to render the scroll bar.

Each candidate is one of `child-frame', `right-margin',
`right-fringe', `left-fringe' or `text-area'; see the Commentary for
what each looks like.  The value may be a single symbol or a list.
When it is a list, the first candidate usable in the current window is
used: `child-frame' needs a graphical display, fringes must have
non-zero width and not be claimed by another package (see
`yascroll-fringe-occupied-functions'), and `right-margin' needs its
reserved margin column."
  :type '(repeat (choice (const :tag "Child Frame" child-frame)
                         (const :tag "Right Margin" right-margin)
                         (const :tag "Right Fringe" right-fringe)
                         (const :tag "Left Fringe" left-fringe)
                         (const :tag "Text Area" text-area)))
  :group 'yascroll)

(defcustom yascroll-delay-to-hide 0.5
  "Idle seconds before the scroll bar auto-hides.
Nil means never hide the scroll bar.  A child-frame thumb fades out
over `yascroll-fade-duration' when hiding."
  :type '(choice (const :tag "Never Hide" nil)
                 (number :tag "Seconds"))
  :group 'yascroll)

(defcustom yascroll-fade-duration 0.2
  "Seconds the child-frame thumb takes to fade out when auto-hiding.
Nil (or 0) hides instantly.  Only the child-frame render target can
fade (frame alpha animation); overlay-based thumbs hide instantly.
Hides triggered by buffer edits or disabling the mode are always
instant."
  :type '(choice (const :tag "Instant" nil)
                 (number :tag "Seconds"))
  :group 'yascroll)

(defcustom yascroll-priority 20
  "Overlay/fringe display priority of the thumb."
  :type 'integer
  :group 'yascroll)

(defcustom yascroll-child-frame-width 6
  "Requested pixel width of the child-frame thumb.
Emacs clamps a frame to at least one character column of its font, so
the realized width can be larger (about 8px with a typical 14pt
monospace font); the thumb is aligned using its realized width."
  :type 'integer
  :group 'yascroll)

(defcustom yascroll-child-frame-min-height 16
  "Minimum pixel height of the child-frame thumb."
  :type 'integer
  :group 'yascroll)

(defcustom yascroll-child-frame-alpha 0.8
  "Opacity of the child-frame thumb, 0.0 (invisible) to 1.0 (opaque).
The thumb is a real window, so anything below 1.0 faintly shows the
text beneath it.  Nil means fully opaque.  Applied when a thumb frame
is created; a live change takes effect on frames created afterwards.

The auto-hide fade still animates the thumb's background color rather
than this parameter: *changing* the alpha of an already-visible NS
child frame renders erratically (see the Fade-out section), but a
constant alpha is applied reliably every time the frame is shown."
  :type '(choice (const :tag "Opaque" nil)
                 (number :tag "Opacity (0.0 - 1.0)"))
  :group 'yascroll)

(defcustom yascroll-thumb-fringe-bitmap 'yascroll-thumb
  "Fringe bitmap used to draw the thumb.
Use `filled-rectangle' for the classic full-width look."
  :type 'symbol
  :group 'yascroll)

(defcustom yascroll-thumb-margin-string " "
  "String drawn in the margin for each line of the thumb.
Keep this a plain space colored by `yascroll-thumb-margin': glyphs
like ▐ can come from a fallback font with taller metrics, which makes
thumb rows taller and breaks `pixel-scroll-precision-mode'."
  :type 'string
  :group 'yascroll)

(defcustom yascroll-fringe-occupied-functions
  '(yascroll--diff-hl-occupies-fringe-p)
  "Predicates deciding whether another package owns a fringe.
Each function is called with `left-fringe' or `right-fringe' in the
buffer being rendered; if any returns non-nil, yascroll skips that
fringe candidate so it does not overwrite the other package's
indicators (a fringe shows only one bitmap per line per side)."
  :type '(repeat function)
  :group 'yascroll)

(defcustom yascroll-enabled-window-systems '(nil x w32 ns pc mac pgtk)
  "Window systems on which yascroll is allowed to render."
  :type '(repeat (choice (const :tag "Termcap" nil)
                         (const :tag "X window" x)
                         (const :tag "MS-Windows" w32)
                         (const :tag "Macintosh Cocoa" ns)
                         (const :tag "Macintosh Emacs Port" mac)
                         (const :tag "MS-DOS" pc)
                         (const :tag "Pure GTK3 Emacs Fork" pgtk)))
  :group 'yascroll)

(defcustom yascroll-disabled-modes '(image-mode)
  "Major modes in which yascroll must not turn on."
  :type '(repeat symbol)
  :group 'yascroll)

;;; Fringe bitmap

;; A slim, centered vertical bar.  The vector is tall so that a single
;; identical row fills any line height once clipped to the line.
(when (fboundp 'define-fringe-bitmap)
  (define-fringe-bitmap 'yascroll-thumb
    (make-vector 64 #b00111100)
    nil 8 'center))

;;; Internal state

(defvar yascroll-bar-mode)              ; defined by `define-minor-mode' below

(defvar-local yascroll--thumb-overlays nil
  "Overlays that make up the currently displayed thumb.")

(defvar-local yascroll--delay-timer nil
  "Idle timer scheduled to hide the thumb.")

(defvar-local yascroll--update-timer nil
  "Pending coalesced re-render timer, or nil.")

(defvar-local yascroll--fade-timer nil
  "Running fade-out animation timer, or nil.")

(defvar-local yascroll--render-state nil
  "Signature of the last render, used to skip redundant redraws.")

(defvar-local yascroll--line-count nil
  "Cached result of `count-lines' over the accessible buffer.")

(defvar-local yascroll--line-count-key nil
  "Cache key `yascroll--line-count' was computed for.")

(defvar yascroll--bar-buffer nil
  "Shared buffer displayed by all child-frame thumbs.")

(defvar yascroll-debug nil
  "When non-nil, re-signal rendering errors instead of swallowing them.")

(defvar yascroll--bar-buffer-keymap
  (let ((map (make-sparse-keymap)))
    ;; The thumb is an indicator, not a control.  Swallow clicks that
    ;; reach the bar buffer (they cannot on macOS, where the thumb
    ;; window ignores the mouse entirely): commands like
    ;; `mouse-drag-region' would otherwise select the bar window.
    (dolist (key '([down-mouse-1] [mouse-1] [down-mouse-2] [mouse-2]
                   [down-mouse-3] [mouse-3]))
      (define-key map key #'ignore))
    map)
  "Keymap of the child-frame bar buffer.")

;;; Utilities

(defmacro yascroll--with-no-redisplay (&rest body)
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

(defun yascroll--listify (object)
  "Return OBJECT as a list."
  (if (listp object) object (list object)))

(defun yascroll--buffer-line-count ()
  "Number of lines in the accessible buffer, cached by modification tick.
The cache is invalidated when the buffer is modified or when narrowing
changes the accessible portion."
  (let ((key (list (buffer-chars-modified-tick) (point-min) (point-max))))
    (if (equal key yascroll--line-count-key)
        yascroll--line-count
      (setq yascroll--line-count-key key
            yascroll--line-count (count-lines (point-min) (point-max))))))

(defun yascroll--window-line-height (&optional window)
  "Number of text lines that fit in WINDOW, aware of `line-spacing'."
  (if (display-graphic-p)
      (max 1 (/ (window-body-height window t)
                (yascroll--line-height (or window (selected-window)))))
    (window-body-height window)))

(defun yascroll--line-edge-position ()
  "Return (POINT PADDING) for the text-area thumb.
POINT is the logical position nearest the right edge of the window and
PADDING is the number of columns from there to the edge."
  (save-excursion
    (let* ((line-number-width
            (if (bound-and-true-p display-line-numbers-mode)
                (+ (line-number-display-width) 2)
              0))
           (window-width (- (window-width) line-number-width))
           (window-hscroll (window-hscroll))
           (tty-offset (if (display-graphic-p) 0 1))
           ;; With truncation on (or any hscroll) the first visible column is
           ;; simply the hscroll; otherwise measure the continued line's start.
           (column-bol (if (or truncate-lines (> window-hscroll 0))
                           window-hscroll
                         (progn (vertical-motion (cons 0 0))
                                (current-column))))
           (column-eol (progn (vertical-motion
                               (cons (- window-width 1 tty-offset) 0))
                              (current-column)))
           (padding (- window-width (- column-eol column-bol) tty-offset)))
      (list (point) padding))))

;;; Thumb geometry

(defun yascroll--compute-thumb-size (window-lines buffer-lines)
  "Height in lines of the thumb given WINDOW-LINES and BUFFER-LINES."
  (if (zerop buffer-lines)
      1
    (max 1 (floor (* (/ (float window-lines) buffer-lines) window-lines)))))

(defun yascroll--compute-thumb-window-line (window-lines buffer-lines scroll-top)
  "Top of the thumb as a line offset within the window.
Derived from WINDOW-LINES, BUFFER-LINES and SCROLL-TOP."
  (if (zerop buffer-lines)
      0
    (floor (* window-lines (/ (float scroll-top) buffer-lines)))))

;;; Thumb overlays

(defun yascroll--thumb-string (string &optional display)
  "Propertize STRING as a thumb glyph, optionally with DISPLAY."
  (if display (propertize string 'display display) string))

(defun yascroll--make-thumb-overlay-text-area ()
  "Create one text-area thumb overlay at point's line."
  (cl-destructuring-bind (edge-pos edge-padding)
      (yascroll--line-edge-position)
    (if (= edge-pos (line-end-position))
        (let ((overlay (make-overlay edge-pos edge-pos))
              (after-string
               (concat (make-string (max 0 (1- edge-padding)) ?\s)
                       (yascroll--thumb-string
                        (propertize " " 'face 'yascroll-thumb-text-area)))))
          (put-text-property 0 1 'cursor t after-string)
          (overlay-put overlay 'after-string after-string)
          (overlay-put overlay 'window (selected-window))
          overlay)
      (let ((overlay (make-overlay edge-pos (1+ edge-pos)))
            (display-string
             (yascroll--thumb-string
              (propertize " " 'face 'yascroll-thumb-text-area 'cursor t))))
        (overlay-put overlay 'display display-string)
        (overlay-put overlay 'window (selected-window))
        (overlay-put overlay 'priority yascroll-priority)
        overlay))))

(defun yascroll--make-thumb-overlay-at-eol (after-string)
  "Create an empty thumb overlay near EOL showing AFTER-STRING."
  (let* ((pos (point))
         ;; When point sits at BOL the glyph would land on the previous
         ;; visual line, so nudge forward.
         (pos (if (= (line-end-position) pos) pos (1+ pos)))
         (overlay (make-overlay pos pos)))
    (overlay-put overlay 'after-string after-string)
    (overlay-put overlay 'window (selected-window))
    (overlay-put overlay 'priority yascroll-priority)
    overlay))

(defun yascroll--make-thumb-overlay-fringe (side)
  "Create one fringe thumb overlay on SIDE (`left-fringe' or `right-fringe')."
  (let ((overlay (yascroll--make-thumb-overlay-at-eol
                  (yascroll--thumb-string
                   "." `(,side ,yascroll-thumb-fringe-bitmap
                               yascroll-thumb-fringe)))))
    (overlay-put overlay 'fringe-helper t)
    overlay))

(defun yascroll--make-thumb-overlay-left-fringe ()
  "Create one left-fringe thumb overlay."
  (yascroll--make-thumb-overlay-fringe 'left-fringe))

(defun yascroll--make-thumb-overlay-right-fringe ()
  "Create one right-fringe thumb overlay."
  (yascroll--make-thumb-overlay-fringe 'right-fringe))

(defun yascroll--make-thumb-overlay-right-margin ()
  "Create one right-margin thumb overlay."
  (yascroll--make-thumb-overlay-at-eol
   (yascroll--thumb-string
    " " `((margin right-margin)
          ,(propertize yascroll-thumb-margin-string
                       'face 'yascroll-thumb-margin)))))

(defun yascroll--make-thumb-overlays (make-thumb-overlay window-line size)
  "Draw a thumb SIZE lines tall starting at WINDOW-LINE.
MAKE-THUMB-OVERLAY builds one overlay at point."
  (save-excursion
    (move-to-window-line 0)
    (vertical-motion window-line)
    (condition-case nil
        (cl-loop repeat size
                 do (push (funcall make-thumb-overlay) yascroll--thumb-overlays)
                 until (zerop (vertical-motion 1)))
      (end-of-buffer nil))))

(defun yascroll--delete-thumb-overlays ()
  "Remove all thumb overlays."
  (when yascroll--thumb-overlays
    (mapc #'delete-overlay yascroll--thumb-overlays)
    (setq yascroll--thumb-overlays nil)))

;;; Child-frame thumb
;;
;; The child frame is positioned in window pixel coordinates, so it is fixed
;; to the viewport.  Overlay thumbs are anchored to buffer text and therefore
;; ride along with the text during pixel-precision scrolling, snapping back
;; on every update; a viewport-fixed thumb simply stays put between updates,
;; which is the correct behavior for a scroll bar.

(defun yascroll--bar-buffer ()
  "Return the shared child-frame thumb buffer, creating it if needed."
  (unless (buffer-live-p yascroll--bar-buffer)
    (setq yascroll--bar-buffer (get-buffer-create " *yascroll-bar*"))
    (with-current-buffer yascroll--bar-buffer
      (setq-local mode-line-format nil
                  header-line-format nil
                  cursor-type nil
                  cursor-in-non-selected-windows nil
                  left-fringe-width 0
                  right-fringe-width 0
                  left-margin-width 0
                  right-margin-width 0
                  truncate-lines t
                  buffer-read-only t)
      (use-local-map yascroll--bar-buffer-keymap)))
  yascroll--bar-buffer)

(declare-function ns-do-applescript "nsfns.m" (script))

(defvar yascroll--transparency-timer nil
  "Pending coalesced mouse-transparency sweep, or nil.")

(defun yascroll--request-mouse-transparency ()
  "Schedule a coalesced `yascroll--make-bar-frames-mouse-transparent'.
Deferring keeps the AppleScript engine (which is not reentrant) out of
frame-creation call stacks, and a burst of frame creations costs one
sweep instead of one per frame."
  (when (and (fboundp 'ns-do-applescript)
             (not (timerp yascroll--transparency-timer)))
    (setq yascroll--transparency-timer
          (run-with-timer
           0 nil
           (lambda ()
             (setq yascroll--transparency-timer nil)
             (yascroll--make-bar-frames-mouse-transparent))))))

(defun yascroll--make-bar-frames-mouse-transparent ()
  "Make every child-frame thumb's NSWindow ignore the mouse (macOS).
Emacs creates undecorated NS frames with a resizable window style, so
the mouse can select and natively resize the thumb (see
`yascroll--position-bar-frame').  Emacs Lisp exposes neither
`ignoresMouseEvents' nor the style mask, but AppleScriptObjC runs
inside the Emacs process via `ns-do-applescript' and can reach both.
Afterwards the window server no longer targets the thumb at all: it
cannot be clicked, hovered, or resized, and clicks fall through to the
text beneath.  Thumb windows are recognized by the explicit \"yascroll-bar\"
frame name.  A failure is harmless; the self-healing geometry still
reverts any interference."
  (when (fboundp 'ns-do-applescript)
    (ignore-errors
      (ns-do-applescript "use framework \"AppKit\"
set theWins to (current application's NSApplication's sharedApplication())'s |windows|()
repeat with i from 1 to ((theWins's |count|()) as integer)
  set w to (theWins's objectAtIndex:(i - 1))
  if ((w's title()) as text) contains \"yascroll-bar\" then
    (w's setIgnoresMouseEvents:true)
    set m to (w's styleMask()) as integer
    if (m div 8) mod 2 is 1 then (w's setStyleMask:(m - 8))
  end if
end repeat"))))

(defun yascroll--bar-frame (window)
  "Return WINDOW's child-frame thumb, creating it invisibly if needed."
  (let ((frame (window-parameter window 'yascroll--bar-frame)))
    (unless (frame-live-p frame)
      (let ((frame-inhibit-implied-resize t)
            (after-make-frame-functions nil))
        (setq frame
              (make-frame
               `((parent-frame . ,(window-frame window))
                 (yascroll--parent-window . ,window)
                 (name . "yascroll-bar")
                 (undecorated . t)
                 (no-accept-focus . t)
                 (no-focus-on-map . t)
                 (no-other-frame . t)
                 (unsplittable . t)
                 (minibuffer . nil)
                 (min-width . 0)
                 (min-height . 0)
                 (width . (text-pixels . ,yascroll-child-frame-width))
                 (height . (text-pixels . ,yascroll-child-frame-min-height))
                 (internal-border-width . 0)
                 (child-frame-border-width . 0)
                 (left-fringe . 0)
                 (right-fringe . 0)
                 (vertical-scroll-bars . nil)
                 (horizontal-scroll-bars . nil)
                 (menu-bar-lines . 0)
                 (tool-bar-lines . 0)
                 (tab-bar-lines . 0)
                 (cursor-type . nil)
                 (alpha . ,yascroll-child-frame-alpha)
                 (visibility . nil)
                 (desktop-dont-save . t))))
        (let ((root (frame-root-window frame)))
          (set-window-buffer root (yascroll--bar-buffer))
          (set-window-dedicated-p root t))
        (set-window-parameter window 'yascroll--bar-frame frame)
        (yascroll--request-mouse-transparency)))
    frame))

(defun yascroll--thumb-color ()
  "Background color for the child-frame thumb."
  (or (face-background 'yascroll-thumb-child-frame nil t) "gray55"))

(defun yascroll--window-scroll-top (window)
  "Lines between `point-min' and WINDOW's start, cached incrementally.
The cache lives in a window parameter so the per-redisplay repositioning
of the child-frame thumb only counts the lines scrolled since the last
call, not the whole buffer prefix."
  (let* ((start (window-start window))
         (tick (buffer-chars-modified-tick))
         (cache (window-parameter window 'yascroll--scroll-top))
         ;; cache = (START TICK PMIN LINES)
         (lines
          (if (and cache
                   (= (nth 1 cache) tick)
                   (= (nth 2 cache) (point-min)))
              (let ((old-start (nth 0 cache))
                    (old-lines (nth 3 cache)))
                (cond ((= old-start start) old-lines)
                      ((< old-start start)
                       (+ old-lines (count-lines old-start start)))
                      (t (max 0 (- old-lines (count-lines start old-start))))))
            (count-lines (point-min) start))))
    (set-window-parameter window 'yascroll--scroll-top
                          (list start tick (point-min) lines))
    lines))

(defun yascroll--line-height (window)
  "Pixel height of a default line in WINDOW, safe outside redisplay."
  (max 1 (or (window-default-line-height window)
             (frame-char-height (window-frame window)))))

(defun yascroll--realized-frame-geometry (frame)
  "FRAME's realized pixel geometry: (WIDTH HEIGHT POSITION)."
  (list (frame-pixel-width frame)
        (frame-pixel-height frame)
        (frame-position frame)))

(defun yascroll--position-bar-frame (window frame)
  "Recompute and apply FRAME's thumb geometry for WINDOW.
Includes WINDOW's sub-line vscroll so the thumb glides pixel-smoothly
under `pixel-scroll-precision-mode'.  A geometry key in a window
parameter makes repeated calls with unchanged state free.

The geometry is also re-asserted whenever FRAME's realized geometry no
longer matches what yascroll last applied: macOS gives every
undecorated frame a natively resizable NSWindow (nsterm.m adds
NSWindowStyleMaskResizable unconditionally, with no Lisp knob to
remove it), so the OS lets the mouse grab the thumb's edges and resize
it.  Any such external resize is snapped back here on the next
redisplay, which the resize itself triggers, so the thumb can never
stay moved or resized.

The reference geometry is recorded as (KEY . REALIZED), where KEY is
the window-state signature the geometry was computed from, and REALIZED
is only rewritten when KEY changes.  During a live macOS resize drag
the session stomps every size yascroll sets, so re-reading the frame
right after applying would record the drag's geometry as the baseline
and permanently disarm the heal; keeping the pre-drag REALIZED for an
unchanged KEY means yascroll keeps re-asserting until the drag ends and
the correct geometry finally sticks.

Return non-nil when the buffer overflows WINDOW (a thumb applies)."
  (with-current-buffer (window-buffer window)
    (let ((window-lines (yascroll--window-line-height window))
          (buffer-lines (yascroll--buffer-line-count)))
      (when (< window-lines buffer-lines)
        (let* ((track-top (nth 1 (window-inside-pixel-edges window)))
               (track-height (window-body-height window t))
               (right (nth 2 (window-pixel-edges window)))
               (scroll-top (yascroll--window-scroll-top window))
               (vscroll (window-vscroll window t))
               (key (list track-top track-height right scroll-top vscroll
                          window-lines buffer-lines)))
          (unless (and (equal key (window-parameter window
                                                    'yascroll--bar-geometry))
                       (equal (cdr (frame-parameter frame
                                                    'yascroll--applied-geometry))
                              (yascroll--realized-frame-geometry frame)))
            (set-window-parameter window 'yascroll--bar-geometry key)
            ;; Scroll motion or a grabbed thumb both mean the user is
            ;; active: snap a fading thumb back to full strength and push
            ;; the auto-hide back, like macOS.
            (when yascroll--fade-timer
              (yascroll--cancel-fade))
            (yascroll--schedule-hide)
            (let* ((line-height (yascroll--line-height window))
                   (thumb-height (max yascroll-child-frame-min-height
                                      (round (* track-height
                                                (/ (float window-lines)
                                                   buffer-lines)))))
                   (thumb-height (min thumb-height track-height))
                   (denominator (max 1 (- buffer-lines window-lines)))
                   (fraction (min 1.0 (/ (+ scroll-top
                                            (/ vscroll (float line-height)))
                                         denominator)))
                   (frame-resize-pixelwise t))
              (yascroll--restore-thumb-color frame)
              (set-frame-size frame yascroll-child-frame-width thumb-height t)
              ;; Emacs clamps a frame to at least one character column/line,
              ;; so the realized size can exceed what was requested.  Align
              ;; with the measured size or the thumb overhangs the window
              ;; edge and gets clipped.
              (let* ((actual-width (frame-pixel-width frame))
                     (actual-height (frame-pixel-height frame))
                     (y (+ track-top
                           (round (* (max 0 (- track-height actual-height))
                                     fraction)))))
                (set-frame-position frame (- right actual-width) y)
                ;; Refresh the reference geometry only when the window
                ;; state it derives from changed; see the docstring for why
                ;; a stomped re-read must never replace the clean baseline.
                (let ((record (frame-parameter frame
                                               'yascroll--applied-geometry)))
                  (unless (equal key (car record))
                    (set-frame-parameter
                     frame 'yascroll--applied-geometry
                     (cons key
                           (yascroll--realized-frame-geometry frame))))))))
          t)))))

(defun yascroll--show-child-frame ()
  "Position and show the child-frame thumb for the selected window.
Return non-nil when a thumb was shown."
  (let ((window (selected-window)))
    ;; Two guards, both load-bearing: a window living in a thumb frame
    ;; must never grow a thumb of its own (recursion), and the overflow
    ;; decision must come before `yascroll--bar-frame', which creates
    ;; the frame as a side effect.
    (when (and (not (frame-parameter (window-frame window)
                                     'yascroll--parent-window))
               (< (yascroll--window-line-height window)
                  (yascroll--buffer-line-count)))
      (when (yascroll--position-bar-frame window (yascroll--bar-frame window))
        (let ((frame (window-parameter window 'yascroll--bar-frame)))
          (unless (frame-visible-p frame)
            (make-frame-visible frame)))
        t))))

(defun yascroll--pre-redisplay (window)
  "Track WINDOW's scroll state before WINDOW is redrawn.
Runs on `pre-redisplay-functions', which fires for vscroll-only pixel
scrolls that never touch `window-start', so this sees every rendered
frame.  A visible child-frame thumb is repositioned (gliding); scroll
motion cancels a running fade; and scroll motion while the thumb is
hidden schedules a re-show.  Heavier work (creation, visibility) stays
in the deferred update path."
  (when (windowp window)
    (let ((frame (window-parameter window 'yascroll--bar-frame))
          (key (cons (window-start window) (window-vscroll window t)))
          (old (window-parameter window 'yascroll--scroll-key)))
      (set-window-parameter window 'yascroll--scroll-key key)
      (if (and (frame-live-p frame) (frame-visible-p frame))
          (if yascroll-debug
              (yascroll--position-bar-frame window frame)
            (ignore-errors (yascroll--position-bar-frame window frame)))
        ;; Thumb hidden (or never created): any scroll motion, including
        ;; sub-line vscroll that fires no scroll hook, re-shows it.
        (when (and old (not (equal key old)))
          (yascroll--request-update (window-buffer window)))))))

(defun yascroll--on-frame-size-change (frame)
  "Snap an externally resized child-frame thumb FRAME back into place.
macOS thumbs are natively mouse-resizable (see
`yascroll--position-bar-frame'); resizing one changes its window size,
which runs this hook with the thumb frame itself, and repositioning
re-asserts the correct geometry immediately.  Other frames' size
changes are handled by the usual update paths and ignored here."
  (when (framep frame)
    (let ((window (frame-parameter frame 'yascroll--parent-window)))
      (when (and (window-live-p window)
                 (frame-visible-p frame))
        (if yascroll-debug
            (yascroll--position-bar-frame window frame)
          (ignore-errors (yascroll--position-bar-frame window frame)))))))

(defun yascroll--hide-bar-frame (window)
  "Hide WINDOW's child-frame thumb if it is visible."
  (let ((frame (window-parameter window 'yascroll--bar-frame)))
    (when (frame-live-p frame)
      (when (frame-visible-p frame)
        (make-frame-invisible frame))
      ;; Undo any partial fade so the next show is at full strength.
      (yascroll--restore-thumb-color frame))))

(defun yascroll--cleanup-bar-frames ()
  "Delete child-frame thumbs whose parent window is gone or is a thumb.
The second case heals sessions poisoned by the runaway thumb-on-thumb
recursion fixed in 1.7.2."
  (dolist (frame (frame-list))
    (let ((window (frame-parameter frame 'yascroll--parent-window)))
      (when (and window
                 (or (not (window-live-p window))
                     (frame-parameter (window-frame window)
                                      'yascroll--parent-window)))
        (delete-frame frame t)))))

(defun yascroll--delete-bar-frame (window)
  "Delete WINDOW's child-frame thumb entirely."
  (let ((frame (window-parameter window 'yascroll--bar-frame)))
    (set-window-parameter window 'yascroll--bar-frame nil)
    (when (frame-live-p frame)
      (delete-frame frame t))))

;;; Fade-out
;;
;; The fade blends the thumb's background color into the window background
;; instead of animating the frame `alpha' parameter: on macOS, alpha changes
;; to an already-visible child frame are applied erratically (often only
;; when the frame is next made visible), which froze thumbs at partial
;; opacity.  Color changes render reliably everywhere.

(defconst yascroll--fade-interval (/ 1.0 30)
  "Seconds between fade animation steps (30 fps).")

(defun yascroll--visible-bar-frames (&optional buffer)
  "Return the visible child-frame thumbs of windows showing BUFFER."
  (let (frames)
    (dolist (window (get-buffer-window-list (or buffer (current-buffer)) nil t))
      (let ((frame (window-parameter window 'yascroll--bar-frame)))
        (when (and (frame-live-p frame) (frame-visible-p frame))
          (push frame frames))))
    frames))

(defun yascroll--blend-colors (from to fraction)
  "Blend color FROM toward color TO by FRACTION (0.0 .. 1.0)."
  (let ((f (color-values from))
        (h (color-values to)))
    (if (and f h)
        (apply #'format "#%04x%04x%04x"
               (cl-mapcar (lambda (a b)
                            (round (+ (* a (- 1.0 fraction)) (* b fraction))))
                          f h))
      to)))

(defun yascroll--fade-target-color (frame)
  "Color the fading thumb FRAME blends toward: its parent's background."
  (or (frame-parameter (frame-parent frame) 'background-color)
      (face-background 'default nil t)
      "black"))

(defun yascroll--restore-thumb-color (frame)
  "Reset FRAME's background to the full-strength thumb color."
  (let ((color (yascroll--thumb-color)))
    (unless (equal color (frame-parameter frame 'background-color))
      (set-frame-parameter frame 'background-color color))))

(defun yascroll--cancel-fade ()
  "Stop any fade animation and restore full thumb color."
  (when (timerp yascroll--fade-timer)
    (cancel-timer yascroll--fade-timer))
  (setq yascroll--fade-timer nil)
  (dolist (frame (yascroll--visible-bar-frames))
    (yascroll--restore-thumb-color frame)))

(defun yascroll--fade-out ()
  "Fade the child-frame thumbs out, then hide the scroll bar.
Falls back to hiding instantly when fading is disabled or the thumb is
overlay-based (overlay faces cannot be animated per window)."
  (let ((frames (yascroll--visible-bar-frames)))
    (if (or (null frames)
            yascroll--thumb-overlays
            (not (numberp yascroll-fade-duration))
            (<= yascroll-fade-duration 0))
        (yascroll-hide-scroll-bar)
      (yascroll--cancel-fade)
      (let* ((buffer (current-buffer))
             (steps (max 1 (round (/ yascroll-fade-duration
                                     yascroll--fade-interval))))
             (step 0)
             (timer nil))
        (setq timer
              (run-with-timer
               yascroll--fade-interval yascroll--fade-interval
               (lambda ()
                 (if (not (buffer-live-p buffer))
                     (cancel-timer timer)
                   (with-current-buffer buffer
                     (setq step (1+ step))
                     (if (>= step steps)
                         ;; `yascroll-hide-scroll-bar' cancels this timer
                         ;; via `yascroll--cancel-fade' and restores color.
                         (yascroll-hide-scroll-bar)
                       (let ((fraction (/ (float step) steps)))
                         (dolist (frame (yascroll--visible-bar-frames buffer))
                           (set-frame-parameter
                            frame 'background-color
                            (yascroll--blend-colors
                             (yascroll--thumb-color)
                             (yascroll--fade-target-color frame)
                             fraction))))))))))
        (setq yascroll--fade-timer timer)))))

;;; Margin management

(defun yascroll--wants-margin-p (buffer)
  "Return non-nil when BUFFER's yascroll wants a right margin reserved."
  (and (buffer-local-value 'yascroll-bar-mode buffer)
       (memq 'right-margin
             (yascroll--listify
              (buffer-local-value 'yascroll-scroll-bar buffer)))))

(defun yascroll--sync-window (window)
  "Reconcile WINDOW's yascroll margin and child-frame with its buffer."
  (when (and (window-live-p window)
             (not (window-minibuffer-p window)))
    ;; Hide a stale child-frame thumb when the window no longer shows a
    ;; yascroll buffer.
    (unless (buffer-local-value 'yascroll-bar-mode (window-buffer window))
      (yascroll--hide-bar-frame window))
    (let ((margins (window-margins window)))
      (cond
       ((yascroll--wants-margin-p (window-buffer window))
        (unless (window-parameter window 'yascroll--saved-margin)
          (set-window-parameter window 'yascroll--saved-margin
                                (or (cdr margins) 0)))
        (when (< (or (cdr margins) 0) 1)
          (set-window-margins window (car margins) 1)))
       ((window-parameter window 'yascroll--saved-margin)
        (let ((old (window-parameter window 'yascroll--saved-margin)))
          (set-window-parameter window 'yascroll--saved-margin nil)
          (set-window-margins window (car margins)
                              (and (numberp old) (> old 0) old))))))))

(defun yascroll--on-window-buffer-change (frame-or-window)
  "Sync yascroll state after FRAME-OR-WINDOW shows different buffers."
  (if (windowp frame-or-window)
      (yascroll--sync-window frame-or-window)
    (dolist (window (window-list frame-or-window 'nomini))
      (yascroll--sync-window window))))

(defun yascroll--sync-windows ()
  "Sync all windows showing the current buffer."
  (dolist (window (get-buffer-window-list (current-buffer) nil t))
    (yascroll--sync-window window)))

;;; Show / hide

(defun yascroll--diff-hl-occupies-fringe-p (side)
  "Return non-nil when diff-hl draws its indicators in fringe SIDE."
  (and (bound-and-true-p diff-hl-mode)
       (not (bound-and-true-p diff-hl-margin-mode))
       (eq (or (bound-and-true-p diff-hl-side) 'left)
           (if (eq side 'left-fringe) 'left 'right))))

(defun yascroll--fringe-occupied-p (side)
  "Return non-nil when another package owns fringe SIDE."
  (run-hook-with-args-until-success 'yascroll-fringe-occupied-functions side))

(defun yascroll--choose-scroll-bar ()
  "Return the first usable scroll-bar candidate, or nil."
  (when (memq window-system yascroll-enabled-window-systems)
    (let* ((fringes (window-fringes))
           (left-width (nth 0 fringes))
           (right-width (nth 1 fringes))
           (right-margin (or (cdr (window-margins)) 0)))
      (cl-loop
       for candidate in (yascroll--listify yascroll-scroll-bar)
       when (pcase candidate
              ('text-area t)
              ('child-frame (display-graphic-p))
              ('right-margin (>= right-margin 1))
              ('left-fringe (and (> left-width 0)
                                 (not (yascroll--fringe-occupied-p
                                       'left-fringe))))
              ('right-fringe (and (> right-width 0)
                                  (not (yascroll--fringe-occupied-p
                                        'right-fringe)))))
       return candidate))))

(defun yascroll--schedule-hide ()
  "Debounce: hide the thumb `yascroll-delay-to-hide' after the last activity.
Every render and every scroll motion re-arms this wall-clock timer, so
it can only fire once scrolling has actually stopped.  A wall-clock
timer is used instead of an idle timer because scroll events do not
reliably reset Emacs's idle clock, which made idle-based hides fire in
the middle of active scrolling."
  (when yascroll-delay-to-hide
    (when (timerp yascroll--delay-timer)
      (cancel-timer yascroll--delay-timer))
    (setq yascroll--delay-timer
          (run-with-timer
           yascroll-delay-to-hide nil
           (lambda (buffer)
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (yascroll--fade-out))))
           (current-buffer)))))

(defun yascroll--show-in-selected-window ()
  "Render the thumb in the selected window if the buffer overflows it.
Return non-nil when a child-frame thumb was shown."
  (let ((scroll-bar (yascroll--choose-scroll-bar))
        (window-lines (yascroll--window-line-height))
        (buffer-lines (yascroll--buffer-line-count)))
    (if (eq scroll-bar 'child-frame)
        (yascroll--show-child-frame)
      (when (and scroll-bar (< window-lines buffer-lines))
        (let* ((scroll-top (count-lines (point-min) (window-start)))
               (thumb-window-line (yascroll--compute-thumb-window-line
                                   window-lines buffer-lines scroll-top))
               (thumb-buffer-line (+ scroll-top thumb-window-line))
               (thumb-size (yascroll--compute-thumb-size
                            window-lines buffer-lines))
               (make-thumb-overlay
                (cl-ecase scroll-bar
                  (left-fringe  #'yascroll--make-thumb-overlay-left-fringe)
                  (right-fringe #'yascroll--make-thumb-overlay-right-fringe)
                  (right-margin #'yascroll--make-thumb-overlay-right-margin)
                  (text-area    #'yascroll--make-thumb-overlay-text-area))))
          (when (<= thumb-buffer-line buffer-lines)
            (yascroll--make-thumb-overlays make-thumb-overlay
                                           thumb-window-line thumb-size))))
      nil)))

(defun yascroll--render-signature ()
  "Return a value identifying the current thumb-relevant display state."
  (list (mapcar (lambda (window)
                  (list window
                        (window-start window)
                        (window-vscroll window t)
                        (window-body-height window t)))
                (get-buffer-window-list (current-buffer) nil t))
        (buffer-chars-modified-tick)
        (point-min) (point-max)))

;;;###autoload
(defun yascroll-show-scroll-bar ()
  "Show the scroll bar in every window displaying the current buffer."
  (interactive)
  (yascroll--with-no-redisplay
    ;; A re-show mid-fade must snap back to full opacity, like macOS.
    (yascroll--cancel-fade)
    (yascroll--delete-thumb-overlays)
    (let ((windows (get-buffer-window-list (current-buffer) nil t))
          (shown nil))
      (dolist (window windows)
        (with-selected-window window
          (when (yascroll--show-in-selected-window)
            (push window shown))))
      ;; Hide child-frame thumbs of windows that did not render one this
      ;; time (buffer fits, or an overlay target was chosen instead).
      (dolist (window windows)
        (unless (memq window shown)
          (yascroll--hide-bar-frame window)))
      (when (or shown yascroll--thumb-overlays)
        (yascroll--schedule-hide)))
    (setq yascroll--render-state (yascroll--render-signature))))

;;;###autoload
(defun yascroll-hide-scroll-bar ()
  "Hide the scroll bar in the current buffer."
  (interactive)
  (yascroll--cancel-fade)
  (setq yascroll--render-state nil)
  (yascroll--delete-thumb-overlays)
  (dolist (window (get-buffer-window-list (current-buffer) nil t))
    (yascroll--hide-bar-frame window)))

(defun yascroll-scroll-bar-visible-p ()
  "Return non-nil when a thumb is currently displayed."
  (or yascroll--thumb-overlays
      (cl-some (lambda (window)
                 (let ((frame (window-parameter window 'yascroll--bar-frame)))
                   (and (frame-live-p frame) (frame-visible-p frame))))
               (get-buffer-window-list (current-buffer) nil t))))

(defun yascroll--safe-show ()
  "Show the scroll bar, swallowing transient rendering errors.
A failure hides the bar but leaves `yascroll-bar-mode' enabled."
  (condition-case err
      (yascroll-show-scroll-bar)
    (error
     (yascroll-hide-scroll-bar)
     (if yascroll-debug
         (signal (car err) (cdr err))
       (message "yascroll: %S" err)))))

;;; Deferred updates
;;
;; Scroll hooks (`window-scroll-functions') run in the middle of redisplay.
;; Mutating display state there interferes with the pixel measurements of
;; `pixel-scroll-precision-mode', so hooks only schedule a coalescing
;; 0-second timer and the actual render happens between frames.

(defun yascroll--request-update (&optional buffer)
  "Schedule a coalesced scroll bar update for BUFFER."
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (unless yascroll--update-timer
          (setq yascroll--update-timer
                (run-with-timer 0 nil #'yascroll--do-update buffer)))))))

(defun yascroll--do-update (buffer)
  "Re-render BUFFER's scroll bar unless nothing observable changed."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq yascroll--update-timer nil)
      (when yascroll-bar-mode
        (unless (and (yascroll-scroll-bar-visible-p)
                     (equal yascroll--render-state
                            (yascroll--render-signature)))
          (yascroll--safe-show))))))

;;; Hooks

(defun yascroll--before-change (&rest _)
  "Hide or trim the thumb before a buffer modification.
When auto-hiding, an edit dismisses the bar (type-to-dismiss).  When
the bar is meant to stay visible (`yascroll-delay-to-hide' nil), only
overlay thumbs are removed -- their text anchors go stale mid-edit --
while the viewport-fixed child frame stays put: hiding it here would
toggle its NSWindow's visibility once per insertion in a buffer fed by
a streaming process.  The after-change update repositions everything."
  (if yascroll-delay-to-hide
      (yascroll-hide-scroll-bar)
    (yascroll--delete-thumb-overlays)))

(defun yascroll--after-change (&rest _)
  "Re-show the bar after a modification when it is meant to stay visible."
  (unless yascroll-delay-to-hide
    (yascroll--request-update)))

(defun yascroll--after-window-scroll (window _start)
  "Schedule an update after WINDOW scrolls.
Called during redisplay, so only a timer is scheduled here."
  (yascroll--request-update (window-buffer window)))

(defun yascroll--after-window-configuration-change ()
  "Reconcile margins/frames and re-render after a layout change."
  (yascroll--sync-windows)
  (yascroll--cleanup-bar-frames)
  (when (yascroll-scroll-bar-visible-p)
    (yascroll--request-update)))

;;; Minor modes

(defun yascroll--any-buffer-enabled-p ()
  "Return non-nil when some live buffer has `yascroll-bar-mode' on."
  (cl-some (lambda (buffer)
             (buffer-local-value 'yascroll-bar-mode buffer))
           (buffer-list)))

;;;###autoload
(define-minor-mode yascroll-bar-mode
  "Toggle the yascroll scroll bar in this buffer."
  :group 'yascroll
  (if yascroll-bar-mode
      (progn
        (add-hook 'before-change-functions #'yascroll--before-change nil t)
        (add-hook 'after-change-functions #'yascroll--after-change nil t)
        (add-hook 'window-scroll-functions #'yascroll--after-window-scroll nil t)
        (add-hook 'pre-redisplay-functions #'yascroll--pre-redisplay nil t)
        (add-hook 'window-configuration-change-hook
                  #'yascroll--after-window-configuration-change nil t)
        ;; Global hooks: windows change buffers without any buffer-local
        ;; hook firing, and reserved margins / child frames must follow;
        ;; size changes of the thumb frames themselves (macOS native
        ;; resize) arrive with the thumb frame, not the parent window.
        (add-hook 'window-buffer-change-functions
                  #'yascroll--on-window-buffer-change)
        (add-hook 'window-size-change-functions
                  #'yascroll--on-frame-size-change)
        (yascroll--sync-windows)
        (yascroll--request-update))
    (dolist (timer (list yascroll--delay-timer yascroll--update-timer))
      (when (timerp timer) (cancel-timer timer)))
    (setq yascroll--delay-timer nil
          yascroll--update-timer nil)
    (yascroll-hide-scroll-bar)
    (dolist (window (get-buffer-window-list (current-buffer) nil t))
      (yascroll--delete-bar-frame window))
    (remove-hook 'before-change-functions #'yascroll--before-change t)
    (remove-hook 'after-change-functions #'yascroll--after-change t)
    (remove-hook 'window-scroll-functions #'yascroll--after-window-scroll t)
    (remove-hook 'pre-redisplay-functions #'yascroll--pre-redisplay t)
    (remove-hook 'window-configuration-change-hook
                 #'yascroll--after-window-configuration-change t)
    (yascroll--sync-windows)
    (unless (yascroll--any-buffer-enabled-p)
      (remove-hook 'window-buffer-change-functions
                   #'yascroll--on-window-buffer-change)
      (remove-hook 'window-size-change-functions
                   #'yascroll--on-frame-size-change))))

(defun yascroll--enabled-buffer-p (buffer)
  "Return non-nil when yascroll should turn on in BUFFER."
  (with-current-buffer buffer
    (and (not (minibufferp))
         ;; Never in the shared bar buffer.  It only exists after the
         ;; first thumb has shown, so re-enabling the global mode used to
         ;; enroll it, making every thumb window grow a thumb of its own:
         ;; measured 3 -> 61 -> 129 frames across repeated enables, which
         ;; froze the session.
         (not (eq (current-buffer) yascroll--bar-buffer))
         (not (memq major-mode yascroll-disabled-modes)))))

(defun yascroll--turn-on ()
  "Turn on `yascroll-bar-mode' where appropriate."
  (when (yascroll--enabled-buffer-p (current-buffer))
    (yascroll-bar-mode 1)))

;;;###autoload
(define-globalized-minor-mode global-yascroll-bar-mode
  yascroll-bar-mode yascroll--turn-on
  :group 'yascroll)

(provide 'yascroll)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; yascroll.el ends here
