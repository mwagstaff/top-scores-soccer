Build an iOS arcade football game inspired by the gameplay feel of classic early-1990s top-down football games such as Sensible Soccer.

Create an original game that captures fast, simple, skill-based arcade football. Pitch graphics, sounds and code are original. The later authorised Top Scores integration supplies real competition, club and player data.

## Planning status and agreed decisions

**Build 20 — restart support and in-match penalties, installed:** the user requested nearby throw-in and free-kick options, legal 10-yard retreat, and penalties for fouls inside the box. Two eligible outfield teammates make stable short support runs while the taker aims. Free-kick opponents respect 9.15m and the goal-line/defensive-area rules. Direct-free-kick fouls in the offender's own painted penalty area, including its lines, retain the complete impact/fall/card/recovery sequence before a live 11m penalty. Tap and held shot controls, aftertouch, physical outcomes, second-touch restrictions and completion at time expiry apply. All 529 native/gameplay tests and six phone/iPad touch checks pass. The signed combined app is installed; the phone lock prevented automatic launch. See [build 20 controls and verification](Documentation/BUILD20_SET_PIECES.md).

**Build 19 — targeted keeper distribution, installed:** the user accepted build 18’s improved passing feel and requested the same reliable target selection for caught-ball throws and goal kicks. Aim and tap chooses the highlighted teammate; a close open throw is underarm, longer/faster throws are overarm, and a reachable arc clears intervening opponents. Holding forces a longer, higher overarm throw from the hands or a longer, higher foot kick from a goal kick. Keeper quality affects useful range, pace and accuracy, while normal first-touch control, interception and offside rules remain active. The camera frames the highlighted outlet before release. All 490 gameplay/native tests passed, with passing phone and iPad touch checks. Installation is confirmed; automatic launch was blocked by the phone’s lock. This supersedes the previous held keeper punt. Research, implementation and verification are recorded in [build 19](Documentation/BUILD19_KEEPER_DISTRIBUTION.md).

**Build 18 — coordinated passing redesign, installed:** implemented after the user accepted the [research-backed approach](Documentation/PASSING_RESEARCH_AND_PROPOSAL.md). Ordinary taps commit the indicated teammate at button-down, and delivery anticipates the receiver’s requested run with matched direction and pace. Immediate steering remains active; neutral input meets the physical flight. First touches carry into a sustainable dribble, queued passes retain their chosen recipient, and the camera frames receiver and ball with distinct target/control markers. Spatial intent selects a through ball to a reachable runner; untargeted taps otherwise knock ahead, with no narrow tap-duration band. All 469 gameplay/native tests passed, with passing phone and iPad UI checks. Build 18 is confirmed installed; automatic launch was blocked by the phone’s lock. See [build 18 verification and playtest](Documentation/BUILD18_PASSING.md).

**Build 16 — immediate receiver movement:** the receiver follows every non-neutral joystick input immediately, including the passing direction held through release and small processed movements. Neutral input alone enables movement to meet the physical flight path; nearby slow or overshot passes are chased instead of leaving the receiver standing. This also applies to keeper backpasses, preserving keeper foot ability and catch recovery. This supersedes build 15's suppression of the inherited passing direction.

**Build 15 — passing and aerial play:** the user requested more reliable teammate passing, easier high/long held clearances, and joystick-directed tap headers. All short taps retain a viable teammate; selection accounts for open lanes and pressure. Intended receivers meet the flight path until fresh steering overrides, then cushion and physically settle the ball. Goal-assisted held shots apply within 32 metres; other held kicks have bounded loft and range, with full power around 0.9 seconds and no clearance overhit penalty. Reachable headers use a half-second early-input buffer, actual swept contact, a hop/light impact, and normal offside decisions. High balls bypass feet and outfield players beyond heading reach. See [the gameplay verification and playtest guide](Documentation/BUILD15_GAMEPLAY.md). These decisions supersede earlier whole-pitch shot assistance and deferred headers.

**World Cup mode — implemented:** a separate saved World Cup mode now sits alongside Friendly and Career. The player chooses one of 48 national teams and plays three group matches in one of 12 four-team groups. The top two in each group and eight best third-placed teams advance to the Round of 32, followed by the Round of 16, quarter-finals, semi-finals, third-place match and final. Regulation remains three minutes of active play; a level knockout result continues through extra time and then a playable alternating penalty shoot-out with early clinches and sudden death. Tournament creation, lineup edits and every completed simulation/match checkpoint save atomically in a World Cup file that cannot replace the Career save. A saved user victory in the final triggers an accessible animated gold-trophy celebration with gleam, gold ticker tape, original cheers/sting and haptics. DEBUG builds expose a direct celebration preview, deterministic final-flow route, and in-match shortcuts for win/draw/defeat, extra time and penalties. The shortcuts use the real save and bracket callbacks, allowing an end-to-end tournament test; Release builds contain none of them. The implementation contract and acceptance checks are in [Documentation/WORLD_CUP_MODE_PLAN.md](Documentation/WORLD_CUP_MODE_PLAN.md).

**Build 14 — movement, restarts and offside, installed and launched:** retains build 13's 11v11 friendlies, saved careers and squads. The user requested a two-player centre-circle kickoff with lateral/backward alternatives, keeper catches that prompt both teams to regroup with one short outlet, and short support plus well-timed forward runs. The user explicitly chose offside free-kick decisions as well as offside-aware AI. Snapshot offside position at teammate touches, adjudicate physical reception/challenge involvement, preserve the snapshot after posts/parries, and exempt direct throw-ins/corners/goal kicks. Award an indirect restart with a whistle/announcement and no disciplinary card. Use bounded deterministic role/space scoring for attacking support; respect the second-last opponent and ball before release, then let a legal receiver run beyond. No teleports on keeper catches. All 359 core tests and nine phone UI checks passed on the final production code; the signed build was installed and launched on 7 September 2026. The verification/delivery record is in Documentation/PLAYTEST.md; these rules supersede earlier offside deferrals.

**Previous milestone — build 13, Premier League career, installed:** after accepting build 12 as a good start, the user authorised the next milestone. Add a saved career with one chosen club, a generated 38-match home/away season, nine simulated results alongside each played fixture, a league table, season history and the next season. A career freezes all squads, ratings and appearance choices at creation. New seasons retain those same clubs and players; management, transfers and promotion/relegation remain later work. The user keeps attacking north in away fixtures, while kits, scoreboards and saved results respect the actual venue. Results save automatically at full time; unfinished matches restart from kickoff when revisited. Save failures retain the result for retry. This current scope supersedes historical 5v5 defaults and 11v11/career deferrals below. All 323 core tests and fifteen distinct phone/iPad UI checks have passing results. Build 13 is installed on the connected iPhone; automatic launch was denied because it was locked. Verification and delivery are recorded in Documentation/PLAYTEST.md.

**Build 12 — Premier League friendly checkpoint accepted:** 20 clubs and 631 players, 11v11, three formations and editable XIs, source shirt numbers, simple club/clash kits, bounded abilities from one overall rating, and stable generated skin/hair palettes. All 305 core tests and eleven phone/iPad UI checks passed, and build 12 was installed and launched on the connected iPhone. Appearances are cosmetic variety, not portrait-matched likenesses. Friendlies and both training exercises remain available in build 13.

