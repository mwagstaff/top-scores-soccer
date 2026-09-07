# Build 20 — restart options and penalties

## What changed

Two nearby, eligible outfield teammates now run into separate short passing positions at throw-ins and free kicks. Their chosen positions remain stable while the taker aims, and a dismissed or unavailable helper is replaced. The ball and taker stay in place until release. The opposition computer gives support time to arrive, with a bounded fallback so restarts cannot stall.

Free-kick opponents stay at least 9.15 metres (10 yards) from the ball. The permitted exception is a defender on his own goal line between the posts. At a defensive free kick inside the taking team's penalty area, opponents also stay outside that area. Throw-ins keep the separate two-metre restriction measured from the touchline point.

An actual direct-free-kick tackle foul in the offender's own penalty area now awards a live penalty. The box boundary belongs to the area, and the decision uses the saved impact position rather than the ball's later position. The existing contact, fall, whistle, card and recovery sequence plays before placement at the 11-metre mark.

The keeper waits on the goal line; other players wait outside the area and penalty arc, behind the mark, with enough separation to remain visible. Aim left or right and tap for a useful shot, or hold and release in the shot meter's green band. Overholding can lift the shot over the bar, and aftertouch still works. Opposition penalties are automatic; normal physics decides goals, saves, posts and rebounds. A taker touching the ball again before another player concedes an indirect free kick. A penalty awarded before the clock expires is allowed to finish.

These changes apply to match play, including 5v5, friendlies, Career and World Cup fixtures. The empty-goal Pass & defend drill gains free-kick support but retains its practice restart rules. World Cup tie-breaking shootouts remain separate.

## What to try on the phone

1. Let the ball cross either touchline. Watch two teammates come towards the thrower, then aim at one and use a short throw. Hold longer to throw beyond the short options.
2. Win a free kick. Aim sideways or back towards an approaching teammate, release the stick and tap ACTION. Check that the short pass is easy to receive and opponents remain clear.
3. Draw a challenge inside the opposition box. Watch the fall and whistle, then take the penalty from the spot. Try a tap, a green-band shot, a deliberately overheld shot and sideways aftertouch.
4. Concede a penalty in your own box. Check the card is retained and your goalkeeper faces the automatic shot.
5. Repeat in an 11v11 match to check that restart support stays readable among more players.

## Rules checked

- [IFAB Law 13 — Free kicks](https://www.theifab.com/laws/latest/free-kicks/): minimum opponent distance, own-goal-line exception, and opponents outside the taking team's penalty area.
- [IFAB Law 14 — The penalty kick](https://www.theifab.com/laws/latest/the-penalty-kick/): award, positioning, forward kick, second touch and completion at period end.
- [IFAB Law 15 — The throw-in](https://www.theifab.com/laws/latest/the-throw-in/): opponent distance.

The two short support runs and forgiving penalty aim are arcade design choices. Rules use player centres and the painted box; this update does not add VAR, off-ball holding offences or detailed goalkeeper-encroachment adjudication.

## Verification

The final combined app is installed as version **0.1.0, build 20**, on the connected **iPhone 16 Pro Max, iOS 26.6.1**. Unlock the phone and open **Top Scores Soccer**; its lock prevented automatic launch.

| Check | Result |
| --- | --- |
| Focused simulation regression suite | 89 tests passed in `.test-artifacts-build20-swift-final.log`. |
| Complete combined native/gameplay suite | All 529 tests passed in `.test-artifacts/Build20CombinedPhone.xcresult`. Includes foul animation, box boundaries, live penalties, second touches, period completion, support runs, passing and existing World Cup/Career tests. |
| iPhone touch checks | All three restart tests passed in the same combined phone bundle: short free-kick pass, tap/held penalty, and short throw-in. |
| iPad touch checks | All three tests passed in `.test-artifacts/Build20CombinedPad.xcresult`, in Dark Mode at the largest accessibility text size. |
| Visual review | Phone and iPad restart layouts, nearby options, keeper/penalty placement and controls inspected. No critical clipping or setup issue. The existing translucent guidance panel can show pitch detail behind text. |
| Signed device build | `.test-artifacts-build20-combined-device.log` reports BUILD SUCCEEDED; strict code-signature verification passes and CFBundleVersion is 20. |
| Final physical installation | Confirmed by `.test-artifacts/Build20CombinedDeviceInstall.json` and the installed-version query `.test-artifacts/Build20CombinedDeviceApps.json`. Launch denial records the device lock in `.test-artifacts/Build20CombinedDeviceLaunch.json`. |
| Final source | Matches the tested/signed snapshot in `.test-artifacts/Build20CombinedSourceHashes.json`. No drift or newly added production source at final verification. |

The final signed app is preserved at `.test-artifacts/Build20Verified.app`; the normal Xcode project builds the same combined gameplay and World Cup updates. The iPad simulator was restored to Light Mode and normal text size, then shut down; the test phone is also shut down.

Earlier failed runs are retained for diagnosis. They exposed an AI thrower heading his own short throw, an intended receiver heading a ball just before foot-height reception, and an AI-speed-zero fixture waiting for players that could not move. Those regressions are fixed. The free-kick UI test was corrected to wait for two physically settled short options and verify pass/restart completion rather than a later selection during live defending; native tests retain exact immediate receiver-handover coverage. A free-kick launch fixture was also moved clear of an unintended opponent overlap. The final passing combined bundles supersede these attempts.

The final build initially overlapped an unfinished World Cup screen edit in the shared workspace. Both tasks coordinated, preserved each other's changes, and verified the completed combined source before final installation.

Physical feel and sustained device performance remain playtest observations.
