extensions [matrix profiler vid numanal]

breed [sheep a-sheep]
breed [shepherds shepherd]
breed [trackers tracker]

globals
[
  prior-model
  fN
  goal-tolerance
  win?
  cohesive?
  at-goal?
  gcm-x
  gcm-y
  sheep-footprint
  psi
  delta
  omega
  radius-pierson
]
patches-own
[
  edge?
  edge-xcor
  edge-ycor
]
sheep-own
[
  sheep-neighbors
  num-nearby-shepherds
  num-nearby-sheep
  last-vx
  last-vy
]
shepherds-own
[
  id
  delta-j
  alpha-j
  dx-j
  dy-j
]

to setup
  let pm prior-model
  clear-all
  set prior-model pm
  set-default-shape sheep "sheep"
  set-default-shape shepherds "dog"
  if sheep-model != prior-model
  [
    reset-default-parameters
    set prior-model sheep-model
  ]
  set fN radius-sheep * (num-sheep) ^ (2 / 3)
  set goal-tolerance 10
  ask patches
  [
    set pcolor green + (random-float 0.8) - 0.4
    if distancexy dest-x dest-y < goal-tolerance
    [
     set pcolor red
    ]
    set edge? (pxcor = max-pxcor or pycor = max-pycor or pxcor = min-pxcor or pycor = min-pycor)
    if edge?
    [
      set edge-ycor pycor
      set edge-xcor pxcor
      (ifelse
        pxcor = max-pxcor [set edge-xcor pxcor + 1]
        pxcor = min-pxcor [set edge-xcor pxcor - 1]
        pycor = max-pycor [set edge-ycor pycor + 1]
        pycor = min-pycor [set edge-ycor pycor - 1])
    ]
  ]
  create-shepherds num-shepherds
  [
    set id who + 1
    set color brown
    set size 10  ;; easier to see
    setxy (random-float-in (min-pxcor) (max-pxcor)) (random-float-in (min-pycor) (max-pycor))
  ]
  create-sheep num-sheep
  [
    set color white
    set size 10  ;; easier to see
    setxy (random-float-in (min-pxcor / 2) (max-pxcor / 2)) (random-float-in (min-pycor / 2) (max-pycor / 2))
  ]
  if shepherd-model = "pierson"
  [
    set shepherd-r 40
    set radius-pierson shepherd-r
    create-trackers 1
    [
      set color blue
      set shape "target"
      set size 15
      setxy 0 0
    ]
  ]
  if num-neighbors > num-sheep
  [
   set num-neighbors num-sheep - 1
  ]
  reset-ticks
end

to-report random-float-in [a b]
  report a + random-float (b - a)
end

to reset-default-parameters
  (ifelse
    sheep-model = "vaughan"  [ default-weights-vaughan ]
    sheep-model = "strombom" [ default-weights-strombom ])
end

to default-weights-vaughan
  set sheep-speed 0.12

  set radius-sheep 0.5

  set weight-com 1.05
  set weight-r-sheep 1.0
  set weight-r-shepherd 1.0
  set weight-inertia 0.5

  set radius-shepherd -1
  set num-neighbors -1

  set weight-epsilon -1
end

to default-weights-strombom
  set sheep-speed 1.0
  set shepherd-speed 1.5
  set probability-move-while-grazing 0.05

  set radius-sheep 2
  set radius-shepherd 75

  set weight-inertia 0.5
  set weight-com 1.05
  set weight-r-shepherd 1.0
  set weight-r-sheep 2.0
  set weight-epsilon 0.05

  ; not used for strombom
  set weight-wall -1
end

to profile
  setup
  profiler:start
  go-for 2000
  profiler:stop
  print profiler:report
  profiler:reset
end

to go
  if sheep-model != prior-model
  [
    reset-default-parameters
    set prior-model sheep-model
  ]
  ask sheep [
    (ifelse
      sheep-model = "vaughan" [ go-sheep-vaughan ]
      sheep-model = "strombom" [ go-sheep-strombom ])
  ]
  let gcm-v gcm
  set gcm-x vx gcm-v
  set gcm-y vy gcm-v
  if shepherd-model = "pierson"
  [

    set radius-pierson radius-pierson + shepherd-k * delta-shepherd-radius
    clear-drawing
    ask trackers [
      setxy gcm-x gcm-y
      facexy dest-x dest-y
      set psi heading-to-angle heading
      pd
      fd shepherd-ell
      pu
    ]
    set delta compute-delta-pierson abs v-pierson radius-pierson
    let by vec2 (- sin psi) (cos psi)
    set omega (- shepherd-k / shepherd-ell) * dot by point-offset
  ]
  ask shepherds [
    (ifelse follow-mouse and mouse-down? [ shepherd-follow-mouse ]
      shepherd-model = "strombom" [ shepherd-strombom ]
      shepherd-model = "pierson" [ shepherd-pierson ])
  ]
  tick
  check-win
  if win? [ stop ]
  if vid:recorder-status = "recording" [ vid:record-view ]
