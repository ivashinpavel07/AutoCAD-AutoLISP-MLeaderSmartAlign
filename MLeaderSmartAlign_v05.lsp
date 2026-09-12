;; ============================================================================
;; MLeaderSmartAlign_v05.lsp
;;
;; Smart MULTILEADER alignment for AutoCAD.
;;
;; v0.5 keeps the proven v0.3/v0.4 algorithm and adds TEXT-CENTER-ON-LANDING alignment.
;;
;; In v0.3 the equally-spaced target point was assigned to the representative
;; landing point (the last leader-line vertex).  For MText content this can look
;; uneven because the attachment/landing point is at an edge of the text.
;;
;; v0.5 treats text and block content differently:
;;   - block content (balloon/circle): use the block content point (normally center)
;;   - MText on a landing: use the HORIZONTAL center of the text, projected onto
;;     the landing line.  This keeps the text centered between neighbors without
;;     moving its vertical attachment level away from the shelf/landing.
;;   - fallback: old landing-point behavior.
;;
;; v0.4 aligned to the full visual MText rectangle center.  That improved spacing
;; but could shift two-line text off the common alignment line because MLeader
;; attachment is defined by the landing, not by the rectangle's vertical center.
;;
;; The iterative CATIA-style selection algorithm itself is unchanged.
;;
;; v0.3 added LIVE PREVIEW while the alignment direction is being specified.
;; The core placement algorithm is unchanged from v0.2 and follows the old
;; CATIA VBA project:
;;
;;   for each target position:
;;     - recalculate the angle for EVERY remaining MLeader
;;     - choose the MLeader with the maximum angle
;;     - remove it from the remaining set
;;     - advance to the next target and repeat
;;
;; During live preview the actual MLeader objects are temporarily moved.  Their
;; original arrowhead points are preserved.  Moving the cursor recalculates the
;; complete iterative placement and transitions all selected MLeaders to the new
;; preview positions.  ESC restores the exact original geometry.
;;
;; Commands:
;;   MLeaderSmartAlign  - v0.5 live-preview + text-center-on-landing command
;;   MSA                - short alias for v0.5
;;   MSA5               - explicit v0.5 alias
;;   MSA4               - previous v0.4 full-content-center mode
;;   MSA3               - stable v0.3 landing-point mode for comparison
;;   MSA2               - static two-point v0.2-style command (no live preview)
;;   MSADEBUG           - inspect one MLeader's ActiveX geometry
;;
;; Notes:
;;   - Uses AutoCAD ActiveX/Visual LISP (Windows AutoCAD).
;;   - grread provides raw cursor tracking.  This first preview version does not
;;     attempt to reproduce every native MLEADERALIGN tracking feature such as
;;     full OSNAP / Polar / Ortho behavior during the dynamic stage.
;; ============================================================================

(vl-load-com)

;; Global emergency recovery state used only while live preview owns temporary
;; geometry.  It lets the outer *error* handler restore the last known preview
;; layout if an unexpected error escapes the grread loop.
(setq *msa-live-placements* nil)

;; ---------- basic vector helpers --------------------------------------------

