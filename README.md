# Top Scores — Premier League Football

## Two-button controls — 13 September 2026

**PASS / BLOCK** plays an immediate short ground pass on the ball and a standing tackle off it. **SHOOT / LONG BALL / SLIDE** shoots within 35 metres of the opposition goal, plays a lofted long ball outside that range, and starts a slide tackle immediately off the ball. Both buttons keep their positions; their labels describe the current action.

Shots always take priority over crosses inside shooting range, regardless of nearby teammates or facing direction. Hold the shooting button and release to strike. Charging begins immediately and reaches maximum power at 0.95 seconds. The meter beneath the player shows a recommended band that rises and narrows with distance. Underpowered attempts lose pace; excess power increases lift and directional error. Distance, body position and player ability affect execution. A good release never guarantees a goal.

Outside shooting range, the long-ball button can produce an assisted cross from the wing. Incoming balls retain first-time passing and shooting/header preparation. Ordinary defensive presses tackle; they no longer switch players. The joystick still selects players. Restarts use short and long buttons, with short/long throws in the keeper’s hands and at throw-ins. PASS is disabled for penalties. Touch cancellation, pause and loss of possession cancel a charge without a kick or slide.

Validated on 13 September 2026: all **600 native tests** pass. The 16 targeted iPhone touch checks have passing results; the keeper and split-control checks passed again after replacing a fixed receiver assumption with the highlighted short option. Four iPad mini checks pass in Dark Mode at the largest accessibility text size. Phone/tablet controls and the under-player power meter were visually checked, and the unsigned iOS Release build succeeds. This update has not been installed on a physical device.

The older dated checkpoints below describe their controls at the time. Current controls are listed under **Play**.