The user authorised implementation on 6 September 2026, accepted Milestone 1, and then requested portrait-only play plus the next passing/defending milestone. Roadmap step 1 was a **3v3 Pass & defend exercise**, with **Solo practice** in settings. Build 2 passed a signed iOS build, 38 simulation/camera tests, and phone/iPad UI checks. Build 3 added the requested off-ball speed advantage, standing/slide/passive tackles, foul and card consequences, chips, nearest-player selection, queued first-time actions and boundary saves; it passed a signed build, 79 unit tests, seven UI tests on each platform, four final gameplay rechecks and a 100,000-step simulation run.

Build 4 added visible sliding contact and a victim fall before the whistle/free kick, deliberate player switching with less automatic switching, and stickier close control. Its signed iOS build, 95 unit tests and seven UI tests on each platform passed, including Dark Mode and the largest accessibility text size on iPad. Rendered iOS snapshots validated its fall presentation.

Build 5 added a longer impact/fall/grounded/recovery sequence, more forgiving pickup and rough-direction passing, captured first-time pass/shot preparation, short untargeted knock-aheads and goal-assisted shots with powerful long kicks elsewhere. Its development-signed iOS build and strict signature verification passed, along with all 118 unit tests and all seven UI tests on each of iPhone and iPad. The iPad checks used Dark Mode and the largest accessibility text size; gameplay/settings screenshots and iOS fall/recovery render grids were inspected.

**Build 6 validation is recorded:** all 131 unit and scene tests and seven phone UI tests passed, and a normal Xcode device build succeeded with a verified development signature. That revision gave the joystick control of an assisted pass's intended receiver while the ball was travelling, and allowed blue's free-kick taker to face the stick direction without moving the set piece. Neutral input retains the last chosen facing. Physical installation, feel and sustained device performance were not verified for that revision.

**Build 7 validation and installation are recorded:** all 146 unit and scene tests and seven phone UI tests passed, together with a development-signed device build; strict signature verification passed and the app declares build number 7. Running toward the ball becomes the primary tackle, with forgiving front/side contact and a brief sustained-pressure requirement from behind. Short off-ball ACTION taps select players or prepare first-time kicks, without a standing tackle; held slides remain. The phone UI suite includes the revised short-tap selection versus held-slide interaction. The iPad UI suite was not rerun for this revision; the earlier Build 5 Dark Mode and largest-text results remain its recorded baseline. Build 7 was successfully installed and launched on the connected iPhone 16 Pro Max running iOS 26.6.1; the installed-app query confirms build number 7. This is the actual connected device, distinct from the originally nominated iPhone 17 Pro Max. Physical feel and sustained performance await user playtesting.

**Build 8 validation and installation are recorded:** all 165 unit and scene tests and seven phone UI tests passed, together with its signed device build; strict signature verification passed and the app declares build number 8. Use joystick intent to switch rapidly and automatically to a nearby blue player whose run can reach the ball or block a moving carrier. The best choice need not be the closest player. ACTION is an optional fallback using the same intent, rather than a required switching step. Preserve committed kicks, receivers, slides and close rear pressure, with distance bounds and brief stability checks to avoid rapid oscillation. Build 8 is installed on the connected iPhone 16 Pro Max running iOS 26.6.1, with its installed build number verified. Automatic launch was blocked by the locked phone; the user can unlock it and open Top Scores Soccer. The phone UI screenshot was inspected for readable selection and steering guidance in portrait. The iPad UI suite was not rerun for this revision; Build 5’s Dark Mode and largest-text run remains the earlier baseline. Physical feel and sustained performance await user playtesting. At that revision, the later 5v5 match still awaited the user’s gameplay review. See README.md and Documentation/PLAYTEST.md for build instructions and each build's evidence.

**Build 9 validation and installation are recorded:** all 201 game, scene, input and haptic tests passed, together with its signed device build. The floating joystick starts anywhere on the left half of the play surface, recentring with each new thumb touch. Add optional haptics on actual kicks and challenge contacts. Forgive rough pass aim and small release movements, allow a 0.26-second tap before charging, and give nearby teammates and the passer useful return lanes. Preserve directional intent, interception, queued first-time actions, running tackles and automatic selection. Strict signature verification passed and the app declares build number 9. Installation, launch and an installed-version check succeeded on the connected iPhone 16 Pro Max running iOS 26.6.1. All eight standard phone UI cases have passing results across the initial seven passing cases and a corrected settings-test rerun, with no app change for that rerun. Gameplay screenshots were inspected. Both focused iPhone settings checks at the largest accessibility text size in Dark Mode passed after correcting the test’s assumption that the first slider was already onscreen. No app change was needed for that rerun; the native haptics toggle and settings layout were visually inspected. At that handoff, physical feel, haptic strength and sustained performance awaited user playtesting; the subsequent core-feel acceptance is recorded below.

**Build 9’s core feel gate was accepted on 7 September 2026.** The user authorised the next milestone and chose **three minutes of active play**. This acceptance covers the gameplay foundation; it is not a recorded sustained-performance measurement.

**Build 10 — 5v5 match, installed and launched:** make Match the default, with four outfield players and one autonomous goalkeeper per side. Keep simple 2–2 outfield formations, blue attacking north throughout one period, an active-play clock, team score, goals and conceding-team kickoffs, simple throw-ins/corners/goal kicks, retained fouls/cards/free kicks, and a full-time result with Play again. Goalkeepers position, dive, hold or parry and distribute; original amber/violet keeper kits, gloves and GK badges make their role visible. Pass & defend and Solo practice remain available in settings. The full 243-test Xcode game/scene/renderer suite passed, followed by six passing match-scene tests including one new keeper-wait check: 244 distinct automated checks have passing results across runs. All ten phone UI cases have passing results across the initial eight retained cases and two corrected match checks; both iPad match checks passed. The final signed app passed strict signature verification and declares build number 10. Installation and launch succeeded on the actual iPhone 16 Pro Max, iOS 26.6.1, at 00:29:36–37 on 7 September 2026; the installed-app record verifies version 0.1.0, build 10. All three additional phone checks at the largest accessibility text size in Dark Mode passed at 00:31:51 on 7 September 2026, with TEST SUCCEEDED and exit code 0. Match balance and sustained performance await physical playtesting. The playtest guide separates passing test portions from mixed-result bundles.

**Build 11 — keeper possession and attacking refinements, installed and launched:** the user reviewed 5v5 as good overall and requested manual keeper distribution, realistic backpass restrictions, hold-dependent throw-in range, through balls, shot sweet spots/overhit height and backheels. This supersedes the earlier rule that keepers can never be controlled. Keepers remain automatic off the ball; blue takes control of a catch, a backpass receiver or a keeper at feet. A caught opposition ball is protected from tackles and body pushing. A teammate's deliberate ball must stay at the keeper's feet until an opposition touch restores handling eligibility. Keep three-minute matches and the accepted passing/selection/tackle foundation. All 282 game/scene/input tests passed; all 13 phone UI cases have passing results across the main run and a focused rerun, five iPad checks passed, and three phone checks passed in Dark Mode at the largest accessibility text size. The signed build and installed version 11 were verified on the connected iPhone 16 Pro Max, with launch at 01:13:49 on 7 September 2026. The playtest guide records the initial missed kickoff tap and unchanged passing rerun. Physical balance and sustained performance remain playtest observations.

