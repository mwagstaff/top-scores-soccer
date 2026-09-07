# Build 20 restart support and penalties

Two nearby teammates come short for throw-ins and free kicks. Free-kick opponents stay 10 yards away, and direct-free-kick fouls in the offender's own box award a live penalty after the full foul animation. Aim and tap for a penalty shot, or hold and release in the green band.

**Build 20 is installed on the iPhone.** Unlock it and open **Top Scores Soccer**. All 529 gameplay/native checks and all six phone/iPad restart touch checks pass on the combined build, including the completed World Cup screen update.

See [build 20 phone checklist and verification](BUILD20_SET_PIECES.md).

# Build 19 targeted keeper distribution

**Build 19 is installed.** All 490 gameplay/native tests passed, with passing phone and iPad touch checks. Unlock the phone and open **Top Scores Soccer**; automatic launch was blocked by the lock.

Aim at the cyan-bracketed teammate and tap ACTION when the keeper holds the ball or takes a goal kick. Close open throws are underarm; longer throws are overarm, and intervening opponents prompt a higher arc. Goal kicks use low or lofted foot passes. Hold for a longer, higher overarm throw or goal kick, with immediate control of the intended receiver.

See [build 19 playtest, research and verification](BUILD19_KEEPER_DISTRIBUTION.md). The keeper’s ability affects delivery range and accuracy; ordinary backpass handling, physical interceptions and offside decisions remain active.

# Build 18 coordinated passing and receiving

**Build 18 is installed on the iPhone.** All 469 gameplay/native tests passed, alongside passing phone and iPad UI checks. The phone was locked during automatic launch; unlock it and open **Top Scores Soccer**.

Start with **Friendly → Training → Pass & defend**. Aim roughly at the cyan-bracketed teammate, tap ACTION and keep steering: the yellow control ring transfers immediately and the pass anticipates the receiver’s run. Centre the stick for automatic reception. Try longer passes, moving after the first touch, and aiming/tapping early to chain passes and one-twos. Then repeat in an 11v11 friendly.

See [build 18 mechanics, playtest and verification](BUILD18_PASSING.md). The original 240 controlled passing scenarios now all receive and retain possession for two seconds; defenders still intercept and challenge in the active-match checks. These automated results do not replace a physical feel playtest.

# Build 16 immediate receiver control

**Build 16 is installed and launched.** All 410 gameplay/native checks and five selected phone UI checks passed.

See [receiver controls, verification and phone playtest](BUILD16_RECEIVER_CONTROL.md). The joystick now controls the receiving teammate immediately even when held through the pass; a neutral stick enables automatic movement to meet the ball.

# World Cup mode

Open **World Cup**, choose a national team and play all three group fixtures. Check that the group table and other results advance once per completed match, then close and reopen the app to confirm the next fixture and edited XI persist independently of Career.

- In a knockout draw, full time must say **Level after 90 minutes** and offer **Play extra time**. The score carries into the extra period.
- If still level after extra time, the screen must say **Level after 120 minutes** and start an alternating kick/save shoot-out. It supports early clinches and sudden death; the winning side alone advances.
- Winning the final must save the championship before presenting the gold trophy, gleam, ticker tape, original cheer, haptic and VoiceOver announcement. **Continue** returns to the completed tournament.
- In a DEBUG build, scroll to **View trophy celebration** at the bottom of the World Cup screen to preview the sequence without changing tournament progress. The `--world-cup-celebration` launch route remains available for automation. Add `--world-cup --world-cup-final-ui --short-match --uitesting` to seed a deterministic tied final without changing a normal save. Release builds contain none of these test routes.
- During a World Cup match in DEBUG, tap the fast-forward toolbar button. **End with a win**, **End with a draw** and **End with a defeat** write 1–0, 0–0 and 0–1 through the normal save callback. A knockout draw reaches the ordinary extra-time prompt. **Jump straight to extra time** starts the 90–120′ period at 0–0; **Jump to penalty shoot-out** opens the real alternating kick/save UI. Eight instant wins take the selected team from its three group fixtures through the final and then the saved trophy celebration.

All **420 core tests** pass in the final combined run, including ten focused World Cup model, bracket, persistence, extra-time, shoot-out and debug-shortcut checks. The end-to-end integration check creates eight separate match sessions, commits each debug win to disk through the real store, reloads it, and confirms the selected team is champion with its celebration pending. The Debug app and Release app both compile; Release excludes the in-match shortcut code. The complete 90′ → extra time → 120′ → penalties route and the direct trophy preview were manually verified on an iPhone 17 Pro simulator running iOS 26.5. The new UI automation covers a direct penalties jump and the same eight-win tournament path; the local XCTest runner subsequently stalled while attaching/finalizing those UI runs, so their source is retained but they are not recorded as passing evidence here.

# Build 15 passing, high clearances and headers

**Build 15 is installed and launched.** All 400 gameplay/core checks passed, with passing results for eight selected phone UI checks and two iPad checks. One charged clearance failed to release during the initial phone run; four consecutive unchanged reruns passed, and the unresolved observation is recorded below.

See [Build 15 controls and verification](BUILD15_GAMEPLAY.md) for this update. Try quick one-twos with rough aiming, a roughly one-second held clearance from defence, and an aimed tap when **HEAD** appears under an incoming high ball. Earlier delivery records remain below.

# Build 14 movement, keeper shape and offside

**Build 14 is installed and launched.** The update retains the installed build 13 career, clubs and lineups.

- At kickoff, try a neutral tap to the partner beside the taker, then a deliberate backward pass on another kickoff. Two players should start together in the centre circle and opponents stay back.
- After a keeper catch, watch opponents leave the area and both teams spread into formation. One teammate should approach for a short throw; the keeper should stay protected. Releasing the ball immediately restores open play.
- Hold possession and look for nearby angled support, width, and forward runners finding gaps. Advanced players should hold or recover behind the offside line before release. Play into space, then move the receiver beyond the defenders.
- Test an early runner: offside should be called on involvement, with an indirect free kick and no card. A player level at release can run through legally; coming back after starting offside does not erase the decision. Posts and parries do not reset the pass's offside position.
- Offside is exempt directly from throw-ins, corners and goal kicks; open-play keeper throws/punts follow normal offside. An indirect kick needs another player's touch to score. Empty-goal practice drills keep their previous rules.
- Play and finish a career fixture, then relaunch to confirm the result was saved once and the next round is ready.

| Build 14 check | Status |
| --- | --- |
| Core, simulation, scene, support and career tests | All 359 tests passed on the final production code in the combined phone run. |
| Phone touch, club and career flows | All nine selected UI checks passed: offside, keeper feet/catches, throw-ins, match restarts/full time, edited 11v11 lineups and automatic career saves. |
| iPad and enlarged text | All three selected iPad checks have passing results across the initial and focused runs: offside, edited 11v11 lineups/kickoff, and career full-time save/relaunch without repeating the round. The new offside/pause/manual restart check also passed on iPhone in Dark Mode at the largest accessibility text setting, with readable guidance. |
| Signed device build and installation | Final build passed strict signature verification; installed and launched at 10:46–10:47 on 7 September 2026. The installed-app query confirms version 0.1.0, build 14. |
| Physical balance and sustained performance | User playtest after delivery. |