end

to go-for [iters]
  if iters < 0
  [
    loop [ go if win? [stop] ]
    stop
  ]
  repeat iters [ go if win? [stop] ]
end

to start-recorder
  carefully [ vid:start-recorder ] [ user-message error-message ]
end

to reset-recorder
  let message (word
    "If you reset the recorder, the current recording will be lost."
    "Are you sure you want to reset the recorder?")
  if vid:recorder-status = "inactive" or user-yes-or-no? message [
    vid:reset-recorder
  ]
end

to save-recording
  if vid:recorder-status = "inactive" [
    user-message "The recorder is inactive. There is nothing to save."
    stop
  ]
  ; prompt user for movie location
  user-message (word
    "Choose a name for your movie file (the "
    ".mp4 extension will be automatically added).")
  let path user-new-file
  if not is-string? path [ stop ]  ; stop if user canceled
  ; export the movie
  carefully [
    vid:save-recording path
    user-message (word "Exported movie to " path ".")
  ] [
    user-message error-message
  ]
end

;; Sheep Models
; Strombom model for sheep
to go-sheep-strombom

  let nearby-shepherds shepherds with [distance myself < radius-shepherd]
  set num-nearby-shepherds count nearby-shepherds

  let move? true
  if num-nearby-shepherds = 0
  [
    set move? (random-float 1.0 < probability-move-while-grazing)
  ]
  if move?
  [
    let inertia-vec polar-to-cartesian weight-inertia (heading-to-angle heading)
    let dir-x vx inertia-vec
    let dir-y vy inertia-vec
    if any? nearby-shepherds
    [
      ; add center-of-mass vector
      let com-vec com-force-strombom
      set dir-x dir-x + weight-com * (vx com-vec)
      set dir-y dir-y + weight-com * (vy com-vec)
      ; add
      let r-shepherd force-shepherds-strombom nearby-shepherds
      set dir-x dir-x + weight-r-shepherd * (vx r-shepherd)
      set dir-y dir-y + weight-r-shepherd * (vy r-shepherd)
    ]

    let nearby-sheep other sheep in-radius radius-sheep
    set num-nearby-sheep count nearby-sheep
    if any? nearby-sheep
    [
      let r-sheep force-sheep-strombom nearby-sheep
      set dir-x dir-x + weight-r-sheep * (vx r-sheep)
      set dir-y dir-y + weight-r-sheep * (vy r-sheep)

    ]
    ; add random noise
    let noise random-vec2
    set dir-x dir-x + weight-epsilon * (vx noise)
    set dir-y dir-y + weight-epsilon * (vy noise)

    ; update position
    let vhat normalize (vec2 dir-x dir-y)
    let dest pos matrix:+ (sheep-speed matrix:* vhat)
    set dest clamp-to-world dest
    facexy (vx dest) (vy dest)
    fd sheep-speed
  ]
end

to-report com-force-strombom
  set sheep-neighbors min-n-of num-neighbors sheep [distance myself]
  report normalize (lcm matrix:- pos)
end

to-report clamp-to-world [xy]
  let x vx xy
  let y vy xy
  if x > max-pxcor + patch-size / 2 [ set x max-pxcor]
  if x < min-pxcor - patch-size / 2 [ set x min-pxcor]
  if y > max-pycor + patch-size / 2 [ set y max-pycor]
  if y < min-pycor - patch-size / 2 [ set y min-pycor]
  report vec2 x y
end

to-report gcm
  report (1.0 / count sheep) matrix:* sum-vec2 [pos] of sheep
end

to-report lcm
  let com-x (1 / num-neighbors) * sum [xcor] of sheep-neighbors
  let com-y (1 / num-neighbors) * sum [xcor] of sheep-neighbors
  report vec2 com-x com-y
end