The user confirmed these decisions on 6 September 2026:

- Pursue faithful Sensible Soccer gameplay feel, adapted for touch.
- Use **portrait only** on iPhone and iPad; the later portrait request supersedes the original landscape layout.
- Use an **iPhone 17 Pro Max** for the first physical playtests.
- Keep one ACTION button; a quick tap passes **on release**.
- Briefly prioritise ball curve over player movement during aftertouch.
- Make running toward the ball the main tackle: forgive close front/side approaches and require brief sustained close pressure from behind. Interpret a firm defensive ACTION press as a brief hold, without requiring screen pressure, to start a slide. Short releases select a player or prepare a loose-ball kick; the later running-tackle request supersedes the earlier button standing tackle. A receiving context has its own pass/shot preparation and must never turn into a slide during that press.
- Switch automatically and promptly off the ball according to joystick intent. Prefer a nearby player whose run in that direction can reach the ball or block the moving carrier, rather than always selecting the closest player. A short off-ball ACTION release is optional and uses the same selection logic; consume it if selection changes, otherwise retain a valid queued first-time rescue opportunity. This later request supersedes slow nearest-player switching and tap-led selection.
- Show tackle contact and the victim falling before announcing the foul, playing a whistle or applying discipline. Make loose-ball pickup and normal close control more forgiving.
- Capture outgoing direction and power when releasing a prepared first-time kick, independent of the incoming ball's direction. Broaden directional passing, make untargeted taps chaseable, and assist roughly aimed shots toward goal while retaining powerful long kicks in other directions. These later requests supersede the original fully manual shot aim and fixed-speed untargeted pass.
- Include simple foul/free-kick/card consequences and pull-back chips in the current exercise, superseding their earlier deferral.
- Exclude physical controller support from the first sandbox.
- Plan for single-player first. Multiplayer is undecided, so networking, synchronisation and multiplayer infrastructure are outside the current scope.

The historical build 11 default was **5v5 match**, with four outfield players and a goalkeeper on each side; positioning and saves are automatic, possession and distribution by blue are controlled by the user. Blue attacks north for a single three-minute active-play period. **Pass & defend** retains the three-a-side empty-goal exercise and **Solo practice** remains available for isolated mechanics tests.

The detailed behaviours and tuning values below remain subject to playtesting. Section 17 records the historical Milestone 1 scope and acceptance criteria; its exclusions are not restrictions on the later authorised mechanics. The current delivered gameplay work is build 20 as defined above. The Build 11 discussion below is retained as historical gameplay detail.

## Technical approach

Create a native iOS game using:

- Swift
- SpriteKit
- SwiftUI only where useful for menus/settings
- Portrait orientation only
- iPhone and iPad support
- 60 fps target

Keep iPad layout support in the design, but use the nominated iPhone as the first gameplay acceptance device. Check iPad layouts in the simulator until a physical iPad is available. The project supports iOS/iPadOS 18 or later and builds with Xcode 26.6.

Avoid external game engines and third-party dependencies unless absolutely necessary.

Initially concentrate entirely on making the **core football mechanics feel good**. Placeholder sprites/shapes are fine.

---

# 1. Camera and presentation

Use the classic elevated top-down football viewpoint:

- Portrait-oriented pitch displayed within a portrait phone screen
- Use 2D rendering with slight visual foreshortening and upright player sprites to suggest an elevated viewpoint; no 3D camera is needed
- Both goals positioned at the short ends of the pitch
- Camera follows the ball/action vertically up and down the pitch
- Camera movement should be smooth but responsive
- Player sprites remain relatively small so the player can see plenty of the pitch
- Camera should look slightly ahead of the direction of play where appropriate

Do not use a FIFA-style close camera.

The visual priority is readability and awareness of space around the controlled player.

Keep the complete pitch width readable where the screen aspect ratio permits. Target approximately one third to one half of the pitch length in view. Use a stable scale initially rather than dynamic zoom, clamp scrolling at the ends, and prioritise keeping a fast-moving ball visible. During a long shot the shooter may leave the screen temporarily. Keep directional aiming consistent with the direction perceived on screen; visual foreshortening must not distort input.

---

# 2. Core controls

Design the game around extremely simple controls.

Left side:

Virtual analogue joystick for 360-degree player movement.

Each new touchdown anywhere on the left half of the play surface places the joystick centre exactly beneath that thumb. The first contact is neutral; dragging then sets direction and speed relative to that origin. Keep the origin until lift, even if the captured thumb crosses the centre line, and start a fresh centre on the next touch. Show the full ring only while active, with a subtle idle touch-and-drag cue. Reserve separate touch ownership for movement and ACTION, giving ACTION priority within its enlarged hit target. Native toolbar controls keep their own touches. Lifting movement must leave an independently held ACTION press intact; cancellation, pause and geometry changes clear old input without kicking. Keep the accessibility movement target meaningful while idle and centred on the active ring during a drag. A mirrored layout option for left-handed use can follow the first sandbox review.

Right side:

One large ACTION button.

Initially use contextual actions rather than lots of separate buttons.

When the player has the ball:

- Tap ACTION and release before the hold threshold = pass on release
- Hold ACTION beyond the threshold = charge a shot
- Shot power increases while held, up to a sensible maximum
- Release ACTION = strike the ball

When the player does not have the ball:

- An incoming friendly/free ball can offer a receiving action. Press ACTION to select an eligible receiver, choose the outgoing direction and release: a tap prepares a first-time pass or knock-ahead; a hold prepares a charged shot or long kick. Bind receiver, release aim and power until actual contact. Do not convert a receiving hold into a slide.
- Point the joystick toward the desired run. Automatically select a nearby eligible blue player who can meet the ball or block the carrier along that direction; no ACTION tap is required. Outside a receiving context, an optional short tap uses the same choice and must not undo an active directional selection by falling back to the closest player. Consume a tap that changes selection; otherwise apply the context below.
- Run toward the opponent's ball to tackle without ACTION. Front and side contact should be forgiving; remaining close behind the same carrier and pressing toward them for about 0.5 seconds can win the ball. A short ACTION tap does not attempt a standing tackle.
- A short tap while approaching a nearby loose ball arms a first-time kick for up to 1 second. Bind this opportunity to the selected player and chosen direction, require actual reachable ball contact, and never rescue a ball after it has crossed out of play.
- Holding for 0.22 seconds commits a slide in the player's current running direction, using facing when stationary. It starts when the hold threshold is reached rather than waiting for release. It can challenge an opponent or reach a loose boundary ball.
- A firm press is a duration gesture on the same ACTION button, not pressure-sensitive input.
- Keep shot aftertouch and the brief chip gesture window protected from a surprise tackle. A press begun in a protected window must not later become an unexpected action.
- The new loose-ball queue and slide controls also work in Solo practice for focused rescue tests.

