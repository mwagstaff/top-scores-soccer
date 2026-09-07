# Build 18 — coordinated passing and receiving

Implementation of the [research-backed passing proposal](PASSING_RESEARCH_AND_PROPOSAL.md), authorised on 7 September 2026. **Build 18 is installed on the iPhone.** Automatic launch was blocked because the phone was locked; unlock it and open **Top Scores Soccer**.

## What to try

1. In **Friendly → Training → Pass & defend**, aim roughly at a teammate. Cyan brackets show the recipient. Tap ACTION; the yellow control marker transfers immediately, with a brief pulse.
2. Keep the original joystick direction held after passing, including medium and long passes. The ball is planned for that run and a successful first touch should flow into the next stride.
3. Centre or lift the joystick to let the receiver move to meet the ball. Drag again to take over immediately. Try a small sideways adjustment and a receive-and-run turn.
4. Aim at the next teammate and tap before the incoming ball arrives. The next pass retains that teammate while you move to meet the arrival. Repeat quick triangles and one-twos.
5. Change movement while holding a short ACTION press: the recipient already shown stays selected. A deliberate charged kick or backheel uses its own direction rules.
6. Aim into a clear lane and tap. A reachable onside runner can receive a through ball into space; otherwise the ball is nudged ahead to chase. Short-tap duration no longer chooses between a knock-ahead and through ball. Hold for a long/high kick or shot.
7. Try a 30–40 metre pass. Both ball and receiver should remain visible between the HUD and controls. Exceptionally wide spans show a numbered arrow at the edge, with bounded zoom.
8. Repeat in an 11v11 friendly with defenders moving, then test a keeper backpass, a held clearance and an early queued shot. Defenders can still intercept and challenge; the keeper must use his feet for a teammate's backpass.

## Mechanics

- The launch planner includes receiver acceleration, requested movement, neutral braking and bounded ability differences. It solves the future contact point and pace together, rather than leading the old AI run and then handing over a different run.
- Direction is the main target-selection signal. Distance and lane risk resolve similar options; a much wider open teammate does not replace a clearly aimed recipient. Unreachable plans are excluded.
- The indicated recipient is committed at button-down. Queued passing retains that identity and outgoing aim separately from movement. Charging and deliberate backheels leave the ordinary pass lock.
- An intended reception uses a bounded physical cushioning touch to bring the ball from the side or behind into the next stride. The ball is not teleported. Opponent contacts, offsides and fouls remain active throughout reception.
- A new steering input can receive one small direction correction within the first 0.12 seconds of an ordinary teammate pass, capped at 6 degrees and preserving ball speed. Neutral lifts, queued actions and reverse chips do not request it. Any contact, deflection or reachable opponent interception closes the window; both the original and adjusted lanes are checked. There is no continuous ball tracking or recipient change.
- Receiver selection stays stable for a viable pass. Deflection, interception or an unreachable flight releases that preference.
- Neutral movement and queued reception share the earliest reachable point on the physical ball path. A fresh return pass releases the intended receiver’s old rebound guard, allowing close one-twos without allowing the kicker to reclaim his own kick immediately.
- The portrait camera includes ball and receiver, with at most 20% extra zoom-out and a smooth return. Cyan target brackets, the yellow control ring and a short handover pulse use different shapes; control guidance takes priority over the optional next-kick hint.

## Verification record

All **469 gameplay/native tests passed** in `Build18FinalCore.xcresult`. Coverage includes actual scene/input handovers at 10, 25 and 40 metres, sustained possession after reception, ten queued passes, close one-twos, keeper backpasses, interceptions and retained World Cup checks.

Five selected ordinary phone UI flows passed: passing practice, edited 11v11 setup/kickoff, keeper distribution, keeper foot control and charged throw-ins. The passing UI also passed in Dark Mode at the largest accessibility text size. On iPad, all 13 selected camera/scene tests and the passing UI passed. Rendered phone and iPad screenshots were inspected for target/control visibility and readable guidance.

The independent comparison ran 2,688 controlled cases with the early adjustment disabled and enabled, plus 28 passing full-flow tests. With the guarded adjustment enabled, all **240 original scenarios** acquired the intended receiver and retained possession for two seconds, compared with **91/240** retained in build 17. All **480 expanded cases where movement was known at launch** also received and retained possession. In 144 active 11v11 fixtures, interceptions and subsequent challenges remained possible, with no unexplained first-touch losses. These fixture counts are engineering evidence, not live-match completion rates.

One deliberate limit remains: abruptly changing from a gentle run to full speed after release cannot increase the ball’s existing speed. That accounts for 72 unsuccessful cases in the expanded matrix. The small early correction changes direction once, never pace. Physical thumb feel and match balance still need the user’s playtest. See [the full diagnostic report](../.test-artifacts/PassingBuild18/REPORT.md).

The final signed device build passed signature verification. An independent installed-app query confirmed **0.1.0 / build 18** on the connected iPhone 16 Pro Max at 16:21 on 7 September 2026. The install command timed out, but the successful installed-version query establishes delivery. Launch was denied because the phone was locked.

Evidence under `.test-artifacts/`: `Build18FinalCore.xcresult` is the final green native suite; `Build18PadValidation.xcresult` is the green iPad run. The five ordinary phone UI results are in `Build18FinalPhone.xcresult`, and the accessible passing UI result is in `Build18DeliveryValidation.xcresult`; those two bundles also contain earlier native failures corrected before the final green suite. Delivery records are `Build18InstalledApp.json` and `Build18DeviceLaunch.json`; the final signed build log is `.test-artifacts-build18-delivery-device.log` at the repository root.

The baseline and source hashes remain under `.test-artifacts/PassingResearch/`. New snapshots, diagnostics and comparisons are under `.test-artifacts/PassingBuild18/`. Xcode validation uses the existing invocation-only compiler-discovery workaround; no permanent compiler setting was added.