to-report force-shepherds-strombom [nearby-shepherds]
  let away-from-shepherds [towards-vec2 myself] of nearby-shepherds
  report normalize (sum-vec2 (map [x -> (1.0 / (norm x) ^ 2) matrix:* x] away-from-shepherds))
end

to-report force-sheep-strombom [nearby-sheep]
  let away-from-others [towards-vec2 myself] of nearby-sheep
  report normalize (sum-vec2 (map [x -> (1.0 / (norm x)) matrix:* x] away-from-others))
end

; Vaughan model for sheep
to go-sheep-vaughan
  let v sheep-velocity-vaughan
  let dest pos matrix:+ v
  set last-vx (matrix:get dest 0 0)
  set last-vy (matrix:get dest 1 0)
  facexy last-vx last-vy
  fd (norm v)
end

to-report sheep-velocity-vaughan
  let inertia (vec2 (weight-inertia * last-vx) (weight-inertia * last-vy))
  let v force-sheep-vaughan matrix:+ force-shepherds-vaughan matrix:+ force-wall-vaughan
  report (min (list sheep-speed (norm v))) * (1 / norm v) matrix:* v
end

to-report force-sheep-vaughan
  let towards-others [pos matrix:- ([pos] of myself)] of other sheep
  report sum-vec2 (map [x -> (1.0 / norm x) * (weight-com / (radius-sheep + norm x) ^ 2 - (weight-r-sheep / (norm x) ^ 2)) matrix:* x] towards-others)
end

to-report force-wall-vaughan
  let nearest-edge min-one-of patches with [edge?] [distance myself]
  let patch-pos [vec2 edge-xcor edge-ycor] of nearest-edge
  let SW pos matrix:- patch-pos
  report (weight-wall / (norm SW) ^ 3) matrix:* SW
end

to-report force-shepherds-vaughan
  let away-from-shepherds [([pos] of myself) matrix:- pos] of shepherds
  report weight-r-shepherd matrix:* sum-vec2 (map [x -> 1.0 / (norm x) ^ 3 matrix:* x] away-from-shepherds)
end


;; Shepherd models
; Mouse following model
to shepherd-follow-mouse
  ifelse count shepherds = 1
    [
    facexy mouse-xcor mouse-ycor
    fd shepherd-speed
  ]
  [
    let center vec2 mouse-xcor mouse-ycor
    let angle who * 360 / (count shepherds)
    let target-pos center matrix:+ (polar-to-cartesian shepherd-r angle)
    if norm (target-pos matrix:- pos) > shepherd-speed
    [
      facexy (matrix:get target-pos 0 0) (matrix:get target-pos 1 0)
    ]
    fd shepherd-speed
  ]
end

; Strombom shepherd model
to shepherd-strombom
  let v shepherd-velocity-strombom
  let noise weight-epsilon matrix:* random-vec2
  ifelse norm v > 0
  [
    set v normalize(noise matrix:+ v)
    let target pos matrix:+ (shepherd-speed matrix:* v)
    set target clamp-to-world target
    facexy (vx target) (vy target)
    fd shepherd-speed
  ] [
    let target pos matrix:+ (shepherd-speed matrix:* normalize(noise))
    set target clamp-to-world target
    facexy (vx target) (vy target)
    fd shepherd-speed
  ]
end

to-report shepherd-velocity-strombom
  if any? sheep with [distance myself < 3 * radius-sheep]
  [
    report vec2 0 0
  ]
  let global-com gcm
  let too-spread sheep with [distancexy (vx global-com) (vy global-com) > fN]
  if any? too-spread
  [
    ; collecting
    let furthest max-one-of too-spread [distancexy (vx global-com) (vy global-com)]
    let target [pos matrix:+ radius-sheep matrix:* normalize (pos matrix:- global-com)] of furthest
    report normalize (target matrix:- pos)
  ]
  ; driving
  let dest vec2 dest-x dest-y
  let target global-com matrix:- radius-sheep * sqrt(count sheep) matrix:* normalize (dest matrix:- global-com)
  report normalize (target matrix:- pos)
end

; Pierson shepherd model
to shepherd-pierson
  set delta-j delta * (2 * id - num-shepherds - 1) / (2 * num-shepherds - 2)
  set alpha-j psi + 180 + delta-j
  set dx-j (gcm-x + radius-pierson * cos(alpha-j))
  set dy-j (gcm-y + radius-pierson * sin(alpha-j))
  let dir (normalize((vec2 dx-j dy-j) matrix:- pos) matrix:+ (weight-epsilon matrix:* random-vec2))
  facexy (xcor + vx dir) (ycor + vy dir)
  fd shepherd-speed