Give immediate visual feedback when ACTION is pressed. Because tap and hold share one button, the kick happens on release, not on initial contact. Build 9 uses a 0.26-second hold threshold so a relaxed short tap still passes; playtest this value. Charge grows from minimum to maximum after that threshold and caps after a further 0.65 seconds, or 0.91 seconds total. Continuing to hold at full power does not auto-fire. Build 11 adds excess shot height when holding too long: the meter includes a green release band and a red overhit warning. Throws and keeper distribution use distance meters without this shooting penalty.

Resolve the action type from the context at button-down. A ball action stays a ball action throughout that press; it must never unexpectedly become a tackle if possession changes. While charging in possession, keep normal movement and loose dribbling active. Losing the soft control claim cancels that charge for the entire press, even if control is regained before release; releasing while the ball is beyond kicking reach also cancels it. Ordinary gaps between dribble touches should retain the claim, using the possession rules in section 8. Tune kicking reach to cover ordinary controlled dribble touches so release does not fail merely because it falls between nudges. A deliberately prepared receiving action is distinct: it begins before acquisition, captures release direction/power, belongs to one player and executes once on real contact. Incoming trajectory determines eligibility independently of outgoing aim. Clear queues on pause, cancellation, reset, out-of-play or an invalidating possession change. Stick movement already held before queued contact must not immediately become a chip or curve gesture at execution; require a fresh change for that aftertouch.

Use deliberate joystick direction at release for kicking. Retain the last deliberate aim through small centre-stick movements or thumb lift during a press; outside a press, retain it briefly for the same actor before falling back to facing. A fresh deliberate aim overrides that memory. Clear it on cancellation and never transfer it to another player. A touch that is cancelled by the system, an app interruption or a restart clears its input and charge without firing. Keep an ACTION press captured until lift even if the thumb slides outside the artwork.

The controls must feel responsive and arcade-like within this agreed release-based scheme.

Avoid animation systems which introduce noticeable input lag.

---

# 3. Player movement

Players should have:

- acceleration
- maximum running speed
- deceleration
- turning
- momentum

However, keep movement arcade-like rather than physically realistic.

Changing direction should feel responsive.

A player running at full speed should not instantly rotate 180°, but they also shouldn't feel like a vehicle.

Tune these values centrally so they can easily be adjusted later.

Implement a GameplayTuning structure/config containing values such as:

playerAcceleration
playerMaxSpeed
playerDeceleration
playerTurnRate
ballFriction
passSpeed
shotMinSpeed
shotMaxSpeed
aftertouchStrength
etc.

Do not add a sprint mechanic in the first sandbox. Joystick magnitude controls requested movement speed; maximum deflection means normal full running speed.

The current refinement gives players 12% more speed off the ball. Keep the accepted 10.5 m/s full-stick dribbling speed; the corresponding off-ball maximum is 11.76 m/s before AI scaling. Apply the distinction to both teams, without adding another button.

Build 5 makes ordinary close control more forgiving through 0.075-second dribble touches, 2.5 m dribble reach, 2.4 m loose-ball acquisition and a 3.5 m soft-control release distance. Friendly passes receive a separate cushioning speed allowance. Keep ball movement independent and preserve hard-shot/airborne exclusions, kicking guards and strict physical reach when trying to take an opponent's protected ball. Do not use end-of-step player positions to acquire a ball before its swept collision or out-of-play event.

Also centralise joystick dead zone, tap/hold threshold, time to full charge, dribble touch interval, dribble reach, control acquisition/release distances, relative-speed limits, kick reach, kick reacquisition delay, aftertouch duration/decay/angle limit, and camera smoothing/look-ahead. Give each value units, a description and a default so changes can be compared and reverted.

---

# 4. Ball behaviour

The ball must be an independent physics/gameplay object rather than simply attached to a player's feet.

When a player has possession, implement loose arcade-style close control.

The ball should remain slightly ahead of the player as they run.

The player periodically nudges/dribbles the ball rather than having it glued to their sprite.

This is important to the feel of the game.

Possession should therefore be slightly imperfect:

- running quickly pushes the ball further ahead
- sharp turns temporarily expose the ball
- an opponent can intercept it
- loose balls occur naturally

Ball behaviour should include:

- velocity
- friction/deceleration
- collision with posts and detection of crossing pitch boundaries
- player interaction
- passes
- shots
- rebounds

Keep ground-plane movement in 2D and add lightweight height and vertical velocity for the authorised chip mechanic. Default upward chip speed is 8 m/s with arcade gravity of 18 m/s². Render the airborne ball separately from its ground shadow; skip foot contacts while it is above the reachable height. On landing, return to ordinary rolling/contact behaviour.

Touchlines and goal lines are not rebound walls. Posts rebound the ball; leaving the playable area causes a restart as described in section 13. Keep ground-plane movement separate from rendering, and check chip height at goal crossings so a ball above the crossbar cannot score. Build 10 adds goalkeeper catches and parries; headers remain deferred.

---

# 5. Passing

Passing should be simple and heavily skill based.

In retained Solo practice there are no teammates: a tap knocks the ball a short distance into space to chase. Use 9 m/s from standing, or the player's forward speed plus 3 m/s if greater. Pass & defend uses the same knock-ahead when no teammate qualifies; assisted teammate passes have separate distance-adjusted pace.

In Pass & defend, when ACTION is tapped and released:

Select a likely teammate using:

1. player's current directional input
2. direction the controlled player is facing
3. distance to candidate teammates
4. whether teammates are roughly inside a directional passing cone

Do NOT simply pass automatically to the nearest teammate.

The player's directional input should matter considerably.

Use a 75-degree half-angle cone and a 42 m range, balancing alignment with a preference for nearby quick options. Exclude players committed to tackles, fallen or recovering. Preserve an untargeted knock-ahead when nobody qualifies. Supporting teammates and the passer offer short return lanes during a friendly pass, encouraging quick movement and one-twos. Lead moving teammates slightly rather than always passing directly to their current coordinates. Start assisted passes at least at 21 m/s and adjust speed for distance and rolling resistance toward a 12 m/s arrival speed, so a chosen distant receiver is reachable. Friendly passes allow cushioning up to 34 m/s relative speed; hard shots retain their stricter acquisition rules.

Allow passes into open space when there is no obvious teammate directly in the chosen direction. A tiny untargeted tap remains a chaseable knock-ahead. If no direct teammate fits but a reachable onside runner can meet the requested open lane, an ordinary tap sends a through ball into that space and selects him. Otherwise the tap stays a chaseable knock-ahead. Tap duration does not choose between these outcomes. Keep ordinary rough-direction taps forgiving and all passes interceptable.

