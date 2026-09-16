;; ============================================================================
;; MLeaderSmartAlign_v07_fix1.lsp
;;
;; STANDALONE version.
;;
;; This file embeds the proven SmartAlign core from v0.5 and the working
;; LINE -> optional PERIMETER live workflow from v0.6.
;;
;; No other .LSP file is required.
;;
;; Workflow:
;;   1) Select MULTILEADER objects.
;;   2) Pick P1.
;;   3) Move cursor -> LIVE linear SmartAlign preview.
;;   4) Click P2 -> linear result becomes the baseline.
;;   5) ESC/right-click -> keep LINEAR result.
;;      OR move cursor sideways -> LIVE PERIMETER preview.
;;   6) Click P3 -> accept PERIMETER result.
;;      ESC during perimeter preview -> return to LINEAR result.
;;
;; User command:
;;   MSA7
;;
;; Windows AutoCAD / Visual LISP / ActiveX.
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

;; 2D geometry helpers for the perimeter stage
;; ----------------------------------------------------------------------------

(defun msa6:cross2 (ax ay bx by)
  (- (* ax by) (* ay bx))
)

(defun msa6:point-in-triangle-p (p a b c / eps c1 c2 c3)
  (setq eps 1.0e-9
        c1 (msa6:cross2
             (- (car b) (car a))
             (- (cadr b) (cadr a))
             (- (car p) (car a))
             (- (cadr p) (cadr a)))
        c2 (msa6:cross2
             (- (car c) (car b))
             (- (cadr c) (cadr b))
             (- (car p) (car b))
             (- (cadr p) (cadr b)))
        c3 (msa6:cross2
             (- (car a) (car c))
             (- (cadr a) (cadr c))
             (- (car p) (car c))
             (- (cadr p) (cadr c))))

  (or
    (and (>= c1 (- eps)) (>= c2 (- eps)) (>= c3 (- eps)))
    (and (<= c1 eps)     (<= c2 eps)     (<= c3 eps))
  )
)