end

to-report v-pierson
  let gcm-v vec2 gcm-x gcm-y
  let bx vec2 (cos psi) (sin psi)
  let v (- shepherd-k * dot bx (point-offset matrix:- vec2 dest-x dest-y))
  let opts list v 0
  let mx max opts
  let opts2 list mx shepherd-speed
  report min opts2
end

to-report point-offset
  report first [pos] of trackers
end

to-report delta-shepherd-radius
  let max-global max-spread-global
  let avg-global average-spread-global
  if radius-pierson > (max-global + avg-global) / 2 and radius-pierson > radius-shepherd / 2
  [
    report 2 * (0.75 * radius-shepherd - radius-pierson) + 0.5 * (max-global + avg-global)
  ]
  report (shepherd-r - radius-pierson) + max-global + avg-global
end

to-report compute-delta-pierson [v r]
  ; v = sin(m\Delta / (2 - 2m)) / (r^2 sin(\Delta / (2 - 2m)))
  ; plug it into a rootfinding algorithm bc math is hard
  ; Note: sin(n * x) = 2 ^ (n-1) * \prod_{k=0}^{n-1} sin (k \pi / n + x)
  ; So, with x = \Delta / (2 - 2m) and n = m:
  ;   v = 2 ^ (n-1) * \prod_{k=0}^{n-1} sin (k \pi / n + x) / (r^2 sin(x))
  ;     = 2 ^ (n-1) / r^2 * \prod_{k=1}^{n-1} sin (k \pi / n + x)

  let fn-v [[D] -> fn-delta D v r]

  report (numanal:Brent-root fn-v 0 360 1.0e-6)
end

to-report fn-delta [D v r]
  let m num-shepherds
  report (2 ^ (m - 1)) * (prod ([[k] -> sin (k * 180 / m + D / (2 - 2 * m))]) 1 m) - v; * r ^ 2
end

to-report prod [f start finish]
  report reduce * (map f (range start finish))
end

;; reports
to check-win
  set cohesive? not any? sheep with [distancexy gcm-x gcm-y > fN]
  set at-goal? norm ((vec2 gcm-x gcm-y) matrix:- (vec2 dest-x dest-y)) < goal-tolerance
  set win? cohesive? and at-goal?
end

to-report average-spread-local
  report mean [norm (lcm matrix:- pos)] of sheep
end

to-report max-spread-global
  report max [distancexy gcm-x gcm-y] of sheep
end

to-report average-spread-global
  report mean [distancexy gcm-x gcm-y] of sheep
end

to-report gcm-distance-from-goal
  report norm ((vec2 gcm-x gcm-y) matrix:- (vec2 dest-x dest-y))
end

to-report average-distance-from-goal
  report mean [distancexy dest-x dest-y] of sheep
end

;; Utility functions
to-report heading-to-angle [ h ]
  report (90 - h) mod 360
end

to-report polar-to-cartesian [r theta]
  report vec2 (r * cos(theta)) (r * sin(theta))
end

to-report vec2 [u v]
  report matrix:from-column-list (list (list u v))
end

to-report vx [v]
  report matrix:get v 0 0
end

to-report vy [v]
  report matrix:get v 1 0
end

to-report towards-vec2 [target]
  report ([pos] of target) matrix:- pos
end

to-report pos
  report vec2 xcor ycor
end

to-report random-vec2
  let sign1 2.0 * (random 2) - 1.0
  let sign2 2.0 * (random 2) - 1.0
  report normalize (vec2 (sign1 * random-float 1) (sign2 * random-float 1))
end

to-report sum-vec2 [list-of-vec]
  report reduce matrix:+ list-of-vec
end

to-report dot [u v]
  report (vx u) * (vx v) + (vy u) * (vy v)
end

to-report norm [u]
  report sqrt(dot u u)
end