A backheel requires a deft forward-to-reverse joystick swipe during a short passing press, relative to the player's original facing, close to release. Keep the body facing forward while sending a shorter, less powerful ground pass behind. An ordinary backward aim is a normal pass. A pull-back after release remains a chip; one reversal must never produce both actions. Cancel the gesture on pause, player change, reset or invalidated possession.

Passes should remain interceptable.

When a friendly/free ball is approaching a receiver, permit a tap or hold to prepare the next pass or shot. Capture release direction and charge for up to 1 second if the ball is within 14 m and is expected to reach the player. Outgoing aim may be unrelated to arrival direction. This is an arming distance, not kicking reach: use a swept physical contact within the 1.3 m reach before executing. A boundary chase retains the separate tap rescue or held slide, and a successful rescue stays directed into play. The line-crossing event must win if it occurs before the player can reach the ball.

---

# 6. Shooting

Holding ACTION charges a shot.

Provide a visible power meter above ACTION, retaining the small player indicator. Use a green useful-release band, a moving power marker and red overhit feedback; explain the state in text as well as colour.

Shot direction should primarily come from the player's directional input at the moment the shot is released.

Shot strength is determined by how long ACTION was held.

Map the time beyond the hold threshold to the minimum/maximum shot speeds. Release at the threshold produces the minimum shot; additional holding increases power up to the cap. Releasing a shot must immediately end dribble attraction so the ball can escape cleanly.

The latest request adds assistance across the practice pitch when the requested aim is within 50 degrees of the opposition goal's direction. Its source range of 140 m covers the whole pitch. In that case, preserve the requested goal-mouth intercept, bringing rough outside aim just inside the posts rather than always aiming at the centre. Outside that directional opportunity, preserve the requested direction and charged power as a long kick, including clearances up or downfield. Shots and long kicks both retain lateral aftertouch and pull-back chips. This supersedes Milestone 1's fully manual shot direction.

---

Close to goal, holding adds pace and lift. Default useful shot releases are approximately 0.60–0.90 seconds; holding past about 1.05 seconds begins overhit loft, with a 1.30-second hold clearly above the bar at ordinary close-range distances. The ball remains physical: height, reach, keeper motion, posts and the whole-ball crossing determine the outcome. Corners should reward placement; do not award goals directly. Longer shots use bounded ordinary loft. Keep lateral aftertouch available for shots and keeper punts.

# 7. Aftertouch / ball curve

This is a critical feature.

After the player releases a shot, allow approximately 0.5–1.0 seconds during which joystick input can influence the trajectory of the ball.

Start with a proposed **0.65-second window**. During this window the joystick controls curve, while the shooter coasts from their release velocity and slows using normal deceleration. It does not steer the shooter simultaneously. When the window expires or ends because of ball contact, restore movement from the current joystick position; normal acceleration and turning rules apply, with no teleport or instant velocity change. Reset, pause and interruption instead clear active input and require fresh touches when play resumes.

This should create classic arcade-style aftertouch.

Example:

Player shoots upwards toward goal.

Immediately holding left after shooting causes the ball to progressively bend left.

Immediately holding right causes it to bend right.

Milestone 1 used lateral curve only. The current refinement adds a demanding chip gesture: pull the joystick opposite the original kick direction within 0.24 seconds of a pass or shot. Trigger lift once per kick, without granting extra horizontal power. Sideways shot curve retains its existing 0.65-second window; passes gain the short chip opportunity, not sideways curve. Forward acceleration and braking remain deferred.

Implement curve gradually rather than instantly changing ball direction.

Interpret lateral joystick input relative to the original shot direction, including diagonal and downward shots. Keeping the joystick along the original aim direction should add no curve. Apply curvature gradually to the moving ball and preserve its speed apart from normal friction; curving alone must not create extra power.

Aftertouch strength should decay smoothly over time.

Begin with the same curve response for all shot powers and a proposed maximum heading deviation of 25 degrees from the original shot direction. These are tuning defaults, not claims about the original game. Aftertouch must never allow absurd 90-degree turns.

End aftertouch when its timer expires, the ball becomes effectively stationary, it contacts a post or another player, or a goal/out-of-play restart occurs. Never carry aftertouch through a rebound or into another player's possession. Clear it when the game is interrupted or paused.

Expose all relevant values in GameplayTuning.

Make curved long-range shots satisfying.

---

# 8. Possession

Do not explicitly lock possession unless necessary.

Determine the controlling player using ball proximity and ball state.

When the ball is sufficiently close and slow enough relative to a player, that player can establish control.

Running toward an opponent's ball without ACTION is the primary tackle. Allow forgiving close front and side challenges while requiring deliberate movement toward the ball. A challenge from behind must build about 0.5 seconds of uninterrupted close pressure against the same carrier, with both carrier and ball nearby. Losing the chase, moving away or a change of carrier clears this progress. Show KEEP PRESSING while rear pressure builds. Ordinary loose-ball pickup remains forgiving, but must not bypass these opposition-possession rules. Slides offer committed movement and more opportunity to reach the ball at the cost of recovery and foul risk.

Implement clear states such as:

free
controlled
pass
shot

but avoid overly rigid possession scripting.

Separate the player's soft control claim from whether the ball is within reach for an actual kick. Use a slightly wider release distance than acquisition distance and a relative-speed check so the claim survives normal dribble nudges without flickering. Sharp turns and excessive separation should still break control naturally. Give a recently struck ball a short, configurable reacquisition guard for the kicker so it is not instantly pulled back; this must not prevent later opponents from intercepting it.

For contested balls in Pass & defend, use stable tie-breaking and control hysteresis without making the ball immune to interception. Keep controlled-player selection separate from ball possession: the selected human player can remain selected while the ball is free.

---

# 9. Player switching

Make off-ball selection automatic and responsive to the joystick. For each nearby eligible blue outfield player, consider where running in the stick direction can meet the moving ball or block the carrier's projected path. Score joystick alignment, travel distance and current momentum, with a small preference for keeping the current player. A slightly farther player with a useful approach should beat the closest player who would run away. Consider the ball, its predicted position and the carrier's path over a horizon capped at 0.4 seconds. Exclude candidates more than 8 m farther from the threat than the best nearby option. With a neutral stick, keep selection stable unless the current player is remote.

Outside an incoming-ball receiving opportunity, an optional short off-ball ACTION tap applies the same selection logic immediately and consumes the press when it changes players. If the preferred player is already selected, a valid nearby loose ball can offer the queued-rescue action; no standing tackle follows the tap. A receiving press selects the eligible incoming receiver so its prepared kick stays with that player. A press that began with possession must not turn into a manual switch if the ball is lost before release.

An assisted human pass immediately selects its intended blue receiver, allowing joystick movement before contact without a second ACTION press. Protect this deliberate receiving selection from an automatic return to the nearby passer while the pass is incoming. Keep manual overrides, invalidated receivers and interceptions able to end that priority. An untargeted knock-ahead retains its kicker. Preserve the existing chip opportunity and actor-bound prepared-kick behavior when changing selection.