(defun msa:v+ (a b)
  (mapcar '+ a b)
)

(defun msa:v- (a b)
  (mapcar '- a b)
)

(defun msa:v* (v s)
  (mapcar '(lambda (x) (* x s)) v)
)

(defun msa:cross (a b)
  (list
    (- (* (cadr a)  (caddr b)) (* (caddr a) (cadr b)))
    (- (* (caddr a) (car b))   (* (car a)   (caddr b)))
    (- (* (car a)   (cadr b))  (* (cadr a)  (car b)))
  )
)

(defun msa:dot (a b)
  (+ (* (car a)   (car b))
     (* (cadr a)  (cadr b))
     (* (caddr a) (caddr b)))
)

(defun msa:len (v)
  (sqrt (msa:dot v v))
)

(defun msa:unit (v / l)
  (setq l (msa:len v))
  (if (> l 1.0e-12)
    (msa:v* v (/ 1.0 l))
    nil
  )
)

(defun msa:avg-points (pts / n sx sy sz)
  (if pts
    (progn
      (setq n  (float (length pts))
            sx 0.0
            sy 0.0
            sz 0.0)
      (foreach p pts
        (setq sx (+ sx (car p))
              sy (+ sy (cadr p))
              sz (+ sz (caddr p)))
      )
      (list (/ sx n) (/ sy n) (/ sz n))
    )
  )
)

(defun msa:first-point (flat)
  (if (and flat (>= (length flat) 3))
    (list (nth 0 flat) (nth 1 flat) (nth 2 flat))
  )
)

(defun msa:last-point (flat / n)
  (if (and flat (>= (setq n (length flat)) 3))
    (list (nth (- n 3) flat)
          (nth (- n 2) flat)
          (nth (- n 1) flat))
  )
)

(defun msa:replace-first-point (flat p)
  (if (and flat p (>= (length flat) 3))
    (append p (cdddr flat))
    flat
  )
)

;; ---------- COM conversion helpers -----------------------------------------

(defun msa:to-list (x)
  (cond
    ((null x) nil)
    ((= (type x) 'VARIANT)
     (msa:to-list (vlax-variant-value x)))
    ((= (type x) 'SAFEARRAY)
     (vlax-safearray->list x))
    ((listp x) x)
    (T nil)
  )
)

(defun msa:double-array (lst / arr)
  (if lst
    (progn
      (setq arr (vlax-make-safearray vlax-vbDouble
                                     (cons 0 (1- (length lst)))))
      (vlax-safearray-fill arr lst)
      arr
    )
  )
)

(defun msa:get-line-vertices (obj lineIndex / r)
  (setq r
    (vl-catch-all-apply
      'vlax-invoke
      (list obj 'GetLeaderLineVertices lineIndex)
    )
  )
  (if (vl-catch-all-error-p r)
    nil
    (msa:to-list r)
  )
)

(defun msa:set-line-vertices (obj lineIndex flat / arr r)
  (setq arr (msa:double-array flat))
  (if arr
    (progn
      (setq r
        (vl-catch-all-apply
          'vlax-invoke
          (list obj 'SetLeaderLineVertices lineIndex arr)
        )
      )
      ;; Compatibility fallback for Visual LISP builds accepting a list.
      (if (vl-catch-all-error-p r)
        (setq r
          (vl-catch-all-apply
            'vlax-invoke
            (list obj 'SetLeaderLineVertices lineIndex flat)
          )
        )
      )
      (not (vl-catch-all-error-p r))
    )
    nil
  )
)

(defun msa:unique (lst / out)
  (foreach x lst
    (if (not (member x out))
      (setq out (append out (list x)))
    )
  )
  out
)

;; Obtain valid leader-line indexes.  First try LeaderCount +
;; GetLeaderLineIndexes.  If necessary, probe line indexes directly.
(defun msa:get-line-indexes (obj / leaderCount cluster foundClusters r ids lines i v misses)
  (setq lines '())

  (setq leaderCount
    (vl-catch-all-apply 'vla-get-LeaderCount (list obj))
  )

  (if (not (vl-catch-all-error-p leaderCount))
    (progn
      (setq cluster 0
            foundClusters 0)
      (while (and (< foundClusters leaderCount)
                  (< cluster (+ leaderCount 64)))
        (setq r
          (vl-catch-all-apply
            'vlax-invoke
            (list obj 'GetLeaderLineIndexes cluster)
          )
        )
        (if (not (vl-catch-all-error-p r))
          (progn
            (setq ids (msa:to-list r))
            (if ids
              (progn
                (setq lines (append lines ids))
                (setq foundClusters (1+ foundClusters))
              )
            )
          )
        )
        (setq cluster (1+ cluster))
      )
    )
  )

  (setq lines (msa:unique lines))

  (if (null lines)
    (progn
      (setq i 0
            misses 0)
      (while (and (< i 128)
                  (or (null lines) (< misses 16)))
        (setq v (msa:get-line-vertices obj i))
        (if v
          (progn
            (setq lines (append lines (list i)))
            (setq misses 0)
          )
          (setq misses (1+ misses))
        )
        (setq i (1+ i))
      )
    )
  )

  lines
)

;; Result: ((lineIndex originalFlatVertices) ...)
(defun msa:capture-lines (obj / indexes out verts)
  (setq indexes (msa:get-line-indexes obj)
        out '())
  (foreach idx indexes
    (setq verts (msa:get-line-vertices obj idx))
    (if (and verts (>= (length verts) 6))
      (setq out (append out (list (list idx verts))))
    )
  )
  out
)

(defun msa:arrow-points (lineData / out)
  (foreach item lineData
    (setq out (append out (list (msa:first-point (cadr item)))))
  )
  out
)

(defun msa:landing-points (lineData / out)
  (foreach item lineData
    (setq out (append out (list (msa:last-point (cadr item)))))
  )
  out
)

(defun msa:restore-arrowheads (obj lineData / idx original current new ok)
  (setq ok T)
  (foreach item lineData
    (setq idx      (car item)
          original (cadr item)
          current  (msa:get-line-vertices obj idx))
    (if current
      (progn
        (setq new
          (msa:replace-first-point current (msa:first-point original))
        )
        (if (not (msa:set-line-vertices obj idx new))
          (setq ok nil)
        )
      )
      (setq ok nil)
    )
  )
  ok
)

(defun msa:restore-full-lines (obj lineData / ok)
  (setq ok T)
  (foreach item lineData
    (if (not (msa:set-line-vertices obj (car item) (cadr item)))
      (setq ok nil)
    )
  )
  ok
)


;; ---------- content reference point -----------------------------------------
;;
;; Autodesk stores MLeader MText geometry in CONTEXT_DATA:
;;   12 = Text Location
;;   13 = Text Direction
;;   11 = Text Normal Direction
;;   43 = Text Width
;;   44 = Text Height
;;
;; TextJustify tells us which point of the text rectangle Text Location refers
;; to.  From these values we can derive the rectangle center without touching
;; the visible object.

(defun msa:context-data (ename / ed p out)
  (setq ed (entget ename)
        out '())
  (if (setq p (member '(300 . "CONTEXT_DATA{") ed))
    (progn
      (setq p (cdr p))
      (while (and p (not (equal (car p) '(301 . "}"))))
        (setq out (cons (car p) out)
              p   (cdr p))
      )
      (reverse out)
    )
  )
)

(defun msa:context-point (code ctx / a)
  (if (setq a (assoc code ctx))
    (cdr a)
  )
)

(defun msa:context-real (code ctx / a)
  (if (setq a (assoc code ctx))
    (cdr a)
  )
)

;; AcAttachmentPoint numeric order:
;; 1 TL, 2 TC, 3 TR, 4 ML, 5 MC, 6 MR, 7 BL, 8 BC, 9 BR.
;; Returns (horizontalFactor verticalFactor), where factors are multiplied by
;; full width/height and added from the attachment point to the rectangle center.
(defun msa:justify-center-factors (j)
  (cond
    ((= j 1) '( 0.5 -0.5))
    ((= j 2) '( 0.0 -0.5))
    ((= j 3) '(-0.5 -0.5))
    ((= j 4) '( 0.5  0.0))
    ((= j 5) '( 0.0  0.0))
    ((= j 6) '(-0.5  0.0))
    ((= j 7) '( 0.5  0.5))
    ((= j 8) '( 0.0  0.5))
    ((= j 9) '(-0.5  0.5))
    (T       '( 0.0  0.0))
  )
)

(defun msa:mtext-center-from-context (obj ctx / hasText loc xdir normal ydir
                                               width height just jf hx hy)
  (setq hasText (msa:context-real 290 ctx))
  (if (= hasText 1)
    (progn
      (setq loc    (msa:context-point 12 ctx)
            xdir   (msa:context-point 13 ctx)
            normal (msa:context-point 11 ctx)
            width  (msa:context-real 43 ctx)
            height (msa:context-real 44 ctx)
            just   (vl-catch-all-apply 'vla-get-TextJustify (list obj)))

      (if xdir   (setq xdir   (msa:unit xdir)))
      (if normal (setq normal (msa:unit normal)))

      ;; Most 2D drawings have a +Z normal.  Keep this generic for any coplanar
      ;; MLeader by deriving the local text Y axis from normal x text-direction.
      (if (and loc xdir normal
               (numberp width) (numberp height)
               (not (vl-catch-all-error-p just)))
        (progn
          (setq ydir (msa:unit (msa:cross normal xdir))
                jf   (msa:justify-center-factors just)
                hx   (* width  (car jf))
                hy   (* height (cadr jf)))
          (if ydir
            (msa:v+ loc
                    (msa:v+
                      (msa:v* xdir hx)
                      (msa:v* ydir hy)))
          )
        )
      )
    )
  )
)


;; v0.5 placement reference for MText:
;; take only the center ALONG the text/landing direction and keep the
;; perpendicular coordinate of the actual landing.  In geometric terms this is
;; the projection of the text's horizontal center onto a line through LANDING
;; parallel to the MText direction.  Therefore two-line MText remains attached
;; to its shelf at the same vertical level while its visible width is centered.
(defun msa:mtext-center-on-landing (obj ctx landing / hasText loc xdir width just jf hx hcenter along)
  (setq hasText (msa:context-real 290 ctx))
  (if (= hasText 1)
    (progn
      (setq loc   (msa:context-point 12 ctx)
            xdir  (msa:context-point 13 ctx)
            width (msa:context-real 43 ctx)
            just  (vl-catch-all-apply 'vla-get-TextJustify (list obj)))

      (if xdir (setq xdir (msa:unit xdir)))

      (if (and loc xdir landing
               (numberp width)
               (not (vl-catch-all-error-p just)))
        (progn
          (setq jf      (msa:justify-center-factors just)
                hx      (* width (car jf))
                hcenter (msa:v+ loc (msa:v* xdir hx))
                along   (msa:dot (msa:v- hcenter landing) xdir))
          (msa:v+ landing (msa:v* xdir along))
        )
      )
    )
  )
)

;; v0.4 reference retained for direct comparison.
(defun msa:content-reference-v04 (ename obj landing / ctx textCenter blockPos)
  (setq ctx (msa:context-data ename))
  (if ctx
    (setq textCenter (msa:mtext-center-from-context obj ctx))
  )
  (cond
    (textCenter
     (list textCenter "TEXTCENTER"))
    ((and ctx
          (= (msa:context-real 296 ctx) 1)
          (setq blockPos (msa:context-point 15 ctx)))
     (list blockPos "BLOCKPOINT"))
    (T
     (list landing "LANDING"))
  )
)

;; v0.5 reference:
;; MText -> horizontal content center projected onto its landing level.
;; Block -> block content point (typically the center for balloon symbols).
;; Fallback -> landing.
(defun msa:content-reference-v05 (ename obj landing / ctx shelfCenter blockPos)
  (setq ctx (msa:context-data ename))
  (if ctx
    (setq shelfCenter (msa:mtext-center-on-landing obj ctx landing))
  )
  (cond
    (shelfCenter
     (list shelfCenter "TEXTLANDINGCENTER"))
    ((and ctx
          (= (msa:context-real 296 ctx) 1)
          (setq blockPos (msa:context-point 15 ctx)))
     (list blockPos "BLOCKPOINT"))
    (T
     (list landing "LANDING"))
  )
)

;; Default reference used by diagnostics is the newest behavior.
(defun msa:content-reference (ename obj landing)
  (msa:content-reference-v05 ename obj landing)
)

;; ---------- records ---------------------------------------------------------
;; Record layout:
;;   0 handle
;;   1 VLA object
;;   2 captured ORIGINAL leader-line data
 ;;   3 ORIGINAL placement reference point
;;        - v0.5: text center projected onto landing / block point / fallback
;;        - v0.4: full MText center / block point / fallback
;;        - v0.3: representative landing point
;;   4 ORIGINAL representative arrow point
;;   5 reference kind: "TEXTLANDINGCENTER" / "TEXTCENTER" / "BLOCKPOINT" / "LANDING"
;;   6 ORIGINAL representative landing point (diagnostic / fallback)

(defun msa:make-record (ename refMode / obj data arrows lands arrow landing handle
                               refInfo reference refKind)
  (setq obj  (vlax-ename->vla-object ename)
        data (msa:capture-lines obj))
  (if data
    (progn
      (setq arrows  (msa:arrow-points data)
            lands   (msa:landing-points data)
            arrow   (msa:avg-points arrows)
            landing (msa:avg-points lands)
            handle  (vla-get-Handle obj))

      (cond
        ((= (strcase refMode) "SHELF_CENTER")
         (setq refInfo   (msa:content-reference-v05 ename obj landing)
               reference (car refInfo)
               refKind   (cadr refInfo)))
        ((= (strcase refMode) "CENTER")
         (setq refInfo   (msa:content-reference-v04 ename obj landing)
               reference (car refInfo)
               refKind   (cadr refInfo)))
        (T
         (setq reference landing
               refKind   "LANDING"))
      )

      (list handle obj data reference arrow refKind landing)
    )
  )
)

(defun msa:collect-records (ss refMode / n i en rec records skipped)
  (setq n (sslength ss)
        i 0
        records '()
        skipped 0)
  (repeat n
    (setq en  (ssname ss i)
          rec (msa:make-record en refMode))
    (if rec
      (setq records (append records (list rec)))
      (setq skipped (1+ skipped))
    )
    (setq i (1+ i))
  )
  (list records skipped)
)

(defun msa:reference-count (records kind / n)
  (setq n 0)
  (foreach rec records
    (if (= (nth 5 rec) kind)
      (setq n (1+ n))
    )
  )
  n
)

;; ---------- iterative CATIA-style selector ---------------------------------

;; Return cosine of the angle between alignment direction and the vector from
;; current target to arrow.  For angles 0..pi:
;;     maximum angle <=> minimum cosine.
(defun msa:angle-cos-score (dir target arrow / v l c)
  (setq v (msa:v- arrow target)
        l (msa:len v))
  (if (< l 1.0e-12)
    1.0
    (progn
      (setq c (/ (msa:dot dir v) l))
      (cond
        ((> c 1.0)  1.0)
        ((< c -1.0) -1.0)
        (T c)
      )
    )
  )
)

;; Exact structural equivalent of the VBA inner For-loop.
(defun msa:choose-for-target (records dir target / best bestScore rec score)
  (setq best nil
        bestScore nil)
  (foreach rec records
    (setq score (msa:angle-cos-score dir target (nth 4 rec)))
    (if (or (null best)
            (< score (- bestScore 1.0e-12)))
      (setq best rec
            bestScore score)
    )
  )
  best
)

(defun msa:remove-record (target records / removed out rec)
  (setq removed nil
        out '())
  (foreach rec records
    (if (and (not removed) (eq rec target))
      (setq removed T)
      (setq out (append out (list rec)))
    )
  )
  out
)

;; Compute the complete placement WITHOUT modifying the drawing.
;; Return:
;;   (placements sequence direction distance)
;; where placements = ((record targetPoint) ...)
(defun msa:compute-placements (records p1 p2 / vec dist dir step target remaining
                                      selected placements sequence)
  (setq vec  (msa:v- p2 p1)
        dist (msa:len vec)
        dir  (msa:unit vec))

  (if (and dir (> dist 1.0e-9) records)
    (progn
      ;; Matches the CATIA VBA exactly: N balloons occupy N interior points,
      ;; so the complete vector is divided into N+1 intervals.
      (setq step       (/ dist (float (1+ (length records))))
            target     (msa:v+ p1 (msa:v* dir step))
            remaining  records
            placements '()
            sequence   '())

      (while remaining
        ;; IMPORTANT: recalculate against ALL remaining MLeaders at EVERY step.
        (setq selected (msa:choose-for-target remaining dir target))
        (if selected
          (progn
            (setq placements (cons (list selected target) placements)
                  sequence   (cons (car selected) sequence)
                  remaining  (msa:remove-record selected remaining)
                  target     (msa:v+ target (msa:v* dir step)))
          )
          (setq remaining nil)
        )
      )

      (list (reverse placements)
            (reverse sequence)
            dir
            dist)
    )
  )
)

;; ---------- movement / preview transition ----------------------------------

(defun msa:placement-target (rec placements / handle answer)
  (setq handle (car rec)
        answer nil)
  (foreach pl placements
    (if (= handle (car (car pl)))
      (setq answer (cadr pl))
    )
  )
  answer
)

;; Move one MLeader from one representative landing point to another and then
;; restore every arrowhead to its ORIGINAL location.
(defun msa:move-record-between (rec fromPt toPt / obj data result)
  (setq obj  (nth 1 rec)
        data (nth 2 rec))

  (if (equal fromPt toPt 1.0e-10)
    T
    (progn
      (setq result
        (vl-catch-all-apply
          'vla-Move
          (list obj (vlax-3d-point fromPt) (vlax-3d-point toPt))
        )
      )
      (if (vl-catch-all-error-p result)
        nil
        (progn
          (msa:restore-arrowheads obj data)
          (vl-catch-all-apply 'vla-Update (list obj))
          T
        )
      )
    )
  )
)

;; Transition from old preview layout to new preview layout.
;; nil oldPlacements means all objects are at their original positions.
(defun msa:transition-placements (records oldPlacements newPlacements / failed rec fromPt toPt)
  (setq failed 0)
  (foreach rec records
    (setq fromPt (msa:placement-target rec oldPlacements)
          toPt   (msa:placement-target rec newPlacements))
    (if (null fromPt)
      (setq fromPt (nth 3 rec))
    )
    (if (null toPt)
      (setq toPt (nth 3 rec))
    )
    (if (not (msa:move-record-between rec fromPt toPt))
      (setq failed (1+ failed))
    )
  )
  failed
)

;; Restore exact original state after a live preview/cancel/error.
(defun msa:restore-originals (records currentPlacements / rec obj data fromPt originalLanding result)
  (foreach rec records
    (setq obj             (nth 1 rec)
          data            (nth 2 rec)
          originalLanding (nth 3 rec)
          fromPt          (msa:placement-target rec currentPlacements))
    (if (null fromPt)
      (setq fromPt originalLanding)
    )

    (if (not (equal fromPt originalLanding 1.0e-10))
      (setq result
        (vl-catch-all-apply
          'vla-Move
          (list obj (vlax-3d-point fromPt) (vlax-3d-point originalLanding))
        )
      )
    )

    ;; Full original vertices make cancellation robust even after many frames.
    (msa:restore-full-lines obj data)
    (vl-catch-all-apply 'vla-Update (list obj))
  )
  T
)

(defun msa:preview-interval-ms (n)
  ;; Adaptive throttling.  Large selections perform thousands of angle tests
  ;; plus many ActiveX updates per frame, so do not process every mouse packet.
  (cond
    ((<= n 15) 25)
    ((<= n 40) 45)
    ((<= n 80) 75)
    (T          110)
  )
)

(defun msa:ms-due-p (lastMs nowMs interval)
  (or (null lastMs)
      (< nowMs lastMs) ; MILLISECS wrapped around
      (>= (- nowMs lastMs) interval))
)

;; Interactive direction stage.
;; Returns:
;;   (T finalPointWCS finalPlacements sequence failed previewFrames)
;; or nil on cancel.
;;
;; Actual MLeader geometry is used as the preview.  No temporary copies are
;; created.  Transitioning from one preview frame to the next means each object
;; is translated directly from its previous target to its new target.
(defun msa:live-direction (doc records p1u p1w / event code key caught done cancelled
                               accepted lastMouseU finalU finalW currentPlacements
                               calc newPlacements newSequence failed totalFailed
                               nowMs lastMs interval frames)

  (setq done              nil
        cancelled         nil
        accepted          nil
        lastMouseU        nil
        currentPlacements nil
        lastMs            nil
        interval          (msa:preview-interval-ms (length records))
        frames            0
        totalFailed       0)

  (prompt
    (strcat
      "\nSpecify direction: move cursor for live preview, click to accept"
      " <Esc to cancel>: "
    )
  )

  (while (not done)
    ;; Catch ESC so we can restore the preview before leaving the command.
    (setq caught (vl-catch-all-apply 'grread (list T 15 0)))
    (if (vl-catch-all-error-p caught)
      (setq event '(2 27))
      (setq event caught)
    )

    (setq code (car event)
          key  (cadr event))

    (cond
      ;; Mouse movement / drag coordinate (current UCS).
      ((= code 5)
       (setq lastMouseU key
             nowMs (getvar "MILLISECS"))
       (if (and (> (distance p1u lastMouseU) 1.0e-9)
                (msa:ms-due-p lastMs nowMs interval))
         (progn
           (setq finalW (trans lastMouseU 1 0)
                 calc   (msa:compute-placements records p1w finalW))
           (if calc
             (progn
               (setq newPlacements (car calc)
                     newSequence   (cadr calc)
                     failed        (msa:transition-placements
                                     records
                                     currentPlacements
                                     newPlacements))
               (setq totalFailed       (+ totalFailed failed)
                     currentPlacements newPlacements
                     *msa-live-placements* currentPlacements
                     lastMs            nowMs
                     frames            (1+ frames))

               ;; Update the graphics without a full database regeneration on
               ;; every mouse packet. vla-Update was called per object above.
               (redraw)
               ;; Yellow highlighted guide, visually close to native dragging.
               (grdraw p1u lastMouseU 2 1)
             )
           )
         )
       )
      )

      ;; Left mouse button: accept the clicked direction point.
      ((= code 3)
       (setq finalU key)
       (if (> (distance p1u finalU) 1.0e-9)
         (setq accepted T
               done T)
       )
      )

      ;; Keyboard input.
      ((= code 2)
       (cond
         ;; ESC
         ((= key 27)
          (setq cancelled T
                done T))
         ;; ENTER or SPACE accepts the last tracked cursor position.
         ((member key '(13 32))
          (if (and lastMouseU (> (distance p1u lastMouseU) 1.0e-9))
            (setq finalU lastMouseU
                  accepted T
                  done T)
          )
         )
       )
      )

      ;; Secondary mouse button - cancel, avoiding an accidental commit.
      ((= code 25)
       (setq cancelled T
             done T))
    )
  )

  (cond
    (cancelled
     (msa:restore-originals records currentPlacements)
     (setq *msa-live-placements* nil)
     (vl-catch-all-apply 'vla-Regen (list doc 1))
     (prompt "\nMLeaderSmartAlign cancelled. Original geometry restored.")
     nil)

    (accepted
     (setq finalW (trans finalU 1 0)
           calc   (msa:compute-placements records p1w finalW))
     (if calc
       (progn
         (setq newPlacements (car calc)
               newSequence   (cadr calc)
               failed        (msa:transition-placements
                               records
                               currentPlacements
                               newPlacements)
               totalFailed   (+ totalFailed failed)
               currentPlacements newPlacements
               *msa-live-placements* currentPlacements)
         (vl-catch-all-apply 'vla-Regen (list doc 1))
         (list T finalW currentPlacements newSequence totalFailed frames)
       )
       (progn
         (msa:restore-originals records currentPlacements)
         (setq *msa-live-placements* nil)
         (vl-catch-all-apply 'vla-Regen (list doc 1))
         nil
       )
     )
    )
  )
)

;; ---------- live commands ---------------------------------------------------

(defun msa:run-live (version refMode / *error* acad doc undoOpen ss n p1u p1w
                                      collected records skipped result failed frames
                                      nText nBlock nLanding)

  (setq acad (vlax-get-acad-object)
        doc  (vla-get-ActiveDocument acad)
        undoOpen nil
        records nil)

  (defun *error* (msg)
    ;; If an unexpected error occurs during dragging, restore original geometry.
    (if (and records *msa-live-placements*)
      (progn
        (msa:restore-originals records *msa-live-placements*)
        (setq *msa-live-placements* nil)
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
      (prompt (strcat "\nMLeaderSmartAlign error: " msg))
    )
    (princ)
  )

  (prompt
    (strcat
      "\nMLeaderSmartAlign " version
      " - iterative CATIA-style alignment with LIVE PREVIEW"
      (cond
        ((= (strcase refMode) "SHELF_CENTER") " + TEXT CENTER ON LANDING.")
        ((= (strcase refMode) "CENTER")       " + CONTENT CENTER (v0.4).")
        (T                                      " + LANDING reference."))
    )
  )

  (setq ss (ssget '((0 . "MULTILEADER"))))

  (cond
    ((null ss)
     (prompt "\nNo MULTILEADER objects selected."))

    ((< (setq n (sslength ss)) 2)
     (prompt "\nSelect at least two MULTILEADER objects."))

    (T
     (setq p1u (getpoint "\nSpecify alignment start point: "))
     (if p1u
       (progn
         (setq p1w       (trans p1u 1 0)
               collected (msa:collect-records ss refMode)
               records   (car collected)
               skipped   (cadr collected))

         (if (< (length records) 2)
           (prompt "\nNot enough readable MLeader geometry to align.")
           (progn
             (if (member (strcase refMode) '("SHELF_CENTER" "CENTER"))
               (progn
                 (setq nText
                        (+ (msa:reference-count records "TEXTLANDINGCENTER")
                           (msa:reference-count records "TEXTCENTER"))
                       nBlock   (msa:reference-count records "BLOCKPOINT")
                       nLanding (msa:reference-count records "LANDING"))
                 (prompt
                   (strcat
                     "\nReference points: text=" (itoa nText)
                     ", block point=" (itoa nBlock)
                     ", landing fallback=" (itoa nLanding) "."
                   )
                 )
               )
             )

             (vla-StartUndoMark doc)
             (setq undoOpen T)

             (setq *msa-live-placements* nil
                   result (msa:live-direction doc records p1u p1w))

             (if result
               (progn
                 ;; Accepted final placement is already on screen.
                 (setq *msa-live-placements* nil
                       failed (nth 4 result)
                       frames (nth 5 result))
                 (prompt
                   (strcat
                     "\nDone. Aligned: " (itoa (length records))
                     (if (> skipped 0)
                       (strcat ", skipped: " (itoa skipped))
                       "")
                     (if (> failed 0)
                       (strcat ", preview/update failures: " (itoa failed))
                       "")
                     ". Live preview frames: " (itoa frames) "."
                   )
                 )
               )
               ;; live-direction already restored originals on cancel.
               (setq *msa-live-placements* nil)
             )

             (if undoOpen
               (progn
                 (vla-EndUndoMark doc)
                 (setq undoOpen nil)
               )
             )
           )
         )
       )
     )
    )
  )
  (princ)
)

(defun msa:run-v05 ()
  (msa:run-live "v0.5" "SHELF_CENTER")
)

(defun msa:run-v04 ()
  (msa:run-live "v0.4" "CENTER")
)

(defun msa:run-v03 ()
  (msa:run-live "v0.3" "LANDING")
)

;; ---------- static v0.2-style command retained for comparison ---------------

(defun msa:run-static (/ *error* acad doc undoOpen ss n p1u p2u p1w p2w
                          collected records skipped calc placements sequence failed)
  (setq acad (vlax-get-acad-object)
        doc  (vla-get-ActiveDocument acad)
        undoOpen nil)

  (defun *error* (msg)
    (if undoOpen
      (progn
        (vl-catch-all-apply 'vla-EndUndoMark (list doc))
        (setq undoOpen nil)
      )
    )
    (if (and msg
             (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")))
      (prompt (strcat "\nMLeaderSmartAlign error: " msg))
    )
    (princ)
  )

  (prompt "\nMLeaderSmartAlign static mode (v0.2 algorithm, no live preview).")
  (setq ss (ssget '((0 . "MULTILEADER"))))

  (cond
    ((null ss)
     (prompt "\nNo MULTILEADER objects selected."))
    ((< (setq n (sslength ss)) 2)
     (prompt "\nSelect at least two MULTILEADER objects."))
    (T
     (setq p1u (getpoint "\nSpecify first alignment point: "))
     (if p1u
       (setq p2u (getpoint p1u "\nSpecify second alignment point: "))
     )
     (if (and p1u p2u)
       (progn
         (setq p1w       (trans p1u 1 0)
               p2w       (trans p2u 1 0)
               collected (msa:collect-records ss "LANDING")
               records   (car collected)
               skipped   (cadr collected)
               calc      (msa:compute-placements records p1w p2w))

         (if (or (< (length records) 2) (null calc))
           (prompt "\nUnable to calculate alignment geometry.")
           (progn
             (vla-StartUndoMark doc)
             (setq undoOpen T
                   placements (car calc)
                   sequence   (cadr calc)
                   failed     (msa:transition-placements records nil placements))
             (vl-catch-all-apply 'vla-Regen (list doc 1))
             (prompt
               (strcat
                 "\nDone. Aligned: " (itoa (length records))
                 (if (> skipped 0)
                   (strcat ", skipped: " (itoa skipped))
                   "")
                 (if (> failed 0)
                   (strcat ", failed: " (itoa failed))
                   "")
                 "."
               )
             )
             (prompt (strcat "\nPlacement order: " (vl-princ-to-string sequence)))
             (vla-EndUndoMark doc)
             (setq undoOpen nil)
           )
         )
       )
     )
    )
  )
  (princ)
)

;; ---------- command aliases -------------------------------------------------

(defun c:MLeaderSmartAlign ()
  (msa:run-v05)
)

(defun c:MSA ()
  (msa:run-v05)
)

(defun c:MSA5 ()
  (msa:run-v05)
)

(defun c:MSA4 ()
  (msa:run-v04)
)

(defun c:MSA3 ()
  (msa:run-v03)
)

(defun c:MSA2 ()
  (msa:run-static)
)

;; ---------- diagnostic helper ----------------------------------------------

(defun c:MSADEBUG (/ en obj cnt indexes verts data arrows lands landing refInfo ctx
                      tc tlc just width height)
  (vl-load-com)
  (if (setq en (car (entsel "\nSelect MULTILEADER to inspect: ")))
    (if (= "MULTILEADER" (cdr (assoc 0 (entget en))))
      (progn
        (setq obj     (vlax-ename->vla-object en)
              cnt     (vl-catch-all-apply 'vla-get-LeaderCount (list obj))
              indexes (msa:get-line-indexes obj)
              data    (msa:capture-lines obj)
              arrows  (msa:arrow-points data)
              lands   (msa:landing-points data)
              landing (msa:avg-points lands)
              refInfo (msa:content-reference en obj landing)
              ctx     (msa:context-data en)
              tc      (msa:mtext-center-from-context obj ctx)
              tlc     (msa:mtext-center-on-landing obj ctx landing)
              just    (vl-catch-all-apply 'vla-get-TextJustify (list obj))
              width   (msa:context-real 43 ctx)
              height  (msa:context-real 44 ctx))

        (prompt (strcat "\nHandle: " (vla-get-Handle obj)))
        (if (not (vl-catch-all-error-p cnt))
          (prompt (strcat "\nLeader clusters: " (itoa cnt)))
        )
        (prompt
          (strcat "\nLeader-line indexes: " (vl-princ-to-string indexes))
        )
        (prompt
          (strcat
            "\nPlacement reference: " (cadr refInfo)
            " " (vl-princ-to-string (car refInfo))
          )
        )
        (if tlc
          (prompt
            (strcat
              "\nMText center on landing: " (vl-princ-to-string tlc)
            )
          )
        )
        (if tc
          (prompt
            (strcat
              "\nMText full-box center (v0.4): " (vl-princ-to-string tc)
              " | width=" (vl-princ-to-string width)
              " | height=" (vl-princ-to-string height)
              " | TextJustify="
              (if (vl-catch-all-error-p just) "?" (itoa just))
            )
          )
        )
        (foreach idx indexes
          (setq verts (msa:get-line-vertices obj idx))
          (prompt
            (strcat
              "\n  Line " (itoa idx)
              " | arrow=" (vl-princ-to-string (msa:first-point verts))
              " | landing=" (vl-princ-to-string (msa:last-point verts))
              " | vertices=" (vl-princ-to-string verts)
            )
          )
        )
      )
      (prompt "\nSelected object is not a MULTILEADER.")
    )
  )
  (princ)
)

(prompt
  "\nMLeaderSmartAlign v0.5 loaded. Commands: MLeaderSmartAlign, MSA, MSA5, MSA4, MSA3, MSA2, MSADEBUG."
)
(princ)