to-report normalize [u]
  let normu norm u
  ifelse normu > 0
  [
    report (1.0 / normu) matrix:* u
  ]
  [
    report u
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
619
13
1228
623
-1
-1
1.0
1
10
1
1
1
0
0
0
1
-300
300
-300
300
0
0
1
ticks
60.0

SLIDER
37
429
207
462
num-sheep
num-sheep
1
200
100.0
1
1
NIL
HORIZONTAL

SLIDER
34
161
204
194
num-shepherds
num-shepherds
1
100
12.0
1
1
NIL
HORIZONTAL

BUTTON
35
45
141
87
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
162
44
260
87
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SLIDER
37
466
207
499
sheep-speed
sheep-speed
0
2.0
1.0
0.01
1
NIL
HORIZONTAL

SLIDER
217
467
389
500
radius-shepherd
radius-shepherd
0
100
75.0
0.5
1
NIL
HORIZONTAL

SLIDER
217
431
389
464
radius-sheep
radius-sheep
0
10
2.0
0.5
1
NIL
HORIZONTAL

SLIDER
403
431
575
464
weight-inertia
weight-inertia
0
2
0.5
.01
1
NIL
HORIZONTAL

SLIDER
403
467
575
500
weight-com
weight-com
0
2
1.05
.01
1
NIL
HORIZONTAL

SLIDER
403
503
575
536
weight-r-shepherd
weight-r-shepherd
0
2
1.0
0.01
1
NIL
HORIZONTAL

SLIDER
403
539
575
572
weight-r-sheep
weight-r-sheep
0
3
2.0
.01
1
NIL
HORIZONTAL

SLIDER
36
502
263
535
probability-move-while-grazing
probability-move-while-grazing
0
1
0.05
0.01
1
NIL
HORIZONTAL

TEXTBOX
34
372
242
430
Sheep Parameters
24
0.0
1

TEXTBOX
35
102
270
160
Shepherd Parameters
24
0.0
1

SWITCH
214
160
343
193
follow-mouse
follow-mouse
1
1
-1000

SLIDER
33
203
205
236
shepherd-speed
shepherd-speed
0
2
1.5
0.01
1
NIL
HORIZONTAL

SLIDER
220
544
392
577
num-neighbors
num-neighbors
0
100
53.0
1
1
NIL
HORIZONTAL

CHOOSER
382
164
520
209
sheep-model
sheep-model
"strombom" "vaughan"
0

TEXTBOX
172
291
322
309
NIL
11
0.0
1

BUTTON
285
44
417
87
Reset Parameters
reset-default-parameters
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
403
576
575
609
weight-epsilon
weight-epsilon
0
1
0.05
.01
1
NIL
HORIZONTAL

SLIDER
402
613
574
646
weight-wall
weight-wall
0
2
-1.0
0.01
1
NIL
HORIZONTAL

SLIDER
33
244
205
277
shepherd-r
shepherd-r
0
100
40.0
1
1
NIL
HORIZONTAL

CHOOSER
384
219
522
264
shepherd-model
shepherd-model
"pierson" "strombom"
0

INPUTBOX
219
207
269
267
dest-x
-90.0
1
0
Number

INPUTBOX
279
208
329
268
dest-y
-90.0
1
0
Number

PLOT
33
874
537
1024
Distance from goal
Ticks
Distance
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot gcm-distance-from-goal"

BUTTON
450
47
540
89
NIL
profile
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
676
640
789
673
Start Recorder
start-recorder
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
794
640
912
673
Reset Recorder
reset-recorder
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
804
680
923
725
NIL
vid:recorder-status
17
1
11

BUTTON
676
679
795
712
Save Recording
save-recording
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
33
285
205
318
shepherd-k
shepherd-k
0
1
0.25
0.01
1
NIL
HORIZONTAL

SLIDER
32
325
204
358
shepherd-ell
shepherd-ell
0
20
10.0
0.5
1
NIL
HORIZONTAL

@#$#@#$#@
<!-- 1998 2001 -->
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dog
false
0
Polygon -7500403 true true 300 165 300 195 270 210 183 204 180 240 165 270 165 300 120 300 0 240 45 165 75 90 75 45 105 15 135 45 165 45 180 15 225 15 255 30 225 30 210 60 225 90 225 105
Polygon -16777216 true false 0 240 120 300 165 300 165 285 120 285 10 221
Line -16777216 false 210 60 180 45
Line -16777216 false 90 45 90 90
Line -16777216 false 90 90 105 105
Line -16777216 false 105 105 135 60
Line -16777216 false 90 45 135 60
Line -16777216 false 135 60 135 45
Line -16777216 false 181 203 151 203
Line -16777216 false 150 201 105 171
Circle -16777216 true false 171 88 34
Circle -16777216 false false 261 162 30

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.3.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