A clear improvement following joystick intent can switch on the next simulation tick without waiting for the cooldown. Ambiguous changes use a 0.06-second confirmation and a 0.10-second cooldown to prevent chatter. These replace the earlier slow nearest-player selection. Keep the selection rules automatic; remove the old Automatic switch delay slider without adding a new selection setting. Exclude sent-off players and off-ball goalkeepers from ordinary directional selection. Blue keeper possession or an intended backpass provides an explicit keeper-control exception; return to ordinary outfield selection after distribution and its aftertouch.

Automatic selection protects visible commitments such as an active kick, chip/curve gesture, slide, actor-bound first-time pass and sustained close rear pressure. Keep the intended pass receiver selected while the pass remains incoming. Rear-pressure protection applies while the player continues the close pursuit; turning away releases it. A deliberate short off-ball tap may use the same directional choice to leave an overridable gesture or recovery window; consume the gesture and end the previous input window. Active tackles and free-kick placement retain their protection. Losing possession, invalidating a receiver or completing the action must release protection appropriately. Candidate timing must be counted once per fixed simulation step, even when selection is checked more than once during that step.

Clearly indicate the currently controlled player using a small marker underneath them.

---

# 10. Tackling

Give the human player two ways to tackle:

- **Running tackle:** move toward the ball without ACTION. Front/side contact uses a forgiving 1.9 m default reach and requires deliberate approach movement or input. From behind, keep close pressure on the same carrier for about 0.5 seconds before winning possession; interruption clears the progress. Broad proximity or waiting beside a carrier must not steal the ball automatically. Slow loose-ball pickup, intended-receiver selection and the boundary crossing order must remain consistent.
- **Slide tackle:** hold ACTION off the ball for 0.22 seconds. Commit to the running direction for 0.30 seconds, with a one-second recovery. Sliding makes it easier to reach the ball but a miss leaves the player exposed. When chasing a boundary ball, a real contact before the crossing can clear it into play or along the pitch.

Computer-controlled players may retain their short standing poke for challenge variety; it is not a human ACTION gesture. Use swept ball/body contact ordering to judge committed standing and slide tackles. Reaching the ball first is clean. Reaching the opponent first is a mistimed foul; a whiff with no opponent contact is not a foul. First enter a 1.2-second contact phase: show the sliding follow-through, impact and victim falling, retaining the actual collision direction. During this phase, block new play actions and keep pending discipline separate from the published foul. At its end, announce the foul, play the whistle if enabled, and apply any card. Then allow 2.4 seconds for foul/card feedback, a visible grounded pause and a get-up animation before placing the opposition free kick at the incident, with nearby opponents moved back. A dismissed offender leaves play instead of recovering into the restart.

Pausing or cancelling touches must not skip the fall, award a card early or replay a whistle. Resume the remaining sequence from its saved state. A manual practice reset clears the pending incident and must not announce it later. Sound is supplementary; visible contact, fall and foul/card feedback explain the event without audio. Use an original short whistle, respect Silent Mode, and provide a **Referee whistle** setting.

Add simple arcade discipline with deterministic randomness, separate from contact legality. Computer-controlled standing fouls have a lower yellow-card chance than slide fouls. Contact from behind or at high relative speed increases the chance. Only a fast, mistimed slide from behind can produce a rare direct red; the default chance for that category is 4%. Two yellows also cause dismissal. Dismissed players leave active play and cannot be selected or receive passes. Automatic goal/out restarts retain discipline; a manual practice reset clears it. If a team has no eligible outfield player remaining, stop the drill and require reset instead of silently bringing dismissed players back. Blue takes awarded free kicks through the usual ACTION input; red restarts automatically. These are gameplay tuning rules rather than a full implementation of football laws.

While a blue free kick awaits ACTION, rotate the taker's facing to the joystick direction while keeping every player and the ball stationary. Neutral input keeps that facing; a later neutral-stick release uses it as the kick's requested direction with normal passing/shot assistance. Turning while charging is allowed, but reaching full power does not auto-kick. Pause/cancellation clears the press and movement without erasing the taker's facing or moving the ball. Red's automatic restart is unchanged.

---

# 11. Basic AI

Implement deliberately simple football AI initially.

Teammates:

- maintain approximate formation
- move forward when attacking
- provide passing options
- occasionally make forward runs
- move toward useful space rather than directly following the ball

Defenders:

- return toward their defensive positions
- track nearby attackers
- pressure the ball when appropriate
- cover space behind the pressing defender

Avoid having every player swarm toward the ball.

Use roles/formation anchors combined with contextual movement.

Milestone 1 excluded AI. The retained 3v3 exercise has simple support movement, opposition pressure, receiving and interceptions, with empty goals. Build 10’s 5v5 match uses one autonomous goalkeeper and four outfield players per team with simple 2–2 formation anchors. A player pressures the ball while teammates cover or offer passes; avoid sending the whole side toward possession. For a later 11v11 match, use one goalkeeper and a 4-4-2 outfield formation. Team size and formation anchors should be data, not assumptions embedded throughout the code.

AI quality is secondary to getting player control and ball physics right.

---

# 12. Goalkeepers

Build 11 distinguishes keeper hands from feet. The retained practice drills keep empty goals.

- Position, close down and save automatically off the ball, using actual reachable contact, ball height and speed.
- An opposition ball can be caught inside the keeper's own area. A caught ball stays secure; challengers cannot steal it or push the keeper backwards.
- Select blue's keeper on possession. Aim and tap from the hands for a throw, or hold and release for a longer punt. Sideways joystick aftertouch can bend the punt. Red's keeper distributes automatically.
- A deliberate teammate ball, including a backpass, stays at the keeper's feet. The handling restriction survives their own touches and posts and clears on an opposition touch. Use ordinary running, kicking and dispossession, with reduced keeper pace and ball skills.
- A keeper can be an intended backward-pass receiver and move before it arrives. Ordinary off-ball directional switching still chooses outfield players.
- Blue goal kicks wait for manual aim and ACTION; opposition goal kicks remain automatic. Cancelled presses do not release held possession.
- Use amber/violet jerseys, team trim, gloves and a GK badge. Show a caught ball at the hands and keep foot possession visually distinct. Preserve dive recovery and clear state across restarts.

---

# 13. Match rules

Build 10 implements the 5v5 milestone approved after the Build 9 feel review on 7 September 2026:

- Four outfield players and one autonomous goalkeeper per side, with simple 2–2 outfield formations.
- One period of **three minutes of active play**. Blue attacks north and red south throughout; no half-time or change of ends.
- Pause the clock during goals, all restarts, foul presentation, user pauses, help, settings and app interruptions. Resume from the saved active-play time without counting time spent away.
- Label the score Blue and Red. Count goals once using the existing whole-ball crossing, posts and crossbar rules; give the conceding team the next kickoff.
- Award a throw-in after the whole ball leaves a touchline, to the side opposite the last touch.
- Award a corner after a defender puts the whole ball beyond their own goal line outside the goal; otherwise award a goal kick. A boundary rescue must contact the ball before it leaves play.
- Keep throw-ins, corners, goal kicks and kickoffs simple and legible. Blue’s taker, including the goalkeeper at goal kicks, aims in place and uses fresh ACTION input; opposition restarts happen automatically. Throw-in distance increases with the hold duration and never turns the throw into a shot. Clear old held/queued input when placing a restart.
- Retain foul contact, recovery, yellow/red cards and free kicks. Discipline persists across ordinary restarts; dismissals cannot silently return players. End play if a side has no eligible outfield player.
- At zero active time, stop play and show the result. **Play again** or **New match** resets score, time, cards and transient actions for a fresh match.
- Keep Pass & defend and Solo practice available from the Play mode setting with their original untimed goal tallies and quick ordinary resets.