Control references: [PES separate passing, shooting and lofted controls](https://dds.konami.com/games/manual/pes2019/PC/en-us/control_base.html), [FIFA Mobile shooting power and tackle controls](https://www.ea.com/ea-originals/news/gameplay-guide-button-controls), [Sensible World of Soccer hold-for-power controls](https://files.swos.eu/manual/SWOS1.1/SWOS1.1manual.pdf), and [Apple button accessibility and hit targets via Sosumi](https://sosumi.ai/design/human-interface-guidelines/buttons). The 35-metre rule and distance-dependent release band are specific to this game.

A native iOS arcade football game with responsive dribbling, quick passing, charged shots, curve and chips. Choose two Premier League clubs, edit their starting XIs and formations, and play an **11v11 friendly with three minutes of active play**. The home club is controlled by you; a coin toss chooses starting ends and teams swap ends at half time. Goals, throw-ins, corners, goal kicks, fouls, cards and free kicks lead to a full-time result, **Play again**, or **Choose clubs**. The Training menu opens **Pass & defend** and **Solo practice**.

## Crossing and headed goals

In a wide attacking position, hold ACTION and release in the green band to cross automatically towards a runner in the box. Short holds underhit the delivery; excessive holds can send it beyond the attackers. Players make box runs, and a tap as the cross arrives attempts a header towards goal. Position, contact distance, height and timing affect the result; higher-rated midfielders and attackers cross more accurately, and higher-rated strikers finish headers better. The usual offside, goalkeeper and goal-line rules still apply at either end.

Validated on 10 September 2026: all **584 gameplay/native tests** pass, including live cross-to-header sequences, both attacking ends, offside, power, timing, ratings and opposition aerial play. Phone and tablet control layouts were visually checked, and the iOS Release build succeeds.

## Difficulty, halves and injuries

Choose **Easy**, **Medium** (the default), or **Hard** on Friendly setup or in **Tune the feel → Difficulty**. The choice is saved for future friendly, Career and World Cup matches. It changes opposition running speed, keeper movement/anticipation, reaction timing and passing choices. Easy also adds kick error; Hard checks passing lanes and receiver space. Your team's movement remains unchanged.

Matches now have **two 90-second halves**, with **Start second half** at the break. A coin toss randomises the starting direction, and teams swap ends for the second half. Kickoff and half-time messages show which goal you attack. Near goal (within 24 metres), a goalward quick tap shoots when there is no nearby teammate available in the aimed direction (within 18 metres). A nearby aimed pass still takes priority; holding continues to add shot power. Time lost to goals, restarts, free kicks and foul treatment is tracked separately and shown as **+seconds** near the end of each half, preserving three minutes of live play. Pausing, opening settings and choosing a replacement stop the clock. Either whistle waits for a near-goal attack, corner, dangerous free kick/throw-in or penalty to finish; a goal, clearance, keeper catch or defensive restart ends that extension. Extra time has two 30-second halves with the same rules.

Each foul has a **4% injury chance**, independent of difficulty and cards. After the foul animation, an injured player must leave. Choose an unused squad replacement for your team; the opposition chooses automatically. The picker shows position, shirt number and rating, and excludes current starters, injured players and players already replaced. If no eligible replacement remains, continue one player short. Injuries, substitutions and cards carry through half-time and extra time; a new match restores the original XI. Injuries do not carry into later fixtures.

Validation on 10 September 2026: all 546 gameplay/native tests pass, with iPhone and iPad touch checks for both starting directions, half-time end changes and replay. The half-time screens were visually checked on both devices, and the iOS Release build succeeds.

Validation on 8 September 2026: all 538 gameplay/native tests passed, together with iPhone and iPad touch checks for difficulty, injury selection, half-time and replay. Friendly and World Cup progression checks passed, including extra time and penalties. The iPad settings and injury picker were visually checked in Dark Mode at the largest accessibility text size. The iOS Release build also succeeds.

## World Cup mode

Open **World Cup**, choose one of 48 national teams, and play through 12 four-team groups followed by the Round of 32, Round of 16, quarter-finals, semi-finals and final. The top two in each group and the eight best third-placed teams advance. Country flags identify every nation. After the first matchday, the dashboard adds an expandable results lozenge: it previews the other result in your group, then shows every completed group when opened. Results use a fixed home–score–away grid, with transparent flags, colour-coded group stripes and matching dashed group separators. In the knockout phase the lozenge becomes a swipeable score strip for the other ties in the latest completed round, with the expanded history reaching back to the opening group games. **Group tables & results** opens a Group A–L browser with live standings, automatic-qualification and best-third-place dividers, plus every fixture for the selected group. Tournament progress and lineup changes save automatically in their own file, independently of Career.

Regulation uses the normal three-minute match. Simulated fixtures use ranking-informed team strength, an Elo-shaped expectation and a bounded match-day form swing, so favourites win more often while draws and occasional upsets remain possible. A level knockout match continues to extra time; if it is still tied after 120 represented minutes, an interactive alternating penalty shoot-out decides the winner, including early clinches and sudden death. Simulated knockout games can also finish after extra time or on penalties, and those decisions are labelled in results. Winning the final opens an accessible animated gold-trophy celebration with gleam, falling gold ticker tape, original crowd audio and haptic feedback. DEBUG builds show **View trophy celebration** at the bottom of the World Cup screen and expose a deterministic final-flow route for testing; those routes are absent from Release builds.

While playing any World Cup fixture in a DEBUG build, use the fast-forward button in the match toolbar to open **Debug match controls**. Choose an instant 1–0 win, 0–0 draw or 0–1 defeat. Knockout fixtures also offer direct jumps to extra time or the interactive penalty shoot-out. Instant results use the normal save and bracket path, so eight debug wins can test the full group-to-final journey and trophy celebration without playing out the clocks. These controls are not compiled into Release builds.

## Restart options and penalties — build 20

**Build 20 is installed on the iPhone.** All 529 gameplay/native tests and six phone/iPad touch checks pass. Unlock it and open **Top Scores Soccer**; the lock prevented automatic launch.

Two nearby teammates now offer short options at throw-ins and free kicks, while free-kick opponents stay 10 yards away. Box fouls lead to a live penalty after the full challenge animation: aim and tap to shoot, or use the shot power meter for a held kick. See [build 20 controls and verification](Documentation/BUILD20_SET_PIECES.md).

## Targeted keeper distribution — build 19

**The build 19 checkpoint was installed on the iPhone.** All 490 gameplay/native tests passed, with passing phone and iPad touch checks. Unlock the phone and open **Top Scores Soccer**; the lock prevented automatic launch.

Aim at a highlighted teammate and tap: a keeper holding the ball chooses an underarm or overarm throw, adding height to clear an intervening opponent. A goal kick uses the same target selection with a low or lofted foot kick. Hold for a longer, higher overarm throw or goal kick. Keeper ability affects range, pace and accuracy; control transfers immediately to the receiver. See [build 19 playtest and verification](Documentation/BUILD19_KEEPER_DISTRIBUTION.md).

## Coordinated passing — build 18

The build 18 checkpoint was installed on the iPhone and its improved passing feel was accepted. All 469 gameplay/native tests passed, with passing phone and iPad UI checks.

A tap commits the indicated teammate, then plans the ball’s direction and pace for the run you are asking him to make. Control moves to him immediately; keep steering to run, or centre the stick to meet the ball automatically. A cushioned first touch now flows into the next stride. Target brackets, a handover pulse and receiver-aware camera framing make the switch visible. See the [build 18 playtest and verification](Documentation/BUILD18_PASSING.md).

## Immediate receiver movement — build 16

**Build 16 is installed and launched on the connected iPhone.** All 410 gameplay/native checks and five selected phone UI checks passed.

After a teammate pass, any active joystick direction moves the receiver immediately, including the direction held through the pass and small deliberate movements. Centre or release the stick to let the receiver meet the ball automatically. He also follows a nearby pass that slows down or runs past him. The same assistance applies when passing back to your keeper, while keeping his weaker foot skills. See the [receiver playtest notes](Documentation/BUILD16_RECEIVER_CONTROL.md).

## Passing and aerial play — build 15

**The build 15 checkpoint was installed and launched on the connected iPhone.** All 400 gameplay/core checks passed; eight selected phone checks and two enlarged-text iPad checks have passing results. The verification record includes one intermittent dropped release that did not recur in four consecutive phone reruns.

Passing now chooses clearer lanes, helps the receiver meet the ball and cushions the first touch. Short taps retain an available teammate across the whole aiming cone. Hold ACTION for roughly a second in defence to kick high and long; close to goal, the shot sweet spot still applies. For a reachable high ball, aim and tap when **HEAD** appears; a brief early tap prepares the contact. See the [controls and verification record](Documentation/BUILD15_GAMEPLAY.md).

## Movement and restarts — build 14

The build 14 checkpoint was installed and launched on the connected iPhone. All 359 core tests and nine phone touch checks passed, with passing iPad checks and enlarged-text offside verification. Career saves, squads and lineups are retained; the [playtest guide](Documentation/PLAYTEST.md) records the test runs and what to try.

- Kickoff pairs two players inside the centre circle. A neutral tap uses the nearby lateral option; aim backwards or elsewhere to choose another teammate.
- When a keeper holds the ball, opponents withdraw from his area and both teams spread into shape. One teammate comes close for a short throw. Everyone moves naturally; your keeper still waits for your distribution input.
- In possession, teammates share short passing support and forward runs into open lanes while others maintain formation. Runners hold behind the offside line before release and can chase beyond it once the pass is played.
- Match play now awards an **indirect free kick for offside involvement**. Position is sampled at a teammate's touch; being level, behind the ball or in your own half is onside. Direct throw-ins, corners and goal kicks are exempt. Keeper throws/punts in open play are not. Another player must touch an indirect kick before it can score. The empty-goal practice drills keep their previous rules.

These arcade decisions follow the receiving, rebound and restart principles in [IFAB Law 11](https://www.theifab.com/laws/latest/offside/). Player centres represent position; the game does not simulate sight-line obstruction or VAR.

## Premier League career — build 13

The build 13 career checkpoint passed all 323 core tests and fifteen phone/iPad UI checks; the playtest guide records individual runs and visual review.

Open **Career**, choose your club, then tap **Start career**. Play all 38 home/away fixtures, follow the league table, and start another season after the final match. Edit your starting XI before any fixture. Your club always attacks the top goal, including away games; the scoreboard and kits follow the fixture's actual home/away order.

- Your full-time result and the other nine matchweek results save together automatically on this device. The other games use a small rating and home advantage with room for upsets. The table awards three points for a win and one for a draw, then separates clubs by goal difference, goals scored and club name.
- Saved careers keep their original squads, ratings and cosmetic appearances. Your selected formation and XI survive app restarts and carry into the next season. Past season tables and fixtures remain in season history.
- Leaving an unfinished match asks first and keeps the fixture unplayed; it restarts from kickoff when you return. A failed save keeps the finished result on screen for **Retry save**. Starting a replacement career asks before replacing your existing save and history.
- A club losing every outfield player forfeits 0–3. Cards reset for the next fixture. These are arcade league rules, with generated fixtures rather than the real Premier League calendar.
- The **Friendly** tab and its **Training** menu remain available. This milestone keeps the same clubs across seasons; transfers, promotion/relegation, management and other competitions remain later work.

## Premier League playable checkpoint — build 12

- All 20 clubs and 631 players are included from the Top Scores snapshot published on 7 September 2026. The game is playable offline immediately. Squad refresh validates a complete export before replacing the local cache, checks daily, and uses ETags to avoid unchanged downloads. A match retains its starting squad even if the catalogue updates.
- Pick the home and away clubs independently. Choose **4–4–2**, **4–3–3** or **4–2–3–1**, then tap a starter to choose a squad replacement or swap positions. Each XI contains one goalkeeper and ten outfield players.
- One overall rating drives bounded arcade differences in pace, acceleration, control, pass/shot power and accuracy, defending and goalkeeping. The conversion is game balancing, not measured detailed scouting statistics. Missing ratings show **EST.**; incomplete squads receive labelled stand-ins.
- Source club colours determine simple kits. The away side receives an alternative when shirts clash; goalkeepers have distinct colours. Source squad shirt numbers and selected player names appear during matches.
- Six skin palettes and four simple hair shapes give players stable visual variety by player ID. These are generated cosmetic appearances, **not photo-matched likenesses**. A local appearance override resource can supply reviewed portrait-based choices later.
- Career seasons were added in build 13 and offside decisions in build 14. Transfers and voluntary tactical substitutions remain deferred; halves and injury substitutions are now supported.

Open the app, choose clubs, open **Starting XI** if desired, then tap **Kick off**. On the pitch, tap ACTION to take the opening kickoff. The bright ring shows the player you control. Use the close button to return to club selection.

Validation and device delivery are recorded in [the playtest guide](Documentation/PLAYTEST.md).

Built with Swift, SpriteKit and SwiftUI. Supports iPhone and iPad in **portrait only** on iOS/iPadOS 18 or later. Turning the device sideways keeps the game in portrait. No third-party dependencies or project-generation tools are required.

## Build and install on your iPhone

1. Open `TopScoresSoccer.xcodeproj` in **Xcode 26.6**.
2. Connect and unlock your iPhone. Complete pairing or Trust prompts if they appear.
3. Select the shared **TopScoresSoccer** scheme and your actual iPhone as the run destination in Xcode’s toolbar.
4. Automatic signing is already configured for the existing development team. If you use another Apple account, select your team under the app target’s **Signing & Capabilities**, keeping **Automatically manage signing** enabled.
5. Choose **Product → Run** or press **⌘R**. Xcode builds, installs and launches the app on the selected phone.

These steps follow [Apple’s build, signing and device Run guidance](https://sosumi.ai/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

If Xcode requests Developer Mode, enable **Settings → Privacy & Security → Developer Mode** on the phone, restart, then confirm enabling it after restart. The setting may appear only after pairing begins. See [Apple’s Developer Mode instructions](https://sosumi.ai/documentation/xcode/enabling-developer-mode-on-a-device).

The nominated playtest device is the **iPhone 17 Pro Max**. Select a simulator instead to try the app on the Mac, and record the actual model and OS if you use a different phone.

The keeper possession, variable throw-ins, through balls, shot-height control and backheels from build 11 are retained. Earlier test records remain in the [playtest guide](Documentation/PLAYTEST.md).

## Play

The controls below also describe the retained generic practice matches. In Premier League friendlies, references to **blue** mean your home club and **red** mean the away opposition; clubs wear their own resolved kits and the match has eleven players per side.

- **Move and aim:** touch anywhere on the left side of the pitch and drag. Each new touch starts neutral and places the joystick centre exactly under your thumb; a longer drag requests more speed. Lift to stop steering, then touch somewhere else on the left to recenter. The ring is visible while you are touching. Players run **12% faster off the ball**. Nearby loose balls and incoming friendly passes are easier to collect, and frequent touches keep ordinary dribbling close. High balls and hard shots retain their contact restrictions; tackling opposition possession follows the running challenge rules below.
- **Pass:** aim towards a nearby teammate and press PASS. Cyan brackets show the short recipient. The pass executes on button-down with automatically judged pace. Holding cannot select a distant player or turn it into a shot.
- **Move the receiver:** an assisted teammate pass selects its intended receiver immediately. Every active joystick direction controls him straight away, even if it is unchanged from the passing aim. Centre or release the stick for automatic movement towards the incoming ball; a new drag takes over at once. Untargeted knock-aheads keep control with the kicker.
- **Knock ahead:** press PASS when no teammate is in the aiming cone, including Solo practice. The ball rolls a short distance to chase: **9 m/s** from standing, with extra pace when running forward.
- **Pass and move:** closer passing options compete more strongly with distant teammates. The passer and supporting teammates move into short return lanes while the ball travels; control still goes immediately to the receiver. Prepare the next kick before arrival for a quick one-two.
- **Haptics:** your kicks and challenges involving your player give brief, distinct impacts on supported devices. An empty slide, ordinary running and cancelled or merely queued kicks stay quiet. Turn **Gameplay haptics** off in settings if preferred.
- **Shoot or kick long:** tap or hold SHOOT inside 35 metres of goal. The stick influences placement, with neutral or backward aim defaulting towards goal. The distance-dependent band indicates suitable power; excessive power adds error and lift. Outside range, LONG BALL lofts the ball in your chosen direction, with longer holds adding distance. The action shown at button-down stays captured for that charge.
- **Cross:** outside shooting range, CROSS appears when the winger has an available runner in the box. Hold and release in green for an assisted delivery. Weak crosses fall short; overpowered crosses can sail past the receiver. Use PASS for the short option. Inside shooting range the button always shoots.
- **Head:** press HEAD as a reachable aerial ball arrives to attempt a goal-directed header inside shooting range or a directional clearance outside it. HEAD PASS requests a directional header pass. Timing and contact quality still matter; an early press can briefly queue the header.
- **Bend a shot:** move the stick sideways immediately after the kick. For **0.65 seconds**, the stick curves the ball while your player coasts. Movement then resumes from the current stick position.
- **Chip:** pull the stick back against the original kick direction within **0.24 seconds** of the ball being kicked. The ball lifts into the air; ordinary foot contacts cannot reach it until it drops. A prepared first-time kick needs a fresh stick change after contact for chip or curve input. The timing is deliberately demanding.
- **Choose a runner with the stick:** off the ball, point the joystick toward the run you want. Selection quickly favours a nearby blue player whose movement in that direction can meet the ball or block the carrier’s path. That can be someone other than the player closest to the ball. No ACTION tap is needed. Watch the marker under the selected player.
- **Win it by running:** move toward the ball from in front of or beside the carrier, without pressing ACTION. Close front and side approaches are forgiving. From behind, stay close and keep pressing toward the same carrier for about **half a second**; **KEEP PRESSING** shows this opportunity. Losing contact or changing the chase breaks that pressure.
- **Block or slide tackle:** off the ball, press BLOCK for a standing tackle or SLIDE for an immediate slide. Each press makes one challenge. Slides reach farther and need more recovery time. Fouls, bookings and injuries follow the existing ball-first contact rules.
- **Prepare a first-time kick:** when an incoming ball is reachable, PASS prepares a short pass and SHOOT / LONG BALL prepares the corresponding charged kick. The chosen action, direction, recipient and power stay with that player until contact or expiry. Pauses and restarts clear the queue.
- **Slide to save it:** press SLIDE while chasing a ball toward the sideline or goal line. A slide that reaches the ball in time can clear it back into the pitch. An unreachable ball still goes out.
- **Keep a committed action:** the intended receiver of an assisted pass retains priority while the pass travels. Slides, prepared first-time kicks, kick gestures and close rear pressure also protect the player you are controlling. Turning away releases rear-pressure protection. Clear changes of direction can select a better runner immediately; nearby candidates and brief checks for close choices keep selection stable. Sent-off players and off-ball keepers are excluded from ordinary switching. Your keeper becomes controllable when receiving a backpass or gaining possession.
- **Aim a free kick:** move the joystick to turn blue's taker in place. The taker and ball wait for PASS or SHOOT / LONG BALL while nearby teammates move into short passing positions. Letting the stick return to neutral keeps the taker's last facing direction for the kick; usual pass and goal assistance still apply.
- **Restart play:** PASS takes a short kickoff, free kick, corner or goal kick. The other button shoots or plays long as appropriate. Throw-ins and keeper possession offer SHORT THROW and LONG THROW. Penalties use SHOOT; PASS is disabled. Opposition restarts remain automatic.
- **Play again:** at full time, read the result and tap **Play again** for a fresh match. The top-bar reset arrow also starts a new match, clearing its score, clock and cards.

In **5v5 match**, a coin toss chooses starting ends and teams swap ends at half time. The clock counts **3:00 of active play** and stops during goals, restarts, fouls, offside decisions, help, settings and pauses. The score is labelled **BLUE** and **RED**. A goal gives the conceding side the next kickoff. The last touch decides the side awarded a throw-in, corner or goal kick. Match offside, half-time and injury substitutions apply in this mode too. Extra time and tie-breaking penalty shootouts are used for tied World Cup knockout fixtures. In-match penalties are awarded for direct-free-kick fouls in the offender’s own box.

Goalkeeper positioning and saves are automatic. When blue’s keeper catches an opposition ball inside his area, you take control: aim and press SHORT THROW to find a nearby teammate, or hold LONG THROW and release for a long, high overarm throw, then steer sideways for swerve. At a goal kick, press PASS for a short foot pass or hold LONG BALL for a high kick. Open routes use lower deliveries; intervening opponents prompt extra loft. A teammate’s backpass must stay at his feet: run and kick with him, but expect slower pace and less tidy control than an outfield player. A held ball is protected from tackles and body pushing. Red’s keeper distributes automatically. Blue’s keeper wears amber, red’s violet; gloves and a **GK** badge distinguish them from outfield players. Outfield teammates keep a loose 2–2 shape, with pressure, cover and passing support.

On a mistimed tackle, impact and the victim's fall play out for **1.2 seconds** before the whistle and any card. The next **2.4 seconds** show the grounded pause and recovery before placing a free kick at the incident, or a penalty at the spot for a match foul inside the offender’s own box. Take blue's kick with fresh ACTION input; red restarts automatically. Cards persist across match restarts. If a team loses every eligible outfield player to dismissals, play ends. A new match restores the whole team.

In **Pass & defend**, three blues face three reds with empty goals and no clock. The **N** and **S** counters tally goals into those ends, and goals or out-of-play balls trigger quick resets. In **Solo practice**, experiment with either goal. A practice reset clears discipline and actions while preserving its goal tally; **Clear goal tally** is available in that mode’s tuning panel.

The top bar contains **How to play**, **Pause** and **Tune gameplay**. In tuning, choose a **Play mode**, adjust movement and passing, or toggle **Referee whistle** and **Gameplay haptics**. The whistle marks fouls, offside and full time and respects Silent Mode; visible feedback remains available. Opening help or tuning pauses play. After a pause, restart or interruption, use fresh touches. Tuning changes last for the current app session; **Restore default tuning** resets them.

## Test the feel

Use the [match checklist and playtest guide](Documentation/PLAYTEST.md). It records validation status, the tuning ranges and what feedback will be useful. For automated checks, select an iPhone simulator and choose **Product → Test** (**⌘U**).

Play a complete match with the accepted control defaults. Check spacing, keeper saves and distribution, clear restart ownership, the stopped clock during breaks, and a clean full-time result followed by Play again. Keep an eye on player selection and performance with all 22 players. Use the retained drills for isolated mechanics checks. Controller support, voluntary tactical substitutions and multiplayer remain deferred.

### Team management

Friendly, Career and World Cup fixtures now open **Match preparation** before kick-off. Choose Defensive, Normal or Attacking, tap a player on the pitch or in the starting-XI list to replace them, and review their half-star quality rating. Automatic formation follows the selected players (for example, replacing a midfielder with a striker changes 4–4–2 to 4–3–3). Turn it off to choose a formation while retaining the selected XI. Eight common formations are supported; unusual squads retain all selected players and label out-of-position assignments.

Open **Pause → Team management**, or use Team management at half-time, to change tactics and queue substitutions. The clock pauses while editing. Changes to style apply when confirmed; substitutions take effect at the next stoppage, after any foul treatment. Each side has five substitutions across the whole match, including extra time and injury replacements. Sent-off players cannot be replaced and replaced players cannot return. Pending changes can be edited or cancelled.

Pre-match selections are remembered per Friendly team or competition save. Match substitutions and tactical adjustments stay within that match. Existing saves load with Normal tactics and automatic formation enabled. Stars use a fixed scale from 55 (one star) to 95 (five stars), rounded to half-stars; missing ratings retain the existing estimated-rating label. Player icons are cached snapshots of the same artwork used on the pitch.