(defun msa6:point-segment-dist2 (p a b / vx vy wx wy len2 param qx qy dx dy)
  (setq vx (- (car b) (car a))
        vy (- (cadr b) (cadr a))
        wx (- (car p) (car a))
        wy (- (cadr p) (cadr a))
        len2 (+ (* vx vx) (* vy vy)))

  (if (< len2 1.0e-18)
    (+ (* wx wx) (* wy wy))
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

(defun msa6:nearest-side (p p1 p2 p3 p4 / d0 d1 d2 d3 best bestd)
  (setq d0 (msa6:point-segment-dist2 p p1 p2)
        d1 (msa6:point-segment-dist2 p p2 p3)
        d2 (msa6:point-segment-dist2 p p3 p4)
        d3 (msa6:point-segment-dist2 p p4 p1)
        best 0
        bestd d0)

  (if (< d1 bestd) (setq best 1 bestd d1))
  (if (< d2 bestd) (setq best 2 bestd d2))
  (if (< d3 bestd) (setq best 3 bestd d3))
  best
)

;; Return side index 0..3.
;; Boundary points and points outside the parallelogram use nearest side.
(defun msa6:classify-point (p p1 p2 p3 p4 c / i0 i1 i2 i3 matches)
  (setq i0 (msa6:point-in-triangle-p p p1 p2 c)
        i1 (msa6:point-in-triangle-p p p2 p3 c)
        i2 (msa6:point-in-triangle-p p p3 p4 c)
        i3 (msa6:point-in-triangle-p p p4 p1 c)
        matches (+ (if i0 1 0)
                   (if i1 1 0)
                   (if i2 1 0)
                   (if i3 1 0)))

  (if (= matches 1)
    (cond
      (i0 0)
      (i1 1)
      (i2 2)
      (T  3))
    (msa6:nearest-side p p1 p2 p3 p4)
  )
)

(defun msa6:append-to-group (rec idx groups / g0 g1 g2 g3)
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

;; Record item 4 is the ORIGINAL representative arrow point captured by v0.5.
(defun msa6:classify-records (records p1 p2 p3 p4 / c groups rec idx)
  (setq c
    (list
      (/ (+ (car p1)  (car p3))  2.0)
      (/ (+ (cadr p1) (cadr p3)) 2.0)
      (/ (+ (caddr p1) (caddr p3)) 2.0))
    groups (list '() '() '() '()))

  (foreach rec records
    (setq idx (msa6:classify-point (nth 4 rec) p1 p2 p3 p4 c)
          groups (msa6:append-to-group rec idx groups))
  )
  groups
)

;; ----------------------------------------------------------------------------
;; UCS helper geometry / transient graphics
;; ----------------------------------------------------------------------------

(defun msa6:p4 (p1 p2 p3)
  (mapcar '+ p1 (mapcar '- p3 p2))
)

(defun msa6:valid-perimeter-p (p1 p2 p3 / ax ay bx by len1 len2 crossv)
  (setq ax (- (car p2) (car p1))
        ay (- (cadr p2) (cadr p1))
        bx (- (car p3) (car p2))
        by (- (cadr p3) (cadr p2))
        len1 (sqrt (+ (* ax ax) (* ay ay)))
        len2 (sqrt (+ (* bx bx) (* by by)))
        crossv (abs (msa6:cross2 ax ay bx by)))

  (and (> len1 1.0e-9)
       (> len2 1.0e-9)
       ;; Reject an almost zero-area parallelogram.
       (> crossv (* 1.0e-6 len1 len2)))
)

(defun msa6:lerp-point (a b ratio)
  (mapcar
    '(lambda (x y) (+ x (* ratio (- y x))))
    a b)
)

(defun msa6:gr-dashed (a b / divisions i r1 r2)
  (setq divisions 40
        i 0)
  (repeat divisions
    (if (= (rem i 2) 0)
      (progn
        (setq r1 (/ (float i) divisions)
              r2 (/ (float (1+ i)) divisions))
        ;; Color 7 is adaptive: black/white depending on AutoCAD background.
        (grdraw (msa6:lerp-point a b r1)
                (msa6:lerp-point a b r2)
                7
                0)
      )
    )
    (setq i (1+ i))
  )
)

(defun msa6:draw-frame-u (p1 p2 p3 p4)
  (msa6:gr-dashed p1 p2)
  (msa6:gr-dashed p2 p3)
  (msa6:gr-dashed p3 p4)
  (msa6:gr-dashed p4 p1)
  (msa6:gr-dashed p1 p3)
  (msa6:gr-dashed p2 p4)
)

;; ----------------------------------------------------------------------------
;; Build a complete perimeter placement list WITHOUT modifying the drawing.
;; Each side reuses the exact v0.5 iterative SmartAlign computation.
;; ----------------------------------------------------------------------------

(defun msa6:compute-perimeter-placements
       (records p1 p2 p3 p4 / groups g0 g1 g2 g3 calc out)
  (setq groups (msa6:classify-records records p1 p2 p3 p4)
        g0 (nth 0 groups)
        g1 (nth 1 groups)
        g2 (nth 2 groups)
        g3 (nth 3 groups)
        out '())

  (if g0
    (progn
      (setq calc (msa:compute-placements g0 p1 p2))
      (if calc (setq out (append out (car calc))))
    )
  )
  (if g1
    (progn
      (setq calc (msa:compute-placements g1 p2 p3))
      (if calc (setq out (append out (car calc))))
    )
  )
  (if g2
    (progn
      (setq calc (msa:compute-placements g2 p3 p4))
      (if calc (setq out (append out (car calc))))
    )
  )
  (if g3
    (progn
      (setq calc (msa:compute-placements g3 p4 p1))
      (if calc (setq out (append out (car calc))))
    )
  )

  (if (= (length out) (length records))
    out
    nil
  )
)

;; ----------------------------------------------------------------------------
;; Stage 1: v0.5-style LIVE linear preview.
;;
;; Returns:
;;   (T p2U p2W linearPlacements sequence failed frames)
;; or nil on ESC / cancel (original geometry restored).
;; ----------------------------------------------------------------------------

(defun msa6:live-line-stage
       (doc records p1u p1w / caught event code key done cancelled accepted
                              lastMouseU p2u p2w currentPlacements calc
                              newPlacements sequence failed totalFailed
                              nowMs lastMs interval frames)
  (setq done nil
        cancelled nil
        accepted nil
        lastMouseU nil
        currentPlacements nil
        lastMs nil
        interval (msa:preview-interval-ms (length records))
        frames 0
        totalFailed 0)

  (prompt
    "\nStage 1/2 - LINE: move cursor for LIVE preview, click P2 to fix line <Esc cancels>: "
  )

  (while (not done)
    (setq caught (vl-catch-all-apply 'grread (list T 15 0)))
    (if (vl-catch-all-error-p caught)
      (setq event '(2 27))
      (setq event caught)
    )

    (setq code (car event)
          key  (cadr event))

    (cond
      ;; MouseMove
      ((= code 5)
       (setq lastMouseU key
             nowMs (getvar "MILLISECS"))
       (if (and (> (distance p1u lastMouseU) 1.0e-9)
                (msa:ms-due-p lastMs nowMs interval))
         (progn
           (setq p2w (trans lastMouseU 1 0)
                 calc (msa:compute-placements records p1w p2w))
           (if calc
             (progn
               (setq newPlacements (car calc)
                     sequence (cadr calc)
                     failed (msa:transition-placements
                              records currentPlacements newPlacements)
                     totalFailed (+ totalFailed failed)
                     currentPlacements newPlacements
                     *msa6-current-placements* currentPlacements
                     lastMs nowMs
                     frames (1+ frames))
               (redraw)
               ;; Same yellow live guide style as v0.5.
               (grdraw p1u lastMouseU 2 1)
             )
           )
         )
       )
      )

      ;; Left click -> fix P2
      ((= code 3)
       (if (> (distance p1u key) 1.0e-9)
         (setq p2u key
               accepted T
               done T)
       )
      )

      ;; Keyboard
      ((= code 2)
       (cond
         ((= key 27)
          (setq cancelled T done T))
         ((member key '(13 32))
          (if (and lastMouseU (> (distance p1u lastMouseU) 1.0e-9))
            (setq p2u lastMouseU
                  accepted T
                  done T)
          )
         )
       )
      )

      ;; Right / secondary mouse button -> cancel before P2.
      ((= code 25)
       (setq cancelled T done T))
    )
  )

  (redraw)

  (cond
    (cancelled
     (msa:restore-originals records currentPlacements)
     (setq *msa6-current-placements* nil)
     (vl-catch-all-apply 'vla-Regen (list doc 1))
     (prompt "\nMLeaderSmartAlign v0.6 cancelled. Original geometry restored.")
     nil)

    (accepted
     ;; Recalculate once at the exact clicked P2.
     (setq p2w (trans p2u 1 0)
           calc (msa:compute-placements records p1w p2w))
     (if calc
       (progn
         (setq newPlacements (car calc)
               sequence (cadr calc)
               failed (msa:transition-placements
                        records currentPlacements newPlacements)
               totalFailed (+ totalFailed failed)
               currentPlacements newPlacements
               *msa6-current-placements* currentPlacements)
         (vl-catch-all-apply 'vla-Regen (list doc 1))
         (list T p2u p2w currentPlacements sequence totalFailed frames)
       )
       (progn
         (msa:restore-originals records currentPlacements)
         (vl-catch-all-apply 'vla-Regen (list doc 1))
         nil
       )
     )
    )
  )
)

;; ----------------------------------------------------------------------------
;; Stage 2: optional LIVE perimeter preview.
;;
;; Baseline = already accepted LINEAR layout.
;;
;; Returns:
;;   ("PERIMETER" finalPlacements failed frames)
;; or
;;   ("LINE" linearPlacements failed frames)
;;
;; ESC/right-click ALWAYS keeps/restores the linear baseline.
;; ----------------------------------------------------------------------------

(defun msa6:live-perimeter-stage
       (doc records p1u p2u p1w p2w linearPlacements
        / caught event code key done accepted keepLine
          lastMouseU lastValidU p3u p4u p3w p4w
          currentPlacements newPlacements
          failed totalFailed nowMs lastMs interval frames)

  (setq done nil
        accepted nil
        keepLine nil
        lastMouseU nil
        lastValidU nil
        currentPlacements linearPlacements
        lastMs nil
        interval (msa:preview-interval-ms (length records))
        frames 0
        totalFailed 0)

  (prompt
    (strcat
      "\nStage 2/2 - PERIMETER (optional): move cursor sideways for LIVE preview,"
      " click P3 to accept <Esc keeps LINEAR>: "
    )
  )

  ;; Keep the accepted P1-P2 guide visible when stage 2 starts.
  (redraw)
  (msa6:gr-dashed p1u p2u)

  (while (not done)
    (setq caught (vl-catch-all-apply 'grread (list T 15 0)))
    (if (vl-catch-all-error-p caught)
      (setq event '(2 27))
      (setq event caught)
    )

    (setq code (car event)
          key  (cadr event))

    (cond
      ;; MouseMove -> live perimeter
      ((= code 5)
       (setq lastMouseU key
             nowMs (getvar "MILLISECS"))

       (if (msa:ms-due-p lastMs nowMs interval)
         (progn
           (if (msa6:valid-perimeter-p p1u p2u lastMouseU)
             (progn
               (setq p3u lastMouseU
                     p4u (msa6:p4 p1u p2u p3u)
                     p3w (trans p3u 1 0)
                     p4w (trans p4u 1 0)
                     newPlacements
                       (msa6:compute-perimeter-placements
                         records p1w p2w p3w p4w))

               (if newPlacements
                 (progn
                   (setq failed
                     (msa:transition-placements
                       records currentPlacements newPlacements)
                     totalFailed (+ totalFailed failed)
                     currentPlacements newPlacements
                     *msa6-current-placements* currentPlacements
                     lastValidU p3u
                     lastMs nowMs
                     frames (1+ frames))

                   (redraw)
                   (msa6:draw-frame-u p1u p2u p3u p4u)
                 )
               )
             )

             ;; Cursor moved back to an invalid/near-collinear shape:
             ;; return to the already accepted linear baseline rather than
             ;; leaving a stale perimeter preview on screen.
             (progn
               (setq failed
                 (msa:transition-placements
                   records currentPlacements linearPlacements)
                 totalFailed (+ totalFailed failed)
                 currentPlacements linearPlacements
                 *msa6-current-placements* currentPlacements
                 lastValidU nil
                 lastMs nowMs)
               (redraw)
               (msa6:gr-dashed p1u p2u)
               (if (> (distance p2u lastMouseU) 1.0e-9)
                 (msa6:gr-dashed p2u lastMouseU)
               )
             )
           )
         )
       )
      )

      ;; Left click -> accept perimeter only if geometry is valid.
      ((= code 3)
       (if (msa6:valid-perimeter-p p1u p2u key)
         (progn
           (setq p3u key
                 p4u (msa6:p4 p1u p2u p3u)
                 p3w (trans p3u 1 0)
                 p4w (trans p4u 1 0)
                 newPlacements
                   (msa6:compute-perimeter-placements
                     records p1w p2w p3w p4w))

           (if newPlacements
             (progn
               (setq failed
                 (msa:transition-placements
                   records currentPlacements newPlacements)
                 totalFailed (+ totalFailed failed)
                 currentPlacements newPlacements
                 *msa6-current-placements* currentPlacements
                 accepted T
                 done T)
             )
           )
         )
       )
      )

      ;; Keyboard
      ((= code 2)
       (cond
         ;; ESC -> keep linear.
         ((= key 27)
          (setq keepLine T done T))

         ;; ENTER / SPACE accepts the last valid perimeter preview.
         ((member key '(13 32))
          (if lastValidU
            (progn
              (setq p3u lastValidU
                    p4u (msa6:p4 p1u p2u p3u)
                    p3w (trans p3u 1 0)
                    p4w (trans p4u 1 0)
                    newPlacements
                      (msa6:compute-perimeter-placements
                        records p1w p2w p3w p4w))
              (if newPlacements
                (progn
                  (setq failed
                    (msa:transition-placements
                      records currentPlacements newPlacements)
                    totalFailed (+ totalFailed failed)
                    currentPlacements newPlacements
                    *msa6-current-placements* currentPlacements
                    accepted T
                    done T)
                )
              )
            )
            ;; No valid perimeter ever shown -> keep linear.
            (setq keepLine T done T)
          )
         )
       )
      )

      ;; Right click -> keep linear.
      ((= code 25)
       (setq keepLine T done T))
    )
  )

  (redraw)

  (if keepLine
    (progn
      ;; If the user was looking at a perimeter preview, return to P1-P2 line.
      (setq failed
        (msa:transition-placements
          records currentPlacements linearPlacements)
        totalFailed (+ totalFailed failed)
        currentPlacements linearPlacements
        *msa6-current-placements* currentPlacements)
      (vl-catch-all-apply 'vla-Regen (list doc 1))
      (prompt "\nLinear SmartAlign kept.")
      (list "LINE" currentPlacements totalFailed frames)
    )
    (progn
      (vl-catch-all-apply 'vla-Regen (list doc 1))
      (prompt "\nPerimeter SmartAlign accepted.")
      (list "PERIMETER" currentPlacements totalFailed frames)
    )
  )
)


;; Standalone v0.7: the required v0.5 core is embedded above.
;; Keep the v0.6 run structure unchanged, but these helpers no longer load
;; or redefine anything.
(defun msa6:ensure-base () T)
(defun msa6:install-aliases () T)


(defun msa6:run
       (/ *error* acad doc undoOpen stage
          ss n p1u p1w collected records skipped
          lineResult p2u p2w linearPlacements
          perimeterResult failedLine failedPerimeter framesLine framesPerimeter
          nText nBlock nLanding)

  (setq acad (vlax-get-acad-object)
        doc  (vla-get-ActiveDocument acad)
        undoOpen nil
        stage "INIT"
        records nil
        linearPlacements nil
        *msa6-current-placements* nil)

  (defun *error* (msg)
    ;; Recovery semantics follow the stage:
    ;; LINE stage -> restore original.
    ;; PERIMETER stage -> preserve the already accepted linear baseline.
    (cond
      ((and records (= stage "LINE"))
       (msa:restore-originals records *msa6-current-placements*))

      ((and records (= stage "PERIMETER") linearPlacements)
       (msa:transition-placements
         records *msa6-current-placements* linearPlacements))
    )

    (if records
      (vl-catch-all-apply 'vla-Regen (list doc 1))
    )

    (if undoOpen
      (progn
        (vl-catch-all-apply 'vla-EndUndoMark (list doc))
        (setq undoOpen nil)
      )
    )

    (if (and msg
             (not (wcmatch (strcase msg) "*CANCEL*,*QUIT*,*BREAK*")))
      (prompt (strcat "\nMLeaderSmartAlign v0.7 error: " msg))
    )
    (princ)
  )

  (if (not (msa6:ensure-base))
    (prompt "\nMLeaderSmartAlign v0.7 internal core is unavailable.")
    (progn
      (msa6:install-aliases)
      (prompt
        (strcat
          "\nMLeaderSmartAlign v0.7"
          " - LIVE LINE -> optional LIVE PERIMETER."
        )
      )

      (setq ss (ssget '((0 . "MULTILEADER"))))

      (cond
        ((null ss)
         (prompt "\nNo MULTILEADER objects selected."))

        ((< (setq n (sslength ss)) 2)
         (prompt "\nSelect at least two MULTILEADER objects."))

        (T
         (setq p1u (getpoint "\nSpecify alignment start point P1: "))
         (if p1u
           (progn
             (setq p1w       (trans p1u 1 0)
                   collected (msa:collect-records ss "SHELF_CENTER")
                   records   (car collected)
                   skipped   (cadr collected))

             (if (< (length records) 2)
               (prompt "\nNot enough readable MLeader geometry to align.")

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

                 (vla-StartUndoMark doc)
                 (setq undoOpen T
                       stage "LINE")

                 ;; ---------------- Stage 1: linear live preview ----------------
                 (setq lineResult
                   (msa6:live-line-stage doc records p1u p1w))

                 (if lineResult
                   (progn
                     (setq p2u             (nth 1 lineResult)
                           p2w             (nth 2 lineResult)
                           linearPlacements (nth 3 lineResult)
                           failedLine       (nth 5 lineResult)
                           framesLine       (nth 6 lineResult)
                           *msa6-current-placements* linearPlacements
                           stage "PERIMETER")

                     (prompt
                       (strcat
                         "\nP2 fixed. Linear distribution is now the baseline."
                         "\nPress Esc now (or during perimeter preview) to KEEP this linear result."
                       )
                     )

                     ;; --------------- Stage 2: optional perimeter live ----------
                     (setq perimeterResult
                       (msa6:live-perimeter-stage
                         doc records
                         p1u p2u
                         p1w p2w
                         linearPlacements))

                     (setq *msa6-current-placements* (nth 1 perimeterResult)
                           failedPerimeter (nth 2 perimeterResult)
                           framesPerimeter (nth 3 perimeterResult)
                           stage "DONE")

                     (prompt
                       (strcat
                         "\nDone. Mode: " (car perimeterResult)
                         ". Aligned: " (itoa (length records))
                         (if (> skipped 0)
                           (strcat ", skipped: " (itoa skipped))
                           "")
                         (if (> (+ failedLine failedPerimeter) 0)
                           (strcat
                             ", preview/update failures: "
                             (itoa (+ failedLine failedPerimeter)))
                           "")
                         ". Line preview frames: " (itoa framesLine)
                         ", perimeter preview frames: " (itoa framesPerimeter)
                         "."
                       )
                     )
                   )
                   ;; Stage 1 cancel already restored originals.
                   (setq stage "DONE")
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
    )
  )

  (setq *msa6-current-placements* nil)
  (princ)
)


;; Public commands in v0.7.
(defun c:MSA7 ()
  (msa6:run)
)

(defun c:MLEADERSMARTALIGN ()
  (msa6:run)
)

(prompt
  "\nMLeaderSmartAlign v0.7 standalone loaded. Commands: MSA7, MLEADERSMARTALIGN."
)
(princ)