Defer 11v11, offsides, penalties, advantage, substitutions, half-time, detailed tactical systems, leagues, career mode, headers, controller support and multiplayer. The simple restart system does not attempt the full laws of football.

The historical Milestone 1 requirements below describe the accepted original sandbox; Build 10’s match rules supersede its match-related exclusions.

For Milestone 1:

- Count a goal only when the whole ball crosses the goal line within the goal mouth; crossing elsewhere is out of play.
- Resolve fast ball movement against posts and the scoring boundary so a powerful shot cannot skip a collision or count twice.
- After a goal or when the whole ball leaves the pitch, briefly show the outcome and reset the player and stationary ball to a predictable central starting position.
- Clear velocity, control claim, shot charge, aftertouch and active touches on reset. Require a fresh touch before ACTION can fire again.
- Include an always-available reset/recover-ball control for quick experimentation.
- Show a simple tally for each goal. A competitive match clock, halves, teams and kickoff rules are deferred.

---

# 14. Visual prototype

Use deliberately simple original placeholder visuals:

- green pitch
- alternating subtle mowing stripes
- white markings
- goals
- small coloured player sprites
- visible ball
- player-control marker
- simple goal tally in practice; Blue/Red score, active clock and full-time result in 5v5 match
- translucent touch controls

Two teams can initially be:

Blue
Red

Players should be small enough that approximately one third to one half of the pitch length can usually be seen.

Prioritise gameplay readability.

Use shape or marker differences as well as colour when distinguishing roles and teams. Keeper gloves/GK badges and team kit trim should remain readable with ten players. Keep the ball, player marker and power indicator readable against pitch stripes. Menus and settings should respect Dynamic Type and Dark Mode; verify HUD contrast, enlarged text and portrait layout, including keeping the app in portrait when the device rotates sideways. Optional gameplay haptics accompany actual human kicks and challenge contacts involving the controlled player, with distinct kick, shot and tackle strengths. A prepared kick triggers feedback only on actual contact; missed slides, ordinary dribbling and cancelled actions stay quiet. Foul impact feedback occurs at collision before the later whistle. Turning Gameplay haptics off, pausing or detaching the game view clears pending feedback without replaying old events. Haptics and audio supplement visible action feedback and are never required to understand an action.

---

# 15. Architecture

Keep gameplay code modular.

Suggested components:

GameScene
MatchController
Player
Football
Team
PlayerController
BallController
AIController
GoalkeeperAI
CameraController
InputController
MatchState
GameplayTuning

Separate:

input
simulation
rendering
AI
match rules

Do not put all game logic in GameScene.swift.

Use delta-time-based movement rather than frame-dependent constants.

For Milestone 1, use these concrete boundaries:

- **InputController:** owns touch tracking and emits movement direction plus timestamped ACTION press/release/cancel events. Use event times for tap/hold duration so classification is not dependent on rendering rate. It does not move sprites or determine possession.
- **Gameplay simulation:** owns player/ball state, movement, dribble touches, kicking, possession, aftertouch and collision rules in plain Swift using consistent pitch units.
- **MatchController/MatchState:** owns sandbox reset, goal events, counters and pause/resume. Team and AI responsibilities arrive later.
- **GameScene/CameraController:** draws simulation state, transforms pitch coordinates into screen positions, moves the camera and displays controls/HUD/debug information.
- **GameplayTuning:** provides documented values shared by those systems, with an easy way to restore defaults.

Use SpriteKit for presentation and frame callbacks, with a small custom 2D simulation as the sole owner of player and ball movement. Do not let SpriteKit physics and custom code both integrate the same objects. Use simple circular player/ball contacts and swept ball collision checks for posts and goal/boundary crossings; avoid a general-purpose physics engine inside the game.

Advance gameplay in fixed 1/60-second steps from a frame-time accumulator. Process input before each simulation step and interpolate presentation when useful. Cap catch-up work to avoid an unbounded loop after a stall. On pause/backgrounding, clear transient input and reset timing; resume without replaying the time spent away. The rendering target is 60 fps; verify it on the physical acceptance device rather than inferring performance from the simulator.

Keep AI consuming movement/action intents through the simulation. The 5v5 match adds only the keeper, formation, clock and restart responsibilities it needs; do not prebuild networking, replay infrastructure or later competition systems. Keep the retained exercises working through the same gameplay core. The separation of simulation and presentation should make focused checks possible without running a SpriteKit scene.

---

# 16. Debugging tools

Include an optional debug overlay that can display:

- player velocity
- ball velocity
- current controlled player
- possession state
- intended pass target
- AI target position
- aftertouch vector
- shot power
- FPS

Also provide toggleable visual debug lines for:

- player movement targets
- passing direction
- selected pass candidate
- ball trajectory
- aftertouch force

These will be important when tuning gameplay.

Implement only indicators relevant to the current milestone; the passing/defending exercise can now show its pass target and selected-player/possession information. For Milestone 1, also show ACTION state (idle/pressed/charging), kick eligibility and remaining aftertouch time, so control problems can be distinguished from physics problems.

Provide a lightweight tuning panel for the main movement, dribble, shot and curve values, plus restore-defaults and reset-ball actions. Keep it accessible from a small debug control rather than cluttering normal play. Record the tested values and a short observation for each playtest; only add persistent presets if simple sessions prove insufficient.

---

# 17. First milestone — accepted; retained as Solo practice

Do NOT attempt to implement the entire finished game immediately.

The accepted Milestone 1 scope was a playable sandbox containing:

- pitch
- camera
- one controllable player
- virtual joystick
- ball
- arcade dribbling
- passing/kicking
- charged shots
- aftertouch/curved shots
- two goals
- goal detection

No AI players are required for this first milestone.

Explicitly exclude teammates, passing assistance, tackling, automatic switching, goalkeepers, a match timer, ball height, sprinting, controller support, multiplayer, polished assets and team management. Goals are empty so the sandbox tests aiming and curve directly.

### Original implementation sequence

1. **Movement and presentation:** create the pitch, one player, camera and simultaneous touch controls; establish pause/reset handling and the tuning structure.
2. **Independent ball and dribbling:** add loose control, nudges, friction, kicking reach and reliable release/recovery behaviour.
3. **Tap kicks and charged shots:** add press/release classification, manual aim, power feedback and clean cancellation when control is lost.
4. **Aftertouch:** add the short curve window, shooter coasting, bounded curve and predictable return to movement.
5. **Sandbox review:** complete post collisions, goals, out-of-play resets, relevant debug tools and device/layout validation; tune with the user before progressing.

