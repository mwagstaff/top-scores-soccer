# Build 19 — targeted goalkeeper distribution

Implements the keeper distribution changes requested on 7 September 2026. **Build 19 is installed on the iPhone.** Automatic launch was blocked because the phone was locked; unlock it and open **Top Scores Soccer**.

## What to try

1. After your keeper catches an opposition ball, point the joystick towards a teammate. Cyan brackets identify the recipient. Tap ACTION to deliver to him, then steer the recipient immediately or release the joystick to meet the ball automatically.
2. Try a close outlet and a player farther away. The keeper bowls a close, open ball underarm, or throws overarm when distance or the receiver’s run needs more pace.
3. Aim towards a teammate with an opponent between them. The keeper chooses a higher arc if he can clear the intervening defender. The ball still follows normal physics, so the receiving end can be contested.
4. Hold ACTION for a longer, higher overarm throw. The distance bar shows the charge; the preview moves to a suitable farther teammate or into space. A nearby outlet should not turn this into a short throw. Fresh sideways joystick input can add aftertouch.
5. At a goal kick, aim at a teammate and tap. An open route gets a foot pass; a blocked route gets a lofted kick. Hold for a longer, higher goal kick. The taker stays at the restart spot while you aim.
6. Compare lower- and higher-rated keepers. Stronger distribution permits more range and pace with less execution error; routine open outlets should remain usable with either.
7. Try an own-team backpass. The keeper must still use his feet. Also check that cancelling ACTION or pausing never releases a caught ball accidentally.

## Design

The same target selection drives the preview and delivery. A tap commits the indicated teammate at button-down. Its trajectory is solved for the receiver’s movement at release, including acceleration and neutral braking. Holding deliberately switches to long distribution. A bounded physical first touch cushions the descending ball before normal dribbling resumes.

Keeper quality affects attainable range, pace and accuracy once. The planner accounts for gravity and intervening players’ contact regions; it does not steer the released ball around an opponent. Offside applies to throws in open play, while a direct goal kick keeps its existing exemption.

Visible underarm, overarm and kicking follow-throughs play on the original keeper while control transfers to the recipient. The distance bar and guidance distinguish throwing from kicking. The camera also frames the highlighted outlet before release, keeping the keeper selected until he distributes; exceptional spans use a numbered target indicator.

The [research record](KEEPER_DISTRIBUTION_RESEARCH.md) compares original Sensi/FIFA manuals with official PES/eFootball controls and EA developer notes. Directional distribution and ability-dependent range have documented precedents. Automatic obstruction-aware keeper loft is our adaptation; held overarm throwing follows the user’s request rather than the punt command used in several reference games.

## Verification and delivery

All **490 gameplay/native tests passed** on the final production source in `Build19DeliveryPhone.xcresult`. The main receiving matrix covers hands/goal kicks at three distances each, with neutral, gentle and full-speed movement, and requires reception followed by two seconds of sustained control. Additional checks cover committed targets during direction changes, physical clearance of a central defender, lower-rated keepers, held range/height, aftertouch, cancellation and backpasses.

Five independent rule tests verify actual goal-kick reception beyond the defensive line without offside, open-play throw offside on involvement, an opponent heading a descending throw, a defender intercepting a released low kick, and bounded ability/charge effects. The final native camera check exercises both sides of the pitch at two phone sizes and an iPad size, before and after handover.

All five selected ordinary phone UI flows passed in `Build19Phone.xcresult`: keeper throws, goal kicks, backpass foot movement, throw-ins and passing practice. The two keeper distribution flows passed again after the final camera change in `Build19DeliveryPhone.xcresult`. On iPad, the six final native presentation checks and both distribution UI flows passed in Dark Mode at the largest accessibility text setting in `Build19DeliveryPad.xcresult`. Throwing poses, meters and full phone/iPad screenshots were inspected; the final keeper preview now keeps the wide highlighted outlet visible.

The final signed app built successfully and passed strict signature verification. Installation succeeded at 17:06 on 7 September 2026; the installed-app query at 17:06:49 confirms **0.1.0 / build 19** on the connected iPhone 16 Pro Max. Launch was denied because the phone was locked. Final device records are `Build19DeliveryInstall.json`, `Build19DeliveryInstalledApp.json` and `Build19DeliveryLaunch.json` under `.test-artifacts/`; the signed build log is `.test-artifacts-build19-delivery-device.log`.

Final screenshots are in `.test-artifacts/Build19DeliveryPhoneScreens/` and `Build19DeliveryPadScreens/`; the source/test hashes are in `.test-artifacts/KeeperBuild19/final-source-hashes.json`. Earlier green bundles predate the final preview-camera adjustment. A debug Mac measurement with 22 players averaged 0.18 ms for a target/trajectory-preview pair; it is not a physical-device frame-rate measurement. Gameplay feel and match balance remain for the user's playtest.