The offside implementation uses body centres and a small level-position tolerance. It implements receiving/challenging, teammate-touch timing, restart exemptions, indirect scoring and rebound/save persistence; it does not model visual obstruction of a keeper, VAR or off-field disciplinary edge cases. Rules reference: [IFAB Law 11](https://www.theifab.com/laws/latest/offside/).

The final combined passing run is `.test-artifacts/Build14PhoneFinal.xcresult`. The signed build is recorded in `.test-artifacts-build14-delivery.log`; device evidence is in `Build14DeviceInstall.json`, `Build14DeviceLaunch.json` and `Build14InstalledApp.json` under `.test-artifacts/`. The actual connected device is an iPhone 16 Pro Max running iOS 26.6.1. Installation retained the app's data. Physical passing rhythm, run timing and sustained frame pacing remain playtest observations.

The ordinary 11v11 flow passed again in `Build14PhoneKickoffFinal.xcresult`, including an additional screenshot before the opening pass. The paired kickoff and normal/enlarged-text offside screenshots were exported and visually inspected. `Build14PhoneAccessible.xcresult` is a mixed bundle: its offside check passed, but the ordinary club-editing test tried to tap a club card whose centre was below the pinned footer at enlarged text; that helper does not scroll the setup card. This does not establish an app failure. The ordinary flow passed at its intended text setting in the final kickoff run. No production code was changed for that rerun. The owned phone simulator was restored to Light appearance/normal text and shut down.

`Build14Pad.xcresult` is also a mixed bundle: offside and the 11v11 flow passed, but career setup stalled after a correctly positioned automated Start career tap. The recording and hierarchy showed an enabled visible button, with the club picker already dismissed and no save error. The unchanged career test passed with exit code 0 in `Build14PadCareerFinal.xcresult`, including a relaunch and confirmation that only one round was recorded. No app or test-source change was made for this isolated missed tap; report any recurrence during manual play. Stalled post-test diagnostics were stopped only after the tests had finished, allowing their result bundles to finalize. The owned iPad simulator was restored to Light appearance/normal text and shut down.

# Build 13 Premier League career milestone

Choose the **Career** tab, pick a club, and start a season. Friendlies and Training remain under **Friendly**. Career uses all 20 clubs, editable XIs and short 11v11 matches from build 12.

- **First fixture:** read both clubs and the Home/Away labels, edit your XI and formation, then Play next match. Tap ACTION for kickoff. Your chosen club always attacks the top goal, including away fixtures; the scoreboard follows actual home/away order and the actual away side changes kit if required.
- **Full time:** the result and the other nine matchweek results save automatically. Continue season shows the next fixture and updated table. Close and reopen the app on the result screen to check that the finished match is retained without requiring Continue.
- **Between games:** lineup edits, formation, score history and progress survive app restarts. Leaving an unfinished match asks first and retains the unplayed fixture; returning starts it from kickoff. In-progress positions and the clock are not saved.
- **Table and fixtures:** the table shows points, played/won/drawn/lost and goal difference. Ranking uses points, goal difference, goals scored, then club name. Fixtures can show only your club or every match. Results are generated for this game, not taken from the real-world calendar.
- **Season end:** after your 38th match, review the champion and final table. Start season 2 with a fresh table, the same frozen squads and your selected XI. Season history retains previous tables and results.
- **Data and balancing:** careers snapshot the available catalogue at creation. Future catalogue updates affect friendlies and new careers. Simulated results use modest overall-rating and home advantages with room for upsets; repeat save attempts cannot reroll or double-count a round.
- **Interrupted saves:** failed writes leave the previous usable career intact and keep the finished result available for Retry save. A damaged or unsupported save is preserved until the user explicitly chooses to replace it. There is one career save on this device.
- **Arcade discipline:** cards last for one match. A side losing all outfield players forfeits 0–3. The result card displays that awarded score. No transfers, management, promotion/relegation, halves, offside or substitutions are added.

All **323 core tests** passed, covering the retained simulation and 18 new career/domain/session checks. The initial phone run also passed the five retained match/friendly UI checks and the two career save/relaunch checks. The initial iPad run passed season rollover/history and both save/relaunch checks. All **15 distinct UI checks now have passing results**: ten on iPhone and five on iPad across the initial and focused runs. They cover career creation, edited XIs, automatic full-time saves, relaunch without Continue, unfinished away fixtures, season rollover/history, friendly navigation and the largest accessibility text size.

Initial evidence: `.test-artifacts/Build13PhoneFinal.xcresult` and `.test-artifacts/Build13Pad.xcresult`. These are mixed-result bundles: their core and individual passing UI checks are valid evidence, but neither overall run passed. Initial failures came from a test expecting covered dashboard elements to disappear from the accessibility tree and from taps on partly obscured rows. Tests now scroll controls clear of pinned action buttons before tapping. Phone and iPad screenshots of the normal career dashboard, full time and season review have been visually checked. Their exported attachments are in `.test-artifacts/Build13PhoneAttachments/` and `Build13PadAttachments/`.

The focused away/history checks passed in `Build13PhoneCareerVerified.xcresult` and `Build13PadCareerVerified.xcresult`; the former remains a mixed bundle because its first stricter scrolling helper rejected a usable large-text card. The final scrolling helper checks that the tap centre is clear of navigation and pinned actions. Final large-text checks passed on both devices in **`Build13PhoneAccessible.xcresult`** and **`Build13PadAccessible.xcresult`**, with zero failures and successful command exits. The phone run also rechecked ordinary full time/Play again. Result cards now use stacked club/score rows at accessibility text sizes, with more width on iPad. Both final result screenshots were inspected and names, scores, save status and Continue are readable and reachable. Final exports are in `Build13PhoneAccessibleAttachments/` and `Build13PadAccessibleAttachments/`.

The final signed device build (`.test-artifacts-build13-device-delivery.log`) passed strict signature verification. Installation on the connected iPhone 16 Pro Max succeeded at 02:42 on 7 September 2026. The installed-app query confirms version **0.1.0, build 13**. Automatic launch was denied because the phone was locked; unlock it, open Top Scores Soccer and select Career. Evidence: `.test-artifacts/Build13DeviceInstall.json`, `Build13DeviceLaunch.json` and `Build13InstalledApp.json`. Physical season balance and sustained frame pacing remain user playtest observations.

Engineering: careers store frozen clubs, lineups, a generated 380-fixture schedule and season archives together in one versioned atomic file. Save validation rejects incomplete rounds and invalid identities before publication. UI tests use isolated temporary careers, including a final-match scenario; ordinary launches never seed or change the real career save. Apple references: [atomic writes](https://sosumi.ai/documentation/foundation/nsdata/writingoptions/atomic) and [confirmation dialogs](https://sosumi.ai/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:message:)-2s7pz).

---

# Build 12 Premier League friendly checkpoint

The default launch now opens Premier League club selection. Choose two clubs, select a formation and starting XI for each, and play a three-minute 11v11 friendly. The first playable checkpoint is implemented; career seasons and other competitions are deferred.

- **Club selection:** choose any two of the 20 Premier League clubs. The opponent picker disables the club already on the other side. Search by club name.
- **Starting XI:** try all three formations, replace a player from the squad and swap two starters. Each side retains one goalkeeper and ten outfield players. Tap anywhere on a player row, including its blank middle area.
- **Identity:** read club names in the scoreboard and restart messages. Source shirt numbers and the selected player name follow the actual player. Missing shirt numbers display an en dash. Goalkeepers retain gloves and GK badges.
- **Kits:** try Arsenal versus Liverpool to exercise an away clash kit. Outfield shirts should be distinct and keepers should differ from both clubs. These are simple game kits using source colours.
- **Appearance:** six stable skin palettes and four hair shapes provide variety. Appearances are generated by player ID, not matched to portraits. Reviewed colour choices can later be supplied through the optional appearance override resource.
- **Abilities:** compare players with different overall ratings. Pace differences are bounded to about eight percent around the baseline; control, passing, shooting, defending and goalkeeping also vary. The same per-player modifiers apply under human and AI control. Detailed attributes are arcade estimates. Missing ratings remain explicitly estimated.
- **Match flow:** tap ACTION for the opening kickoff. Play until full time, select Play again, then Choose clubs. Check every restart, keepers, pause/resume and selection among the 22 players. The home club always attacks the top goal; no halves, substitutions or offside are introduced.
- **Offline:** the included 7 September 2026 export contains 20 clubs and 631 players. Existing matches remain frozen during catalogue updates. Failed refreshes leave usable data intact; complete imports are atomically cached, with daily checks and conditional ETags.
- **Practice:** the Training menu opens Solo practice or Pass & defend directly. Existing short-pass, through-ball, keeper, shot-height and backheel controls are retained.

Build 12 signed device compilation and strict signature verification passed. Installation and launch on the connected iPhone succeeded; the installed app query reports version 0.1.0, build 12. Delivery evidence is in `.test-artifacts/Build12DeviceInstall.json`, `Build12DeviceLaunch.json` and `Build12InstalledApp.json`.

All 305 core, catalogue, match, input and rendering tests passed in the final phone run. All eight phone UI checks passed, including three Premier League flows and five retained match/keeper cases. All three Premier League UI flows also passed on iPad. Both devices passed the largest accessibility text-size setup/lineup check. The final result bundles report 313 passing tests on the phone and three on iPad, with zero failures or skipped tests.

Evidence: `.test-artifacts/Build12FinalPhone.xcresult` and `.test-artifacts/Build12Pad.xcresult`. Setup, lineup, full-time and live-pitch screenshots were inspected; club labels, distinct kits, source shirt numbers and varied player palettes are visible. Phone screenshots are in `.test-artifacts/Build12PhoneScreens/` and iPad screenshots in `.test-artifacts/Build12PadAttachments/`. Both simulator runs completed successfully. Physical balance and sustained frame pacing still benefit from user playtesting.

Engineering note: this machine encountered the previously documented SwiftBuild compiler-discovery pipe hang. Validation used the existing invocation-only `CCC_OVERRIDE_OPTIONS` workaround; no project compiler settings changed. An initial new renderer test incorrectly searched from the scene root instead of the player node; corrected node scoping and component-based colour comparisons now pass. A failed initial XI-edit UI check exposed missing hit areas in plain player rows; the full row is now tappable. Initial failed runs stopped during verbose diagnostics; their text logs are retained.

---

# Build 11 keeper and attacking controls playtest

**Build 11 is installed and launched on the connected iPhone.** These are refinements to the three-minute 5v5 match following the user's feedback. Verification for this revision is recorded here; older build records remain below.

- **Keeper catch:** send an opposition ball into the area. The keeper should hold it visibly, remain stable under pressure and wait for your input. Aim/tap to throw; hold to punt farther and add sideways aftertouch.
- **Backpass:** pass back to your keeper and move him as it approaches. He must use his feet, with slower pace and less forgiving dribbling. Opponents can win a foot-controlled ball. His own next touch must not secretly allow handling.
- **Throw-in:** compare a tap and a long hold. Longer holds should throw farther and must remain throws.
- **Through ball:** give a firmer tap into an open forward lane. A reachable runner should be selected and head into that space; a tiny tap should still make a short knock-ahead.
- **Shot power:** near goal, compare a brief hold, the green release band and an overlong red hold. Pace and height should increase; overhit attempts should clear the bar. Try each corner and sideways aftertouch.
- **Backheel:** while facing forward, reverse the stick sharply during a short passing press, close to release. The ball goes behind while the player stays facing forward. Ordinary backward passes and after-release chips should still work normally.
- **Interruptions:** pause or open settings while preparing a distribution or shot. It must cancel the press without an accidental release; resume and make a fresh action.

| Build 11 verification | Status |
| --- | --- |
| Core, keeper, kick, scene and input regressions | All 282 tests passed in `Build11FinalCoreTests.xcresult`, including actual corner goals versus central saves, untouched-stick shot direction, protected catches, legal backpasses, thrown/punted distribution, throw-ins, through balls, chips and backheels. |
| Real-touch phone UI and power-meter rendering | All 13 distinct phone UI cases have passing results across the initial run and focused rerun. Includes keeper foot movement, manual catch/throw/punt and held throw-ins. Shot green-band/overhit and keeper hand/foot/dive render attachments were inspected. |
| Portrait iPad and enlarged-text/Dark Mode checks | All five iPad checks passed: the three keeper/throw cases plus both match-flow cases. All three additional phone checks passed at the largest accessibility text size in Dark Mode: settings, keeper catch/distribution, and full time/Play again. Keeper and full-time screenshots were inspected; labels fit. |
| Signed build, version and physical installation | Final device build and strict signature verification passed. Installed and launched on the connected iPhone 16 Pro Max, iOS 26.6.1, at 01:13:49 on 7 September 2026. The installed-app query confirms version 0.1.0, build 11. |
| Physical feel | User playtest after delivery. |

Evidence: `.test-artifacts/Build11FinalCoreTests.xcresult`, `Build11PhoneUI.xcresult`, `Build11PadUI.xcresult` and `Build11AccessibleUI.xcresult`. The first phone run passed 12 of 13 cases; its full-time check timed out because the synthesized kickoff tap did not register (the captured state still showed kickoff, zero kicks and 0:02). That unchanged case passed in the focused phone run, and had also passed on iPad. No production change was made to obtain the rerun. The exact cause of the isolated missed automation tap was not established; note any similar real-device occurrence. The initial core run contained superseded keeper/shot expectations; those were updated for the requested rules before the final 282-test passing run.

The final signed build log is `.test-artifacts-build11-final-device.log`. Successful delivery records are `.test-artifacts/Build11DeviceInstall.json`, `Build11DeviceLaunch.json` and `Build11InstalledApp.json`. Physical shot balance, backheel gesture difficulty, haptic comfort and sustained frame pacing remain user playtest observations.

# Build 10 five-a-side match playtest

**Build 10 is installed and launched.** Normal phone/iPad match checks, the final signed build and all three additional phone checks at the largest accessibility text size in Dark Mode are verified. This milestone is ready for playtesting. The default is now **5v5 match**: four outfield players and an autonomous goalkeeper per side, with **three minutes of active play**. Blue attacks north for the whole match. The user accepted Build 9’s core gameplay feel on **7 September 2026** and chose this match duration. Keep those control defaults while testing team spacing, saves, restarts and the complete match loop. **Pass & defend** and **Solo practice** remain available under Play mode in settings.

## Build 10 focus

- Complete a match from the opening kickoff through full time, then use **Play again**. The score should identify Blue and Red, the clock should reach zero only after three minutes of active play, and the new match should start with a clean score, clock and team.
- Look for four outfield players in a loose 2–2 shape on each side. One player can press while others cover or offer passes; the whole team should not bunch around the ball. The familiar joystick-directed selection should choose outfield runners only.
- Test both keepers with shots, chips and rebounds. Blue’s keeper wears amber, red’s violet, with gloves and a GK badge. A reachable shot may be caught or parried, a dive should show a committed reach and recovery, and a held ball should be distributed automatically.
- Let the ball leave a touchline and each goal line after touches by either side. Read the awarded throw-in, corner or goal kick. Aim blue’s outfield restarts and use ACTION; opposition and goalkeeper restarts should resume automatically.
- Score and concede. Each goal should count once, and the conceding side should take the next kickoff. Blue keeps attacking north; there is no half-time or change of ends.
- Pause, open help/settings or background the app while watching the clock. Time should remain still during these breaks, goals, restarts and foul sequences. Resume with fresh touches; no held or queued action should leak into the restart.
- Keep checking running tackles, prepared first-time kicks, chips and the visible foul/recovery sequence with ten players. Cards persist through restarts. Play again or New match clears them.

## Build 10 validation record

| Build 10 check | Status |
| --- | --- |
| Combined game, match, keeper, scene, input and rendering checks | All 243 tests passed in the full Xcode run. After a keeper-wait accessibility correction, all six MatchSceneTests passed in a focused run, including one new case: **244 distinct checks have passing results across runs**. |
| Signed iOS build and declared build number | The final corrected app built successfully, passed strict signature verification and declares build number 10. |
| iPhone gameplay and settings UI | All ten distinct phone UI cases have passing results across two runs: eight retained cases in the initial run, followed by both match cases after correcting accessibility grouping. The focused match run reported TEST SUCCEEDED. |
| iPad match UI | Both focused match cases passed in the final run, which reported TEST SUCCEEDED and exit code 0. Stalled post-test diagnostics were stopped only after the tests had finished. Earlier mixed-result evidence is retained below. |
| Enlarged text and Dark Mode | All three focused phone checks passed in Dark Mode at the largest accessibility text size at 00:31:51 on 7 September 2026, with TEST SUCCEEDED and exit code 0. Coverage includes accessible settings, full time/Play again, and restoring defaults/returning to play. |
| Physical installation and launch | Installed and launched successfully on the connected iPhone 16 Pro Max, iOS 26.6.1, with the final launch at 00:33:43–44 on 7 September 2026. The installed-app record confirms version 0.1.0, build 10. |
| Five-a-side feel and performance | Match playtest pending, including keeper balance, spacing, restart flow and sustained frame pacing on the actual phone. |

The full 243-test result is `.test-artifacts/Build10FinalCoreTests.xcresult`. The six passing MatchSceneTests are the unit-test portion of `.test-artifacts/Build10PadMatchUI.xcresult`; that same bundle’s two UI tests failed, so the overall bundle must not be described as passing. One match-scene case was new after the combined run; the other five repeated existing coverage. The initial phone UI results are `.test-artifacts/Build10PhoneUI.xcresult`, with eight passing retained cases and two failing new match cases. The production correction uses an accessibility container that preserves its child elements. Both focused phone match cases subsequently passed in `.test-artifacts/Build10PhoneMatchUI.xcresult`; both iPad match cases passed in `.test-artifacts/Build10PadFinalUI.xcresult`. Thus all ten phone UI cases have passing results across runs; the initial bundle is still a mixed result. Phone and iPad kickoff/full-time screenshots were exported and visually reviewed.

The final signed-device build log is `.test-artifacts-build10-device-delivery.log`; strict code-signature verification and build number 10 were confirmed. Successful install, launch and installed-version records are `.test-artifacts/Build10FinalDeviceInstall.json`, `.test-artifacts/Build10FinalDeviceLaunch.json` and `.test-artifacts/Build10FinalInstalledApp.json`. The originally nominated acceptance phone was the iPhone 17 Pro Max; the actual connected phone used for installation is the iPhone 16 Pro Max. All three enlarged-text/Dark Mode checks passed in `.test-artifacts/Build10AccessibleUI.xcresult`, using Dark appearance and the largest accessibility content size. The passing cases were `AccessibilityLayoutTests.testSettingsRemainAccessibleWithSystemAppearanceAndTextSize`, `MatchUITests.testFullTimeShowsResultAndPlayAgainResetsMatch` and `SandboxUITests.testSettingsRestoreDefaultsAndReturnToPlay`. Screenshot inspection then caught a clipped result-screen button label, shortened to “Settings”. The full-time/Play again case passed again at the same largest text size in `.test-artifacts/Build10FinalResultUI.xcresult`; its screenshot was reviewed and both button labels fit. The phone and iPad test simulators were shut down, with phone appearance/text size restored. No technical verification remains pending for this handoff; physical match balance and sustained performance still need the playtest above.

### Earlier Build 9 evidence and accepted controls

**Build 9 was verified, installed and launched.** All 201 game, scene, input and haptic tests passed, together with its signed device build. It is installed and launched on the connected iPhone 16 Pro Max running iOS 26.6.1. All eight standard phone UI cases have passing results across the initial run and a focused settings rerun. Both additional settings checks passed in Dark Mode at the largest accessibility text size. The user accepted the core gameplay feel on **7 September 2026**, authorising the 5v5 milestone. Sustained performance and individual haptic comfort remain physical-device observations. Touch anywhere on the left side of the pitch and drag: every new touchdown places the joystick centre under your thumb. Passing accepts rougher aim, remembers deliberate direction through release noise and gives more time for a tap before charging. Teammates offer short return lanes for quick pass-and-move play. Kicks and challenge impacts have optional haptics on supported devices.

#### Build 9 control checks

- Lift the left thumb and place it higher, lower or farther inward on the left side. Each touchdown should be neutral, with a new ring at the touch. Drag to move and keep ACTION usable with the other thumb. Lifting should release movement input; returning to the old centre is unnecessary. A captured drag can cross the middle of the screen without becoming an ACTION press.
- Try relaxed short taps just under 0.26 seconds, then compare a longer hold. Full power takes 0.91 seconds total. Roughly aim at a nearby teammate, then lift the joystick thumb first or let it drift slightly towards centre. The intended pass should remain clear. Deliberately choose a different direction while holding ACTION and check that it changes the kick.
- Pass and immediately prepare the receiver’s next pass. Try a one-two with the original passer moving into support. Nearby useful options should be easier to find; opponents must still be able to intercept.
- Feel a light kick, a stronger shot, a running challenge and a slide impact involving your player. A missed slide should stay quiet. A foul impact should coincide with the collision, before the whistle. A queued kick should vibrate only when it actually meets the ball.
- In settings, turn Gameplay haptics off and repeat; play should stay identical without vibration. Re-enabling must not replay old events. Pause or reset with a touch held and check for a clean restart.

#### Build 9 validation record

| Build 9 check | Status |
| --- | --- |
| Gameplay, scene, input and haptic event tests | All 201 Xcode tests passed with zero failures at 23:18:17 on 6 September 2026; Xcode reported TEST SUCCEEDED and exited successfully. |
| Signed iOS build | Development-signed build succeeded, the app declares build number 9, and strict signature verification passed. |
| iPhone UI | iPhone 17 Pro Max, iOS 26.5: all eight standard UI cases have passing results across two runs. The initial run passed seven cases, including floating higher-left touches; one settings test failed because it tapped the labelled row instead of the switch. After correcting that test’s tap target, the focused settings rerun passed at 23:24:37 on 6 September 2026, with TEST SUCCEEDED and exit code 0. The app was unchanged for the rerun. |
| Large-text and Dark Mode settings | Both focused iPhone settings checks passed in Dark Mode at the largest accessibility text size at 23:28:21 on 6 September 2026, with TEST SUCCEEDED and exit code 0. The haptics toggle was verified off and on; native controls, wrapping, scrolling and Done were visually inspected. |
| iPad UI | No new Build 9 run recorded. Build 5’s Dark Mode and largest accessibility text-size run remains the earlier baseline below. |
| Physical installation and launch | Installed and launched successfully on the connected iPhone 16 Pro Max, iOS 26.6.1, at 23:18:54 on 6 September 2026. The installed-app query confirms build number 9. |
| Physical feel and performance | Core feel accepted by the user on 7 September 2026. No sustained 60 fps measurement or separate haptic-strength assessment is recorded. |

Build 9’s combined result bundle is `.test-artifacts/Build9FinalCoreTests.xcresult`, with log `.test-artifacts-build9-final-core.log`. The signed-device build log is `.test-artifacts-build9-device.log`. Successful install, launch and installed-version records are `.test-artifacts/Build9DeviceInstall.json`, `.test-artifacts/Build9DeviceLaunch.json` and `.test-artifacts/Build9InstalledApp.json`. The initial seven passing phone UI cases and settings-test failure are recorded in `.test-artifacts/Build9PhoneUI.xcresult` and `.test-artifacts-build9-phone-ui.log`. The passing settings rerun is `.test-artifacts/Build9SettingsUI.xcresult`, with log `.test-artifacts-build9-settings-ui.log`. Together these cover all eight standard UI cases; they are not a single all-green result bundle. Inspected screenshots are `.test-artifacts/Build9PhoneAttachments/581E7241-F3A8-4C71-A287-3C56C11C5BC2.png` for the floating-control idle cue, and `.test-artifacts/Build9GameplayAttachments/BE56BB2F-D253-4F48-BAF2-802C6F2714FA.png` for receiver guidance and portrait readability. The final two passing enlarged-text/Dark Mode settings checks are in `.test-artifacts/Build9FinalAccessibleUI.xcresult`, with log `.test-artifacts-build9-final-accessible-ui.log`. The earlier `.test-artifacts/Build9AccessibleUI.xcresult` run exposed a test assumption that the first slider was already onscreen; the test was corrected to scroll there before calculating its gesture. No app change was needed. The inspected enlarged-text haptics screenshot is `.test-artifacts/Build9AccessibleAttachments/083D1622-6790-41EC-A91E-61FDAD2A5F27.png`; the normal settings screenshot is `.test-artifacts/Build9SettingsAttachments/2E370F84-A9E0-430D-85E8-BB2BD653D911.png`.

Technical verification note: haptic event checks verify when feedback is requested through [Apple’s native impact API](https://sosumi.ai/documentation/uikit/uiimpactfeedbackgenerator/impactoccurred(intensity:)). The actual pulse strength and comfort need the physical phone; simulator results do not establish tactile feel.

### Earlier Build 8 evidence

**Build 8 passed validation and was installed.** All 165 unit and scene tests and seven phone UI tests passed, together with its signed device build. It is installed on the connected iPhone 16 Pro Max running iOS 26.6.1, with the installed build number verified. Automatic launch was blocked by the locked phone; unlock it and open Top Scores Soccer. Point the joystick toward the run you want when off the ball. Selection now quickly favours a nearby blue player whose movement can meet the ball or block the carrier’s path; they need not be the closest player. No ACTION tap is required. Running tackles, held slides, prepared kicks, intended-receiver movement and stationary free-kick aiming remain. **Pass & defend** starts with three blue players against three red players. **Solo practice** remains available for focused movement, kicking and rescue experiments. Use the defaults for one complete session before changing values. The originally nominated acceptance device was the iPhone 17 Pro Max; the actual connected phone is the iPhone 16 Pro Max.


| Build 8 check | Status |
| --- | --- |
| Directional selection | Regression checks passed for useful joystick-directed runs, moving-ball interception, carrier blocking, nearby candidate bounds and stable handoffs, including 12 independent selection scenarios. |
| Retained controls | Regression checks passed for pass receivers, kick gestures, queued kicks, slides, rear pressure and optional tap selection, including 11 scene-input checks. |
| Combined unit and scene checks | All 165 Xcode tests passed with zero failures at 22:59:12 on 6 September 2026; Xcode reported TEST SUCCEEDED. |
| Device build and signing | Development-signed iOS build succeeded, the app declares build number 8, and strict signature verification passed. |
| iPhone UI | iPhone 17 Pro Max, iOS 26.5: all seven tests passed with zero failures at 23:01:43 on 6 September 2026; Xcode reported TEST SUCCEEDED and exited successfully. The gameplay screenshot was inspected for portrait layout, the selection marker, steering guidance and SLIDE/HOLD feedback. |
| iPad UI | No new Build 8 run recorded. Build 5’s Dark Mode and largest accessibility text-size results remain the earlier baseline below. |
| Physical installation | Installed successfully on the connected iPhone 16 Pro Max, iOS 26.6.1. The installed-app query verified build number 8 at 23:00 on 6 September 2026. |
| Physical launch | Automatic launch was denied because the phone was locked. Unlock the phone and open Top Scores Soccer; successful launch is not yet verified for Build 8. |
| Physical feel and performance | User playtest pending, including sustained 60 fps on the phone. |

Build 8’s combined result bundle is `.test-artifacts/Build8FinalCoreTests.xcresult`, with log `.test-artifacts-build8-final-core.log`. The signed-device build log is `.test-artifacts-build8-device.log`. Successful install and installed-version records are `.test-artifacts/Build8DeviceInstall.json` and `.test-artifacts/Build8InstalledApp.json`; `.test-artifacts/Build8DeviceLaunch.json` records the locked-phone launch failure. Passing phone UI results are in `.test-artifacts/Build8PhoneUI.xcresult`, with log `.test-artifacts-build8-phone-ui.log`. The inspected gameplay screenshot is `.test-artifacts/Build8PhoneAttachments/5C2731C3-3C6C-47DE-AD82-76FFD160CB1F.png`.

### Earlier Build 7 evidence

These checks describe the running-tackle revision before automatic directional selection.

| Build 7 check | Status |
| --- | --- |
| Running tackles | Regression checks passed for front/side contact, sustained rear pressure, interrupted pressure and protected possession. Includes a natural moving chase against the carrier AI, touchline contact order and protection against an immediate AI return poke. |
| Retained controls | Regression checks passed for short-tap selection and prepared kicks, held slides, receiver movement and free-kick aiming. |
| Combined unit and scene checks | All 146 Xcode tests passed with zero failures at 22:33:20 on 6 September 2026; Xcode reported TEST SUCCEEDED and exited successfully. |
| Device build and signing | Development-signed generic iOS build succeeded. The app declares build number 7 and passed strict signature verification. |
| iPhone UI | iPhone 17 Pro Max, iOS 26.5: all seven tests passed with zero failures at 22:36:15 on 6 September 2026; Xcode reported TEST SUCCEEDED and exited successfully. Includes real off-ball short-tap selection without a standing tackle, and the held slide. |
| iPad UI | Not rerun for Build 7. Build 5’s Dark Mode and largest accessibility text-size run remains the recorded baseline; its results are preserved below. |
| Physical installation | Installed and launched successfully on the connected iPhone 16 Pro Max, iOS 26.6.1. The installed-app query confirms `uk.co.mwagstaff.TopScoresSoccer`, build number 7. |
| Physical feel and performance | User playtest pending, including sustained 60 fps on the phone. |

Build 7’s combined result bundle is `.test-artifacts/Build7CompleteCoreTests.xcresult`, with log `.test-artifacts-build7-complete-core.log`. The signed-device build log is `.test-artifacts-build7-device.log`. Successful install, launch and installed-version records are `.test-artifacts/Build7DeviceInstall.json`, `.test-artifacts/Build7DeviceLaunch.json` and `.test-artifacts/Build7InstalledApp.json`. Passing phone UI results are in `.test-artifacts/Build7PhoneUI.xcresult`, with log `.test-artifacts-build7-phone-ui.log`. The inspected gameplay screenshot is `.test-artifacts/Build7PhoneAttachments/0AB50D3B-F9FE-4914-9CAB-639DAB184072.png`; the running-tackle guidance and SLIDE/HOLD button fit the portrait layout.

### Earlier Build 6 evidence

These checks describe the receiver-control and free-kick-aiming revision before the new running tackles.

| Build 6 check | Evidence |
| --- | --- |
| Receiver control | Regression checks passed for movement before reception, stable intended selection, prepared onward passes, chip input, manual override, interception, expiry and eligible-player filtering. |
| Free-kick aiming | Four independent tests passed for directional facing, frozen set-piece positions, remembered neutral aim, charging and cancellation, including in the combined suite. |
| Combined unit and scene checks | All 131 tests passed with zero failures; Xcode reported TEST SUCCEEDED. |
| Device build | A regular Xcode Product → Build (⌘B) succeeded at 18:33 on 6 September 2026 without command-line overrides. The normal Xcode build product declares build number 6 and passed strict signature verification. |
| iPhone UI | iPhone 17 Pro Max, iOS 26.5: all 7 UI tests passed with zero failures; Xcode reported TEST SUCCEEDED and exited successfully at 18:36:17. The gameplay screenshot was inspected. |
| Physical installation | Not verified for Build 6; the nominated phone was unreachable during the Run attempt. |
| Physical feel and performance | User playtest pending, including sustained 60 fps on the phone. |

The combined result bundle is `.test-artifacts/Build6CompleteCoreTests.xcresult`, with log `.test-artifacts-build6-complete-core.log`. Phone UI results are in `.test-artifacts/Build6PhoneUI.xcresult`, with log `.test-artifacts-build6-phone-ui.log`; the inspected gameplay attachment is `.test-artifacts/Build6PhoneAttachments/E2188464-487D-45CC-B1D2-AD474210CA39.png`. Build 5's iPad evidence remains recorded separately below; it is not a new iPad UI run for Build 6.

Engineering note: command-line validation initially hung during compiler discovery, consistent with the stderr/stdout pipe deadlock described in [Swift Build PR #1315](https://github.com/swiftlang/swift-build/pull/1315). A temporary invocation-only `CCC_OVERRIDE_OPTIONS='# x-v'` suppressed verbose discovery output while preserving compiler selection and macro output. The normal Xcode GUI build subsequently succeeded without this override; no project setting or installation step requires it.

### Earlier Build 5 evidence

These results describe the preceding feel revision before the receiver-control and free-kick-aiming fixes.

| Build 5 check | Evidence |
| --- | --- |
| Supported platform | iOS/iPadOS 18+, iPhone and iPad, portrait only. |
| Device build | Development-signed generic iOS build succeeded, build number 5; strict signature verification passed. |
| Simulation, scene and rendering | All 118 Xcode unit tests passed, including 67 simulation tests, 9 independent kick/receiving scenarios, 9 gameplay-feel cases, 6 scene-input tests, 2 whistle-scene tests and 3 renderer checks. |
| iPhone UI | iPhone 17 Pro Max, iOS 26.5: all 7 UI tests passed; settings screenshot inspected. |
| iPad UI | iPad Pro 11-inch (M5), iPadOS 26.5: all 7 UI tests passed in Dark Mode at the largest accessibility text size; settings screenshots inspected. |
| Foul presentation | Both actual iOS render grids were inspected for the longer impact/fall/grounded/get-up sequence. |
| Physical feel and performance | User playtest pending, including sustained 60 fps on the phone. |

Build 5's final unit bundle is `.test-artifacts/Build5CompleteCoreTests.xcresult`, with render attachments in `.test-artifacts/Build5RenderAttachments`. Its UI results are in `.test-artifacts/Build5PhoneUI.xcresult` and `.test-artifacts/Build5PadUI.xcresult`; phone gameplay/settings and iPad settings screenshots were inspected. Its signed-device build log is `.test-artifacts-build5-device.log`. Build and installation instructions are in the [README](../README.md). Record each revision's device findings separately from earlier automated evidence.

### Earlier Build 4 evidence

These checks describe the previous collision, switching and pickup revision.

| Build 4 check | Evidence |
| --- | --- |
| Supported platform | iOS/iPadOS 18+, iPhone and iPad, portrait only. |
| Device build | Final development-signed generic iOS build succeeded in Xcode 26.6, build number 4. Strict signature verification passed; the built Info.plist declares portrait only for iPhone and iPad. |
| Simulation, scene and rendering | All 95 Xcode unit tests passed, including the new contact/fall/discipline sequence, cancellation/reset and fresh free-kick input, deliberate switching, slow/fast/airborne pickup distinctions, whistle delivery and preserved mechanics. |
| iPhone UI | iPhone 17 Pro Max, iOS 26.5: all 7 UI tests passed for real touch input, portrait rotation, practice selection, reset/pause and settings. |
| iPad UI | iPad Pro 11-inch (M5), iPadOS 26.5: all 7 UI tests passed in Dark Mode at the largest accessibility text size. |
| Final settings check | The settings regression passed again after improving native button contrast; the final screenshot was inspected. |
| Fall presentation | Actual iOS offscreen render snapshots passed and were inspected for the sliding collision/fall presentation. |

Build 4 evidence is in `.test-artifacts/Build4CompleteCoreTests.xcresult`, `.test-artifacts/Build4PhoneUI.xcresult`, `.test-artifacts/Build4PadUI.xcresult` and `.test-artifacts/Build4FinalSettings.xcresult`; its final signed rebuild log is `.test-artifacts-build4-final-device.log`. The bundled whistle is original, generated by `Scripts/generate_whistle.py`, and can be disabled under **Referee whistle**. Silent Mode is respected.

### Earlier Build 3 evidence

These results describe the previous mechanics delivery, before the Build 4 feel changes.

| Current delivery | Evidence |
| --- | --- |
| Milestone 1 | Accepted by the user; earlier technical evidence is recorded below. |
| Build 2 review | The user reported that the portrait drill was looking good and requested the current mechanics refinements. |
| Supported platform | iOS/iPadOS 18+, iPhone and iPad, portrait only. |
| Build 3 device build | Final development-signed generic iOS build succeeded in Xcode 26.6, bundled build number 3. Strict signature verification passed; the built Info.plist declares portrait only for both iPhone and iPad. |
| Build 3 simulation, scene and camera | All 79 Xcode unit tests passed. Coverage includes preserved movement/kicking, hold timing, chip flight and contact height, standing/slide/passive tackles, foul and card consequences, free-kick/reset lifecycle, nearest eligible selection, queued-contact/expiry ordering and portrait camera behavior. |
| Extended simulation | 100,000 fixed steps passed: 50,000 in Solo and 50,000 in Pass & defend, about 13 minutes 53 seconds of simulated play per mode. Mixed passes, holds, slides, chips and interruptions retained finite state, bounded players and eligible selection. The exercise run included 26 fouls and 40 goals. |
| Build 3 iPhone UI | iPhone 17 Pro Max, iOS 26.5: all 7 UI tests passed, including real-touch off-ball tap versus held slide, preserved pass/shot input, reset, portrait rotation, exercise selection and settings. Four focused gameplay checks passed again after the final core fixes. Default drill and tuning screenshots inspected. |
| Build 3 iPad UI | iPad Pro 11-inch (M5), iPadOS 26.5: all 7 UI tests passed in Dark Mode at the largest accessibility text size. Portrait rotation and enlarged native settings screenshots inspected; controls and settings remain usable. |

The final 79-test unit result bundle is `.test-artifacts/RevisionFinalCoreTests.xcresult`. Build 3 UI results are in `.test-artifacts/RevisionPhoneUI.xcresult` and `.test-artifacts/RevisionPadUI.xcresult`, with final gameplay rechecks in `.test-artifacts/RevisionFinalPhoneChecks.xcresult`. Extended-simulation output is in `.test-artifacts/RevisionSoak/results.txt`; the final signed-device rebuild log is `.test-artifacts-revision-final-device.log`.

### Earlier Build 2 evidence

These results describe the previous portrait drill, before the Build 3 mechanics changes.

| Check | Recorded evidence |
| --- | --- |
| Device build | Xcode 26.6: development-signed generic iOS build succeeded; strict signature verification passed. Both iPhone and iPad declared portrait only. |
| Simulation and camera | 38 tests passed: 20 original mechanics tests, 15 passing/defending tests and 3 portrait camera tests. Includes 36,000 fixed steps (10 simulated minutes) of mixed play with finite state, legal bounds and continued restarts. |
| iPhone simulator | iPhone 17 Pro Max, iOS 26.5: all 6 UI checks passed, covering real joystick/pass/shot input, portrait lock through both landscape rotations, six-player drill, mode selection, settings and pause/reset. |
| iPad simulator | iPad Pro 11-inch (M5), iPadOS 26.5: gameplay, mode selection and settings checks passed in Dark Mode at the largest accessibility text size. All six UI cases passed across the initial run and focused rerun; the final three layout/settings checks passed after the accessibility layout adjustment. |

### Earlier Milestone 1 evidence

These results describe the accepted solo delivery before the portrait/drill changes; they do not establish validation of the new build.

| Check | Recorded evidence from 6 September 2026 |
| --- | --- |
| Build toolchain | Xcode 26.6, build 17F113. |
| Device build | Development-signed generic iOS build succeeded and strict signature verification passed. |
| Plain Swift simulation | 20 tests passed for movement, independent dribbling, recovery, tap/hold boundaries, cancellation, curve/decay, goals/posts, resets and fixed simulation steps. |
| iPhone simulator | iPhone 17 Pro Max, iOS 26.5: all 25 tests passed, comprising 20 simulation and 5 UI checks. |
| iPad simulator | iPad Pro 11-inch (M5), iPadOS 26.5: all 24 simulation/gameplay UI checks passed; the then-landscape layout was inspected in Simulator. |
| Dark Mode and enlarged text | Separate iPad settings check passed at the largest accessibility text size in Dark Mode, including slider access, Done and return to gameplay; screenshot inspected. |

Build 2 local evidence is in `.test-artifacts/PortraitCoreTests.xcresult`, `.test-artifacts/PortraitUITests.xcresult`, `.test-artifacts/PortraitPadUITests.xcresult` and `.test-artifacts/PortraitPadFinalChecks.xcresult`. The first iPad rotation check sampled an unfinished layout transition; the revised check uses a stable, complete hierarchy snapshot and retains strict bounds assertions. Phone/iPad gameplay and settings screenshots were inspected.

The earlier local result bundles are `.test-artifacts/iPhoneFinalTests.xcresult`, `.test-artifacts/iPadTests.xcresult` and `.test-artifacts/LargeTextDarkModeFinal.xcresult`. Generated validation artifacts are excluded from source control.

## Pass & defend checklist

Select **Pass & defend** in settings for this retained three-a-side drill. Blue attacks the north goal; red attacks south. This mode deliberately has empty goals and no clock. Watch the selected-player marker as you move the joystick off the ball: the game should quickly choose a nearby runner who can meet the ball or block the carrier in that direction. The closest player is not always the best choice, and no ACTION tap is needed. An incoming friendly/free ball offers a receiving action: press to select the receiver, then release a prepared pass or shot. Outside that context, an optional short tap uses the same directional choice, consuming the tap if selection changes. If the preferred runner is already selected, a nearby loose ball can offer a queued rescue. A short tap does not attempt a standing tackle.

- Run toward a blue teammate, aim roughly in their direction and tap-release ACTION. Compare a stationary receiver with one moving into space, including close return options, longer passes and an aim about 60–70° away from the receiver. Assistance should find a teammate within its cone, lead their movement slightly and send the ball far enough to arrive.
- Immediately after an assisted pass, move the joystick sideways without tapping ACTION again. The intended receiver should move while the ball is still travelling, and the selection marker should stay with them instead of jumping back to the passer. Compare an untargeted knock-ahead, which should leave the kicker selected.
- Aim away from teammates and tap into space. The untargeted knock-ahead should stay close enough to chase, with more pace when already running. Compare it with holding for a powerful long kick upfield or sideways.
- Hold-release roughly toward the north goal from both midfield and closer range. Within 50° of the goal direction, assistance should bring the kick toward goal across the pitch; outside that directional opportunity, the charged kick should preserve your requested direction. Curve and chips should still work.
- Send a pass toward another blue player. Before it arrives, press ACTION to select the receiver, aim the next pass away from the incoming direction and release a tap. Check that the first-time kick happens on contact in the captured outgoing direction. Resume movement while waiting; it must not redirect the queued kick or accidentally chip it.
- Repeat with a hold and release before arrival. This should prepare a charged shot or long kick, with no slide. Let another prepared kick miss or expire, then pause/reset during one; neither should fire later from a different player.
- Pass across a red defender. The ball should remain interceptable, and the selected blue defender should change without flickering between players.
- Compare running with the ball against chasing it: off-ball running should be slightly faster while the accepted dribbling pace remains familiar.
- Run onto a slow loose ball from several angles and make ordinary turns after collecting it. Pickup and close control should feel more forgiving. Repeat with a hard shot or an airborne chip; mere proximity should not capture those balls.
- Without touching ACTION, point the joystick so a nearby blue player can run toward a loose ball. Compare two players on opposite sides of it: the game should prefer a useful run in your chosen direction, even if the other player is a little closer. Reverse the stick and check that a clearly better nearby runner is selected promptly.
- Chase a moving ball, then defend against a carrier running across the pitch. Selection should account for where the ball or carrier is going, choosing a nearby player who can meet or block that path. It should not jump to a distant player merely because their facing happens to match.
- Hold the same joystick direction through close candidate ties, then briefly wiggle it and return to neutral. The marker should remain understandable, without rapidly alternating between players. Compare a deliberate large direction change, which should respond quickly.
- After automatic selection chooses a useful runner who is not the closest player, briefly tap ACTION. That optional tap should respect your joystick direction rather than jumping back to the closest player. A tap that does change selection must not also kick, tackle or queue.
- Lose possession, approach the carrier from the front or side and run toward the ball without ACTION. Close approaches should win the ball more readily than before. Compare arriving within reach with running past too far away, then stop beside the carrier: merely standing nearby should not win possession.
- Run toward the opponent and hold ACTION briefly. At **0.22 seconds**, the player should commit to a slide in the running direction. Compare a successful ball-first challenge, a complete miss and a player-first late challenge. A miss leaves recovery. On a late collision, look for impact and a readable tumble/fall during the **1.2 seconds** before the whistle/card. The next **2.4 seconds** should give time to see the grounded pause and get-up before free-kick placement, without a sudden jump straight from impact to restart.
- Approach from behind and keep running toward the same carrier. Look for **KEEP PRESSING** and stay close for about **half a second** before winning the ball. Brief rear contact should not grant an instant steal. Break away or change targets partway through, then try again; the earlier pressure should not carry over. Compare closing from the side instead.
- While already controlling the preferred runner beside an opponent, tap ACTION briefly. It should not add a standing poke or a slide. Hold in the same situation to confirm that the deliberate slide still works.
- Observe foul feedback, yellow cards and any dismissal. Take blue's awarded free kicks with ACTION; red should restart automatically after a brief pause. Blue and red must both obey disciplinary consequences. Two yellows dismiss a player, direct reds should be rare, and a sent-off player should not reappear after a goal or ordinary out-of-play restart. Losing every eligible player stops the drill until reset. The reset arrow starts a fresh drill and clears discipline.
- At blue's free kick, point the joystick left, right, down and diagonally. The taker should face that direction while every player and the ball stay put. Return the stick to neutral, then tap or charge-release: the remembered facing should guide the kick, with usual assistance. Change aim while charging, wait at full power, and pause before release; only a fresh valid release should strike the ball.
- Chase a loose ball near a touchline. Tap ACTION before reaching it, keeping within the **1-second** opportunity. A first-time kick should execute on actual reachable contact, and a threatened outward ball should be sent back into play. A late arrival must still concede out-of-play.
- Try the same rescue with a **0.22-second hold**. The slide can reach and clear the ball before it crosses the line; holding should not also fire an unrelated shot when the button lifts.
- Follow the marker after a pass, turnover and slide, and while building close rear pressure. Incoming receivers, committed actions and sustained rear pressure should keep their player until that opportunity ends. Turn away during rear pressure and check that selection can respond to the new run. Ordinary off-ball movement should then resume choosing useful nearby runners. Existing stick input should feel predictable after a handoff, without teleporting players.
- Switch to **Solo practice**, make a tap kick and curved shot, then try pulling the stick back against the original kick within **0.24 seconds**. Compare successful chips, late pull-backs and ordinary lateral curve. The ball should visibly lift above its shadow, pass over feet while high enough and become reachable again when it drops.
- Pause or reset during a charge, queued pass or slide, then resume with fresh touches. Old actions must not leak into resumed play. A press that began as a pass/shot must not become a surprise tackle if control is lost.
- Pause during a victim's fall, then resume. The contact sequence should continue from where it stopped, followed by one whistle and any card. Reset during the fall instead: it should start a fresh drill without later announcing the discarded incident.
- Toggle **Referee whistle** in tuning and try Silent Mode. The optional sound should follow the visible fall, once per foul, while the on-screen sequence remains understandable with audio muted.
- Turn the phone sideways and back. The game should stay in portrait, with both thumb controls and the top bar usable. Repeat the settings check in Dark Mode and with enlarged text.

Note whether the opponents provide useful pressure, teammates offer readable passing options, and the ball stays loose without making possession frustrating. Empty goals, simple AI and quick ordinary restarts remain deliberate limits of this drill.

## Ten minutes of match play on the phone

Start in **5v5 match** with defaults and complete at least two matches. Three minutes counts active play, so restarts and breaks make each session longer in real time. Use the first match to judge spacing, passing options, keeper saves and distribution. In the next, deliberately test goals, last-touch restarts, a foul, pause/help/settings and full time. Check that Play again restores a full side, zero score and 3:00. Enable **Show gameplay overlay and vectors** for part of the session and note repeated stalls or growing heat with ten players. Simulator checks do not establish sustained device performance.

## Retained ten-minute Solo mechanics check

For the focused mechanics checks below, select **Solo practice**. Open the sliders and enable **Show gameplay overlay and vectors** for the performance portion. The overlay exposes gameplay state alongside FPS. Close the panel to resume; help and tuning pause gameplay.

| Time | Exercise | Look for |
| --- | --- | --- |
| 0–2 min | Run gently, then at full stick deflection. Make small turns, diagonal turns and a full reversal. Release the stick. Lose and recover the ball. | Responsive movement with brief reversal momentum; the ball visibly rolls between touches. Sharp turns may expose it, and recovery should happen without snapping it to your feet. |
| 2–4 min | Tap ACTION while standing and running. Compare short knock-aheads with medium/full holds. Try a roughly aimed goal attempt and a sideways clearance, then release with a neutral stick. Hold through a sharp turn that loses the ball. | Chaseable untargeted taps, goal assistance within its directional opportunity, increasing charged power and no automatic kick at full charge. Losing control cancels an ordinary possession press; recovery alone must not fire it. |
| 4–6 min | Shoot up, down and diagonally. Compare neutral input, lateral curve and a quick pull-back after release. Try chipping a pass too. | Curve remains bounded; only a timely reverse input chips. Height and shadow make flight readable, and ordinary foot contacts cannot steal a high ball. |
| 6–8 min | Send the ball toward a boundary and chase it, comparing an early queued tap with a committed slide and a deliberately late attempt. Score, miss wide and hit a post. | Contact before the line can save the ball; contact after it cannot. Each goal counts once, posts rebound, and the camera keeps hard shots visible. |
| 8–9 min | Pause during a charge, open tuning, briefly background the app, then return. Turn the device sideways and back while the app stays in portrait. | No accidental shot or stuck stick. Both thumbs and top-bar controls remain comfortable around the screen edges. |
| 9–10 min | Mix running, tap kicks, charged shots and resets with the overlay enabled. | Approximately 60 fps with consistent motion. Record repeated dips, hitches or growing heat together with the action that caused them. |

An overlay number is only a first indication of performance. If motion repeatedly stalls, report when it happens so the scene can be profiled with Instruments. Simulator results cannot substitute for this physical session.

After the focused checks, spend a further few minutes mixing passes, turnovers, running tackles and slides in **Pass & defend**. Check that free kicks resume cleanly and selection excludes dismissed players. Watch for repeated stalls as selection and AI change; record the action that caused each one.

## Tune one thing at a time

These are the implemented defaults and the ranges available under **Tune gameplay**. The ranges are starting points for experiments; they have not yet been validated as the best settings on your phone. Change one slider, play for a minute, and note whether the result improves the feel.

| Setting in the app | Default | Slider range | Increasing it does this |
| --- | ---: | ---: | --- |
| Running speed | 10.5 m/s | 6–15 m/s | Raises full-stick dribbling speed; off-ball speed also applies its separate multiplier. |
| Off-ball speed boost | 1.12× | 1.00–1.30× | Increases the running advantage while chasing or supporting without possession. |
| Acceleration | 42 m/s² | 20–70 m/s² | Reaches requested speed sooner and reverses velocity faster. |
| Stopping strength | 30 m/s² | 12–55 m/s² | Stops sooner on neutral input and shortens aftertouch coasting. |
| Turning speed | 12 rad/s | 5–22 rad/s | Turns the player's facing direction faster. |
| Control reach | 2.4 m | 1.3–3.0 m | Makes slow loose balls easier to collect nearby; escaping, hard-shot and high-ball restrictions remain. |
| Rolling resistance | 5 m/s² | 2–9 m/s² | Slows rolling balls faster and shortens kick travel. |
| Time between touches | 0.075 s | 0.05–0.24 s | Leaves longer free-rolling gaps between dribble nudges. |
| Dribble reach | 2.5 m | 1.5–2.7 m | Allows foot touches from farther away. |
| Pass speed | 21 m/s | 14–28 m/s | Raises the minimum speed of assisted teammate passes; distance can require more pace. Untargeted taps have separate short-kick tuning. |
| Pass assistance angle | 75° | 15–85° | Widens the cone to each side of your aim in which a teammate can be selected. |
| Pass lead | 0.85× | 0–1.20× | Aims farther ahead along the receiver’s predicted movement. |
| AI running speed | 0.82× | 0.45–1.00× | Raises computer-controlled players’ speed as a fraction of the human maximum; affects both teammates and opponents. |
| Running tackle reach | 1.9 m | 1.3–2.3 m | Makes front/side running challenges more forgiving; deliberate approach and separate rear-pressure rules remain. |
| Hold to slide | 0.22 s | 0.15–0.40 s | Requires a longer deliberate off-ball press before committing to a slide. |
| Slide recovery | 1.00 s | 0.50–1.50 s | Leaves the sliding player committed for longer after the slide ends. |
| Queued kick window | 1.00 s | 0.25–1.50 s | Gives the chosen player longer to reach the ball for a captured first-time pass or shot. |
| Tap / hold threshold | 0.26 s | 0.12–0.30 s | Gives more time to release a pass before it becomes a shot. |
| Time to full power | 0.65 s | 0.35–1.00 s | Takes longer to reach full power **after** the hold threshold. |
| Maximum shot speed | 47 m/s | 32–62 m/s | Raises fully charged shot speed. |
| Curve window | 0.65 s | 0.40–1.00 s | Allows longer aftertouch and longer player coasting. |
| Curve strength | 2.4 rad/s | 0.6–4.0 rad/s | Bends the ball faster before decay and the angle cap apply. |
| Curve fade | 2.0 | 1–4 | Fades the curve response sooner; this is a unitless exponent. |
| Maximum bend | 25° | 10–40° | Allows a larger heading change from the original shot direction. |
| Pull-back window | 0.24 s | 0.12–0.40 s | Gives more time after a kick to reverse the stick and trigger a chip. |
| Chip lift | 8 m/s | 5–12 m/s | Sends chips higher and keeps them airborne longer. |
| Camera response | 9 /s | 4–16 /s | Makes camera tracking catch up faster. |
| Camera look ahead | 0.28 s | 0–0.55 s | Looks farther along the ball’s current velocity. |
| Joystick dead zone | 0.12 | 0.04–0.25 | Requires more thumb displacement before movement; values are fractions of the joystick radius. |

The full reference is [GameplayTuning.swift](../TopScoresSoccer/Core/GameplayTuning.swift). Additional defaults there include a **25 m/s** minimum charged kick, **3.5 m** control release distance, **18 m/s** ordinary acquisition relative-speed limit, **3.4 m** kick reach, **0.28 s** kick reacquisition delay and **1.1 s** ordinary restart delay. Those values are kept in source rather than exposed as sliders. Running challenges use their separate **Running tackle reach** setting; rear challenges need about **0.5 s** of sustained close pressure on the same carrier.

The ball uses ground-plane distances in metres plus height for chips. Curve changes direction without adding horizontal speed; airborne movement has its own vertical motion before rolling resumes. Passes have the short chip opportunity but no sideways curve. In team modes, deliberate release aim guides receiver selection and pass leading within the 75° half-angle cone; small release movements retain the last deliberate aim. Solo practice tap kicks follow that same aim. The 0.26-second pass/shot threshold is separate from the 0.22-second defensive slide hold. Charged kicks aim toward the opposition goal when within **50°** of its direction, with a **140 m** source range covering the whole pitch; other directions remain powerful long kicks. Untargeted taps start at **9 m/s**, or forward running speed plus **3 m/s** when greater. Assisted passes aim for a **12 m/s** arrival speed, with distance and ground friction included in their starting pace.

The four **Passing and defending** sliders appear in both 5v5 match and Pass & defend. Selection now responds automatically to the joystick, so the former Automatic switch delay slider has been removed. First test with defaults; no selection tap should be necessary. If assistance picks a receiver too far from your intended line, reduce **Pass assistance angle**; if passes trail moving teammates, try a little more **Pass lead**. Lower **AI running speed** to ease the pace, remembering that it also slows your supporting teammates. Increase **Running tackle reach** if front and side challenges still feel too exacting. **Slide recovery** changes the cost of committing to a slide. The slide, queue and chip sliders also appear in Solo practice.

Other exercise defaults remain in source: **42 m** assisted-pass range, **34 m/s** receiving relative-speed limit and the computer-controlled **0.10 s** standing poke with **1.3 m** reach; that poke is no longer a human button action. Automatic selection considers the joystick-directed run toward a moving ball or carrier. Clear improvements can switch immediately; close choices use brief confirmation and a switching margin. Prediction and the candidate area are bounded, while neutral input keeps a useful current player. There is no selection slider. Outside an incoming-ball receiving action, an optional off-ball tap uses the same selection logic. These are starting values for playtesting, not promises of a particular football feel.

Retained defaults include a **1.12×** off-ball speed multiplier, **0.22 s** defensive slide hold threshold, **0.30 s** slide commitment at **16 m/s**, **1.0 s** slide recovery, **1.3 m** actual queued-kick reach, and a **0.24 s** chip gesture window. Prepared kicks now last **1 second** within an initial **14 m** arming distance and require a predicted reachable arrival. The receiving press itself has a bounded opportunity; a missed arrival does not arm an indefinite action. Chip lift begins at **8 m/s**, gravity is **18 m/s²**, and feet can interact only below **0.65 m**. The retained foul sequence plays impact/fall for **1.2 s** before announcing a foul or applying its card. Foul/card feedback, the grounded pause and recovery then take **2.4 s** before placing the free kick, with opponents moved at least **6 m** from the spot.

Discipline defaults are in [TackleRules.swift](../TopScoresSoccer/Core/TackleRules.swift). Clean ball-first contact never draws a random foul. For body-first fouls, yellow chances start at **4%** for computer-controlled standing tackles and **20%** for slides, rising for contact from behind or at high relative speed. Only fast slides from behind have the separate **4%** direct-red chance. Cards use deterministic random draws so a reported sequence can be reproduced.

Choose **Restore default tuning** to undo an experiment. Tuning changes are not saved across app launches. The match duration is fixed at three minutes of active play in the normal app, with no duration slider. In 5v5, **Start a new match**, the reset arrow and **Play again** clear score, time, disciplinary records and queued/committed actions. In the practice modes, **Reset practice** keeps the goal tally; **Clear goal tally** clears it too. Goals and ordinary out-of-play restarts retain disciplinary records.

## Feedback to send back

Record the phone model, iOS version, approximate session length and whether you used defaults. For Build 11, focus on keeper catches versus backpasses, manual throws and punts, variable throw-ins, through balls, the shot-power release window and reverse-swipe backheels. Check that stronger corner shots reward placement while keepers still save central attempts. Keep checking team spacing, automatic selection, restarts, the stopped clock during breaks, full time and Play again. Include which Play mode you used. For a problem, include the action immediately before it, how often it happens and a short screen recording if convenient.

Use a row for each tuning experiment:

| Device / OS | Setting | Before → after | Observation | Keep or revert? |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

Current limits: five-a-side with simple 2–2 outfield formations, automatic keeper positioning and saves, manual blue keeper possession, one three-minute active-play period and original placeholder visuals. No 11v11, half-time, substitutions, headers, penalties, offside, advantage, controller support or multiplayer. Restarts and AI are deliberately simple. The retained Pass & defend and Solo practice modes keep empty goals and no clock. The core gameplay and first 5v5 milestone were accepted; Build 11’s keeper and attacking balance still need physical playtesting.