The first milestone is successful if I can:

1. run around the pitch
2. dribble the ball naturally
3. kick/pass it
4. hold the button to shoot harder
5. bend shots using the joystick after striking the ball
6. score into either goal

Focus heavily on the **feel** of these mechanics.

### Acceptance and validation

- **Movement:** 360-degree running, responsive ordinary turns and a visible but brief loss of momentum on a full-speed reversal. Releasing the stick slows the player predictably.
- **Dribbling:** the ball visibly travels between touches; normal turns retain useful control, while sharp full-speed turns can expose it. The player can recover a loose ball without a scripted snap.
- **Kicking:** quick release kicks in the chosen direction; holding increases shot power up to its limit; every press produces at most one kick. No automatic goal aiming occurs, and deliberately poor aim can miss.
- **Input edge cases:** movement and ACTION work together; a charging player can still dribble; losing control, cancelling a touch or pausing cannot produce a ghost shot or stuck joystick. A released ball is not immediately recaptured by its kicker.
- **Aftertouch:** upward, downward and diagonal shots curve gradually in the intended screen direction; neutral or original-direction input adds no curve; the shooter coasts while curve has priority. Curve stays within its cap and ends on contact/expiry/reset. Ordinary expiry or contact restores movement from the existing joystick input; a reset, pause or interruption clears input and requires fresh touches.
- **Goals and resets:** powerful shots cannot pass through posts unchecked; a genuine goal counts once; shots that miss and go out of play restart reliably. A rebound that remains on the pitch stays live. Reset always removes old input, charge and curve.
- **Presentation:** the ball remains visible during a maximum-power shot; controls do not obscure the central action or conflict with system safe areas. For the current portrait revision, check the nominated iPhone and representative iPad simulator sizes, including hardware rotation while the app remains portrait.
- **Performance:** target a sustained 60 fps during a proposed 10-minute mixed session on the iPhone 17 Pro Max, including repeated charged shots, camera tracking and resets. Inspect frame pacing and any repeated stalls; use Instruments to investigate observed problems. Simulator results alone do not establish device performance.
- **Focused simulation checks:** when implementation begins, cover tap/hold boundaries and cancellation, kick escape/reacquisition, aftertouch direction/limits/expiry, swept goal/post crossings and consistent outcomes under different render-frame sequences. Manual physical-device playtesting remains the acceptance test for feel.

The Milestone 1 handoff was completed and accepted. Its original mechanics remain useful for regression checks, while explicitly authorised changes such as queued actions and chips supersede the older exclusions. The user accepted the Build 9 passing/defending foundation on 7 September 2026 and authorised the 5v5 match; review that match before progressing to 11v11.

The handoff should include build/run instructions, the tested device and OS, default tuning values with units and suggested ranges, known rough edges, and a short playtest checklist. The user has given both Milestone 1 and Build 9 feedback and authorised 5v5. Obtain fresh gameplay feedback on keeper behaviour, team spacing and the complete match loop before starting 11v11; passing technical checks alone does not establish that it feels right.

## Roadmap after the accepted first sandbox

1. **Passing and defending exercise — Build 9 feel accepted 7 September 2026:** portrait-only, initially three blue players against three red players, blue attacking north. Each new left-thumb touch centres the floating joystick; wider pass assistance, remembered deliberate aim, a 0.26-second tap window and short return lanes support quick exchanges. Optional haptics mark actual kicks and challenges. Rapid automatic selection follows joystick intent, using nearby players who can meet the ball or block the moving carrier without an ACTION tap. Running into the ball remains the primary tackle, with forgiving front/side contact and sustained close pressure from behind; held slides and prepared kicks remain. Retains simple support/pressure AI, off-ball speed advantage, chips, boundary saves and optional tap selection. Includes richer foul animation and recovery, stickier pickup, forgiving directional passes, prepared first-time kicks, chaseable untargeted taps and goal-assisted shots. Intended-receiver joystick control and stationary free-kick aiming remain. Keeps two empty goals, goal tallies and quick ordinary restarts; no goalkeeper or match clock. Build 9 defaulted to Pass & defend and retained Solo practice. Its accepted controls remain the foundation for the next match milestone.
2. **5v5 match — Build 10 installed and launched:** current default, four outfield players and an autonomous goalkeeper per side, simple 2–2 formations, Blue/Red score, three minutes of active play in one period, goals and conceding-team kickoffs, throw-ins/corners/goal kicks, retained fouls/cards/free kicks, and full-time result/Play again. Preserve both earlier practice modes. Core checks, normal phone/iPad match UI, three enlarged-text/Dark Mode checks, final signing and physical installation/launch are verified. This milestone is ready for match feedback on spacing, keeper behaviour and restarts.
3. **11v11 and real clubs — build 12 accepted:** Premier League friendlies, 4–4–2 / 4–3–3 / 4–2–3–1, starting XI selection, club colours, player identities and arcade ratings.
4. **Premier League career — build 13:** saved seasons, home/away fixtures, simulated opposition results, tables and season history. Keep the match foundation and frozen career data; management and additional competitions remain later milestones.
5. **World Cup mode — planned:** independent national-team tournament save; 48 teams in 12 groups of four; three group matchdays; top two plus eight best third-placed teams into a fixed Round-of-32 bracket; compact extra time and playable penalties; saved three-minute match progression; and a DEBUG-previewable gold-trophy winner celebration. See [the full World Cup mode plan](Documentation/WORLD_CUP_MODE_PLAN.md).

Revisit controller support, headers, the remaining football rules, wider device/OS coverage and distribution after the core match works. Multiplayer requires a new scope and architecture decision if the user chooses it; the current plan makes no promise of a drop-in online mode.

## Apple references

Use official Apple guidance through Sosumi when implementing platform details:

- [SpriteKit scene update callback](https://sosumi.ai/documentation/spritekit/skscene/update(_:)) — app logic runs before scene actions and physics.
- [Preferred rendering frame rate](https://sosumi.ai/documentation/spritekit/skview/preferredframespersecond) — the requested rate depends on display capabilities and must be measured in practice.
- [Game controls](https://sosumi.ai/design/human-interface-guidelines/game-controls) — thumb placement, safe areas, simultaneous touch controls and visible interaction feedback.
- [Safe-area changes](https://sosumi.ai/documentation/uikit/uiview/safeareainsetsdidchange()) — update control geometry and cancel stale touches when the usable layout changes.
- [Impact feedback](https://sosumi.ai/documentation/uikit/uiimpactfeedbackgenerator/impactoccurred(intensity:)) — native impact events with an intensity between 0 and 1; tactile strength still needs device playtesting.

## Guiding gameplay philosophy

The game should be:

FAST
SIMPLE
RESPONSIVE
SKILL-BASED
SLIGHTLY CHAOTIC
EASY TO LEARN
HARD TO MASTER

Do not try to create a football simulation.

The enjoyable interactions should come from player movement, imperfect ball control, manual aiming, passing into space and exaggerated-but-believable aftertouch.

When faced with a choice between realism and fun arcade responsiveness, favour arcade responsiveness.
