;; ============================================================================
;; MLeaderSmartAlign_Perimeter_v01_fix1.lsp
;;
;; AutoCAD / Visual LISP companion command for MLeaderSmartAlign v0.5.
;;
;; fix1:
;;   - renamed local/formal variable T to safe names (ratio/param).
;;     In AutoLISP T is the built-in true constant and cannot be bound.
;;
;; Purpose:
;;   Distribute many MULTILEADER objects around a user-defined parallelogram.
;;
;; Workflow:
;;   1) Select MULTILEADER objects.
;;   2) Pick P1.
;;   3) Drag a dashed transient line P1 -> P2 and click P2.
;;   4) From P2 immediately drag the second side P2 -> P3 and click P3.
;;   5) P4 is calculated automatically:
;;
;;          P4 = P1 + (P3 - P2)
;;
;;   6) Four sides + both diagonals are shown as a transient dashed frame.
;;   7) The diagonals divide the parallelogram into four triangles.
;;   8) Each MLeader is assigned by its representative ORIGINAL arrow point:
;;
;;          triangle P1-P2-C -> side P1-P2
;;          triangle P2-P3-C -> side P2-P3
;;          triangle P3-P4-C -> side P3-P4
;;          triangle P4-P1-C -> side P4-P1
;;
;;      Boundary/outside arrow points are assigned to the nearest perimeter side.
;;
;;   9) Inside each side group, the proven MLeaderSmartAlign iterative algorithm
;;      is used:
;;
;;          N -> choose -> move one
;;        N-1 -> recalculate -> choose -> move one
;;        ...
;;
;;      Each MLeader is shown moving step-by-step.
;;
;;   10) The transient parallelogram disappears when placement is complete.
;;
;; Commands:
;;   MSAP
;;   MLeaderSmartAlignPerimeter
;;
;; Dependency:
;;   MLeaderSmartAlign_v05.lsp
;;
;;   Load MLeaderSmartAlign_v05.lsp first, or place it in an AutoCAD support
;;   path so this file can find and load it automatically.
;;
;; Notes:
;;   - Windows AutoCAD / Visual LISP / ActiveX.
;;   - Uses v0.5 "SHELF_CENTER" content reference:
;;       MText -> horizontal center projected onto landing,
;;       block  -> block content point,
;;       fallback -> landing.
;;   - Arrowhead geometry is restored after every MLeader move by the base v0.5
;;     functions.
;;   - The transient dashed frame is drawn with grdraw; it is not added to the
;;     drawing database.
;; ============================================================================

(vl-load-com)

;; ----------------------------------------------------------------------------
;; Base v0.5 availability
;; ----------------------------------------------------------------------------

(defun msap:function-defined-p (sym)
  ;; AutoLISP has BOUNDP for variables but no portable FBOUNDP.
  ;; ATOMS-FAMILY 0 returns the currently defined symbols.
  (if (member sym (atoms-family 0)) T nil)
)

(defun msap:ensure-base (/ f ok)
  (setq ok
    (and
      (msap:function-defined-p 'msa:collect-records)
      (msap:function-defined-p 'msa:compute-placements)
      (msap:function-defined-p 'msa:move-record-between)
      (msap:function-defined-p 'msa:restore-originals)
      (msap:function-defined-p 'msa:v-)
      (msap:function-defined-p 'msa:v+)
      (msap:function-defined-p 'msa:v*)
    )
  )

  (if (not ok)
    (progn
      (setq f (findfile "MLeaderSmartAlign_v05.lsp"))
      (if f
        (progn
          (load f)
          (setq ok
            (and
              (msap:function-defined-p 'msa:collect-records)
              (msap:function-defined-p 'msa:compute-placements)
              (msap:function-defined-p 'msa:move-record-between)
              (msap:function-defined-p 'msa:restore-originals)
            )
          )
        )
      )
    )
  )

  ok
)

;; ----------------------------------------------------------------------------
;; 2D geometry helpers
;; ----------------------------------------------------------------------------

(defun msap:cross2 (ax ay bx by)
  (- (* ax by) (* ay bx))
)

(defun msap:point-in-triangle-p (p a b c / eps c1 c2 c3)
  (setq eps 1.0e-9
        c1 (msap:cross2
             (- (car b) (car a))
             (- (cadr b) (cadr a))
             (- (car p) (car a))
             (- (cadr p) (cadr a)))
        c2 (msap:cross2
             (- (car c) (car b))
             (- (cadr c) (cadr b))
             (- (car p) (car b))
             (- (cadr p) (cadr b)))
        c3 (msap:cross2
             (- (car a) (car c))
             (- (cadr a) (cadr c))
             (- (car p) (car c))
             (- (cadr p) (cadr c))))

  (or
    (and (>= c1 (- eps)) (>= c2 (- eps)) (>= c3 (- eps)))
    (and (<= c1 eps)     (<= c2 eps)     (<= c3 eps))
  )
)

(defun msap:point-segment-dist2 (p a b / vx vy wx wy len2 param qx qy dx dy)
  (setq vx (- (car b) (car a))
        vy (- (cadr b) (cadr a))
        wx (- (car p) (car a))
        wy (- (cadr p) (cadr a))
        len2 (+ (* vx vx) (* vy vy)))

  (if (< len2 1.0e-18)
    (progn
      (setq dx wx
            dy wy)
      (+ (* dx dx) (* dy dy))
    )
    (progn
      (setq param (/ (+ (* wx vx) (* wy vy)) len2))
      (cond
        ((< param 0.0) (setq param 0.0))
        ((> param 1.0) (setq param 1.0))
      )
      (setq qx (+ (car a) (* param vx))
            qy (+ (cadr a) (* param vy))
            dx (- (car p) qx)
            dy (- (cadr p) qy))
      (+ (* dx dx) (* dy dy))
    )
  )
)

(defun msap:nearest-side (p p1 p2 p3 p4 / d0 d1 d2 d3 best bestd)
  (setq d0 (msap:point-segment-dist2 p p1 p2)
        d1 (msap:point-segment-dist2 p p2 p3)
        d2 (msap:point-segment-dist2 p p3 p4)
        d3 (msap:point-segment-dist2 p p4 p1)
        best 0
        bestd d0)

  (if (< d1 bestd) (setq best 1 bestd d1))
  (if (< d2 bestd) (setq best 2 bestd d2))
  (if (< d3 bestd) (setq best 3 bestd d3))

  best
)

;; Returns (group outsideP)
;; group:
;;   0 -> P1-P2
;;   1 -> P2-P3
;;   2 -> P3-P4
;;   3 -> P4-P1
(defun msap:classify-point (p p1 p2 p3 p4 c / i0 i1 i2 i3 matches group)
  (setq i0 (msap:point-in-triangle-p p p1 p2 c)
        i1 (msap:point-in-triangle-p p p2 p3 c)
        i2 (msap:point-in-triangle-p p p3 p4 c)
        i3 (msap:point-in-triangle-p p p4 p1 c)
        matches (+ (if i0 1 0)
                   (if i1 1 0)
                   (if i2 1 0)
                   (if i3 1 0)))

  (cond
    ((= matches 1)
     (setq group
       (cond
         (i0 0)
         (i1 1)
         (i2 2)
         (T  3)))
     (list group nil))

    (T
     ;; On a diagonal / vertex / outside frame:
     ;; use nearest outer side.  Mark outside only if it matched no triangle.
     (list (msap:nearest-side p p1 p2 p3 p4)
           (= matches 0)))
  )
)

;; ----------------------------------------------------------------------------
;; Transient dashed graphics
;; ----------------------------------------------------------------------------

(defun msap:lerp-point (a b ratio)
  (list
    (+ (car a)   (* ratio (- (car b)   (car a))))
    (+ (cadr a)  (* ratio (- (cadr b)  (cadr a))))
    (+ (caddr a) (* ratio (- (caddr b) (caddr a))))
  )
)

;; Draw a display-only dashed segment.
;; AutoCAD color 7 is adaptive: white on dark background, black on light.
(defun msap:gr-dashed (a b / divisions i t1 t2)
  (setq divisions 40
        i 0)
  (repeat divisions
    (if (= (rem i 2) 0)
      (progn
        (setq t1 (/ (float i) divisions)
              t2 (/ (float (1+ i)) divisions))
        (grdraw (msap:lerp-point a b t1)
                (msap:lerp-point a b t2)
                7
                0)
      )
    )
    (setq i (1+ i))
  )
)

(defun msap:draw-frame-u (p1 p2 p3 p4)
  (msap:gr-dashed p1 p2)
  (msap:gr-dashed p2 p3)
  (msap:gr-dashed p3 p4)
  (msap:gr-dashed p4 p1)
  (msap:gr-dashed p1 p3)
  (msap:gr-dashed p2 p4)
)

;; Rubber-band one side using grread.
;; fixedA/fixedB optionally show the already accepted first side while the
;; second side is being defined.
(defun msap:get-rubber-point (base promptText fixedA fixedB / ev code data
                                    done cancelled accepted lastPt result)
  (setq done nil
        cancelled nil
        accepted nil
        lastPt nil)

  (prompt (strcat "\n" promptText))

  (while (not done)
    (setq ev (vl-catch-all-apply 'grread (list T 15 0)))
    (if (vl-catch-all-error-p ev)
      (setq ev '(2 27))
    )

    (setq code (car ev)
          data (cadr ev))

    (cond
      ;; MouseMove
      ((= code 5)
       (setq lastPt data)
       (redraw)
       (if (and fixedA fixedB)
         (msap:gr-dashed fixedA fixedB)
       )
       (if (> (distance base lastPt) 1.0e-9)
         (msap:gr-dashed base lastPt)
       )
      )

      ;; Left click
      ((= code 3)
       (if (> (distance base data) 1.0e-9)
         (setq result data
               accepted T
               done T)
       )
      )

      ;; Keyboard
      ((= code 2)
       (cond
         ((= data 27)
          (setq cancelled T done T))
         ((member data '(13 32))
          (if (and lastPt (> (distance base lastPt) 1.0e-9))
            (setq result lastPt
                  accepted T
                  done T)
          )
         )
       )
      )

      ;; Secondary mouse button
      ((= code 25)
       (setq cancelled T done T))
    )
  )

  (redraw)

  (if (and accepted (not cancelled))
    result
    nil
  )
)

;; ----------------------------------------------------------------------------
;; Group helpers
;; ----------------------------------------------------------------------------

(defun msap:append-to-group (rec idx groups / g0 g1 g2 g3)
  (setq g0 (nth 0 groups)
        g1 (nth 1 groups)
        g2 (nth 2 groups)
        g3 (nth 3 groups))

  (cond
    ((= idx 0) (setq g0 (append g0 (list rec))))
    ((= idx 1) (setq g1 (append g1 (list rec))))
    ((= idx 2) (setq g2 (append g2 (list rec))))
    ((= idx 3) (setq g3 (append g3 (list rec))))
  )

  (list g0 g1 g2 g3)
)

;; Records use WCS.  Arrow point is record item 4.
(defun msap:classify-records (records p1 p2 p3 p4 / c groups outside rec p info idx)
  (setq c (list
            (/ (+ (car p1)  (car p3))  2.0)
            (/ (+ (cadr p1) (cadr p3)) 2.0)
            (/ (+ (caddr p1) (caddr p3)) 2.0))
        groups (list '() '() '() '())
        outside 0)

  (foreach rec records
    (setq p (nth 4 rec)
          info (msap:classify-point p p1 p2 p3 p4 c)
          idx (car info))

    (if (cadr info)
      (setq outside (1+ outside))
    )

    (setq groups (msap:append-to-group rec idx groups))
  )

  (list groups outside)
)

;; ----------------------------------------------------------------------------
;; Step-by-step placement
;; ----------------------------------------------------------------------------

;; Apply one side group using the exact base v0.5 iterative computation.
;;
;; Returns:
;;   (updatedCurrentPlacements failedCount)
(defun msap:apply-group (group a b frameU currentPlacements sideNo
                         / calc placements pl rec target ok failed)
  (setq failed 0)

  (if group
    (progn
      (setq calc (msa:compute-placements group a b))
      (if calc
        (progn
          (setq placements (car calc))

          (foreach pl placements
            (setq rec    (car pl)
                  target (cadr pl))

            ;; Every record in this perimeter command is moved only once.
            ;; Start from its original v0.5 placement reference.
            (setq ok
              (msa:move-record-between
                rec
                (nth 3 rec)
                target))

            (if ok
              (setq currentPlacements
                (cons (list rec target) currentPlacements))
              (setq failed (1+ failed))
            )

            (prompt
              (strcat
                "\rMLeaderSmartAlign Perimeter - side "
                (itoa sideNo)
                ": "
                (itoa (length currentPlacements))
                " placed"
              )
            )

            ;; Show this exact step and redraw the transient helper frame,
            ;; because REDRAW erases grdraw graphics.
            (redraw)
            (apply 'msap:draw-frame-u frameU)
          )
        )
      )
    )
  )

  (list currentPlacements failed)
)

;; ----------------------------------------------------------------------------
;; Main command
;; ----------------------------------------------------------------------------

(defun msap:run (/ *error* acad doc undoOpen ss n
                   p1u p2u p3u p4u
                   p1w p2w p3w p4w
                   v1u v2u area
                   collected records skipped
                   classified groups outside
                   g0 g1 g2 g3
                   currentPlacements totalFailed r
                   frameU)

  (if (not (msap:ensure-base))
    (progn
      (prompt
        (strcat
          "\nMLeaderSmartAlign_Perimeter requires MLeaderSmartAlign_v05.lsp."
          "\nLoad MLeaderSmartAlign_v05.lsp with APPLOAD first, then run MSAP."
        )
      )
      (princ)
    )

    (progn
      (setq acad (vlax-get-acad-object)
            doc  (vla-get-ActiveDocument acad)
            undoOpen nil
            records nil
            currentPlacements nil
            totalFailed 0)

      (defun *error* (msg)
        (redraw)

        ;; Restore any MLeaders already moved before an unexpected error.
        (if (and records currentPlacements)
          (progn
            (msa:restore-originals records currentPlacements)
            (vl-catch-all-apply 'vla-Regen (list doc 1))
          )
        )

        (if undoOpen
          (progn
            (vl-catch-all-apply 'vla-EndUndoMark (list doc))
            (setq undoOpen nil)
          )
        )

        (if (and msg
                 (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")))
          (prompt (strcat "\nMLeaderSmartAlign Perimeter error: " msg))
        )

        (princ)
      )

      (prompt
        (strcat
          "\nMLeaderSmartAlign Perimeter v0.1"
          "\nFour-side geometry-aware MULTILEADER distribution."
        )
      )

      (setq ss (ssget '((0 . "MULTILEADER"))))

      (cond
        ((null ss)
         (prompt "\nNo MULTILEADER objects selected."))

        ((< (setq n (sslength ss)) 2)
         (prompt "\nSelect at least two MULTILEADER objects."))

        (T
         ;; P1 uses normal GETPOINT so OSNAP works for the first point.
         (setq p1u (getpoint "\nSpecify parallelogram P1: "))

         (if p1u
           (progn
             ;; First side P1 -> P2.
             (setq p2u
               (msap:get-rubber-point
                 p1u
                 "Move cursor for side P1-P2, click P2 <Esc to cancel>: "
                 nil
                 nil))

             (if p2u
               (progn
                 ;; Second side starts immediately from P2.
                 ;; Keep first side visible while dragging.
                 (setq p3u
                   (msap:get-rubber-point
                     p2u
                     "Move cursor for side P2-P3, click P3 <Esc to cancel>: "
                     p1u
                     p2u))

                 (if p3u
                   (progn
                     ;; P4 = P1 + (P3-P2), in current UCS.
                     (setq p4u
                       (list
                         (+ (car p1u)  (- (car p3u)  (car p2u)))
                         (+ (cadr p1u) (- (cadr p3u) (cadr p2u)))
                         (+ (caddr p1u) (- (caddr p3u) (caddr p2u)))))

                     ;; Reject nearly-collinear side vectors.
                     (setq v1u (msa:v- p2u p1u)
                           v2u (msa:v- p3u p2u)
                           area (abs
                                  (msap:cross2
                                    (car v1u) (cadr v1u)
                                    (car v2u) (cadr v2u))))

                     (if (< area 1.0e-9)
                       (prompt
                         "\nThe two sides are collinear; parallelogram was not created."
                       )

                       (progn
                         ;; Draw complete helper frame before the heavier work.
                         (setq frameU (list p1u p2u p3u p4u))
                         (redraw)
                         (apply 'msap:draw-frame-u frameU)

                         ;; Convert geometry to WCS because ActiveX MLeader
                         ;; records / leader vertices are WCS.
                         (setq p1w (trans p1u 1 0)
                               p2w (trans p2u 1 0)
                               p3w (trans p3u 1 0)
                               p4w (trans p4u 1 0))

                         ;; Read the exact same v0.5 records used by MSA.
                         (setq collected
                           (msa:collect-records ss "SHELF_CENTER")
                               records (car collected)
                               skipped (cadr collected))

                         (if (< (length records) 2)
                           (prompt
                             "\nNot enough readable MLeader geometry to distribute."
                           )

                           (progn
                             ;; Classify by ORIGINAL representative arrow point.
                             (setq classified
                               (msap:classify-records
                                 records p1w p2w p3w p4w)
                                   groups  (car classified)
                                   outside (cadr classified)
                                   g0 (nth 0 groups)
                                   g1 (nth 1 groups)
                                   g2 (nth 2 groups)
                                   g3 (nth 3 groups))

                             (prompt
                               (strcat
                                 "\nGroups P1-P2 / P2-P3 / P3-P4 / P4-P1: "
                                 (itoa (length g0)) " / "
                                 (itoa (length g1)) " / "
                                 (itoa (length g2)) " / "
                                 (itoa (length g3))
                                 "."
                               )
                             )

                             (if (> outside 0)
                               (prompt
                                 (strcat
                                   "\n"
                                   (itoa outside)
                                   " arrow point(s) were outside the frame"
                                   " and assigned to the nearest side."
                                 )
                               )
                             )

                             (if (> skipped 0)
                               (prompt
                                 (strcat
                                   "\nSkipped unreadable MLeaders: "
                                   (itoa skipped)
                                   "."
                                 )
                               )
                             )

                             ;; One Undo step for the complete perimeter command.
                             (vl-catch-all-apply 'vla-StartUndoMark (list doc))
                             (setq undoOpen T)

                             ;; Perimeter order:
                             ;; P1 -> P2 -> P3 -> P4 -> P1.
                             (setq r
                               (msap:apply-group
                                 g0 p1w p2w frameU
                                 currentPlacements 1)
                                   currentPlacements (car r)
                                   totalFailed
                                     (+ totalFailed (cadr r)))

                             (setq r
                               (msap:apply-group
                                 g1 p2w p3w frameU
                                 currentPlacements 2)
                                   currentPlacements (car r)
                                   totalFailed
                                     (+ totalFailed (cadr r)))

                             (setq r
                               (msap:apply-group
                                 g2 p3w p4w frameU
                                 currentPlacements 3)
                                   currentPlacements (car r)
                                   totalFailed
                                     (+ totalFailed (cadr r)))

                             (setq r
                               (msap:apply-group
                                 g3 p4w p1w frameU
                                 currentPlacements 4)
                                   currentPlacements (car r)
                                   totalFailed
                                     (+ totalFailed (cadr r)))

                             ;; Remove transient helper graphics.
                             (redraw)

                             (vl-catch-all-apply 'vla-Regen (list doc 1))

                             (if undoOpen
                               (progn
                                 (vl-catch-all-apply
                                   'vla-EndUndoMark
                                   (list doc))
                                 (setq undoOpen nil)
                               )
                             )

                             (prompt
                               (strcat
                                 "\nMLeaderSmartAlign Perimeter complete. "
                                 (itoa (length currentPlacements))
                                 " MLeader(s) placed."
                                 (if (> totalFailed 0)
                                   (strcat
                                     " Failed moves: "
                                     (itoa totalFailed)
                                     "."
                                   )
                                   ""
                                 )
                               )
                             )

                             ;; Successful command owns the new geometry;
                             ;; prevent *error* restoration.
                             (setq currentPlacements nil)
                           )
                         )
                       )
                     )
                   )
                   (prompt "\nMLeaderSmartAlign Perimeter cancelled.")
                 )
               )
               (prompt "\nMLeaderSmartAlign Perimeter cancelled.")
             )
           )
         )
        )
      )

      ;; Safety close for early non-error exits.
      (if undoOpen
        (progn
          (vl-catch-all-apply 'vla-EndUndoMark (list doc))
          (setq undoOpen nil)
        )
      )

      (redraw)
      (princ)
    )
  )
)

(defun c:MSAP ()
  (msap:run)
)

(defun c:MLeaderSmartAlignPerimeter ()
  (msap:run)
)

(prompt
  (strcat
    "\nMLeaderSmartAlign Perimeter v0.1 loaded."
    "\nCommands: MSAP / MLeaderSmartAlignPerimeter"
  )
)
(princ)
