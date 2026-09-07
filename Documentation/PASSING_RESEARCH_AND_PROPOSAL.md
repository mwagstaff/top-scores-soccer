# Passing and receiving: research and proposed redesign

Research date: 7 September 2026. Baseline: build 17 workspace. The research itself did not change production code or the installed app. The user subsequently authorised implementation: see [build 18 changes and verification](BUILD18_PASSING.md). The evidence and original proposal below are preserved as the design record.

## Recommendation

Treat an ordinary pass as a request to give a particular teammate a controllable ball. Plan the ball and receiver's likely movement together, preserve immediate joystick control, complete the first touch into a usable dribble, and show both the receiver and ball clearly. The last two updates improved individual input rules but did not validate that those rules still produced successful receive-and-run sequences.

The priority is a coordinated passing and receiving redesign, rather than another increase in pickup radius or a blanket increase in ball speed. The evidence below reproduces the reported long-pass and control failures without defenders.

## What the other games document

| Reference | Documented behaviour | Useful lesson |
| --- | --- | --- |
| Sensible World of Soccer 1.1 | A quick tap picks a nearby teammate in the general facing direction; holding produces a stronger straight kick. | An ordinary pass can express recipient intent without precise power control. |
| SWOS 96/97 | The manual explicitly links post-pass stick directions to both pass adjustment and receiver movement. Keeping an upfield passing direction can bring the receiver slightly towards the passer; neutral can make him wait. | Ball delivery and reception are coordinated. These special direction mappings differ from the immediate screen-direction control requested for our touch game. |
| FIFA 22 / FC 26 | Ground-pass assistance handles direction and power. Pass target lock timing and movement assistance after an automatic switch are separate settings. | Target choice, ball execution and the transfer of movement input need separate, predictable rules. |
| FC 26 gameplay notes | The notes describe receivers maintaining position for ordinary ground passes, leading through passes, faster quick passes, and improved first touches into dribbling. | Passing to feet and into space have distinct receiving intentions; successful contact should lead to useful possession. |
| PES 2019 / eFootball | Konami documents separate pass-speed assistance, switching options, first-touch direction, through passes, one-twos and teammate runs. | Passing quality includes choosing the recipient, getting into position, controlling the arrival and making the next action. |

Primary sources:

- [SWOS 1.1 printed manual, pp. 2–3 (PDF page 4)](https://files.swos.eu/manual/SWOS1.1/SWOS1.1manual.pdf#page=4).
- [SWOS 96/97 printed manual, pp. 14–15 (PDF page 9)](https://openretro.org/file/effc21899be62c73fb511110b634e2b4732763d3/Manual%20%28en%2C%20fr%2C%20de%2C%20it%2C%20es%2C%20nl%29.pdf#page=9). The archived scan was downloaded and visually read because the web reader could not ingest the large PDF.
- [EA: FIFA 22 control settings](https://www.ea.com/able/resources/fifa/fifa-22/ps5/customise-controls-settings).
- [EA: FC 26 assistance and switching settings](https://www.ea.com/able/resources/ea-sports-fc/fc-26).
- [EA: FC 26 gameplay notes, passing and first touches](https://www.ea.com/games/ea-sports-fc/fc-26/news/pitch-notes-fc26-gameplay-deep-dive).
- [Konami: eFootball v2.2, pass-speed assistance and cursor changes](https://www.konami.com/efootball/en-us/page/2023/season2_patch-notes_v2-20).
- [Konami: eFootball v4.0, first-touch direction](https://www.konami.com/efootball/en-us/page/v4/versioninfo_v4-00).
- [Konami: PES 2019 pass-and-move, one-twos and teammate controls](https://dds.konami.com/games/manual/pes2019/PC/en/control_team.html).

The manuals describe behaviour, not proprietary algorithms. They do not establish internal targeting weights, timing thresholds, movement blending or whether a particular game bends a ball towards its target after launch. Console/PC assistance settings are not assumed to be identical to mobile controls. The design below is our proposed adaptation.

## Reproducing our problem

A separate copy of the current simulation ran 240 deterministic scenarios: four distances (10, 20, 30, 40 metres), three initial receiver velocities, five joystick patterns after release and four ability profiles. The profiles included unrated practice and three actual bundled club-rating profiles. Other players were kept clear and AI movement was disabled. Every attempt selected the same intended teammate, used a normal 0.12-second pass, and produced no chip.

Each table cell gives **collected / retained for two seconds**, out of 12 scenarios. These are controlled case counts, not estimates of live-match completion percentages.

| Receiver input after passing | 10 m | 20 m | 30 m | 40 m |
| --- | ---: | ---: | ---: | ---: |
| Neutral | 12 / 12 | 12 / 12 | 12 / 12 | 12 / 12 |
| Original forward direction held | 8 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| Gentle forward movement | 12 / 0 | 8 / 0 | 8 / 0 | 8 / 0 |
| Gentle sideways movement | 12 / 4 | 10 / 3 | 0 / 0 | 0 / 0 |

Three concrete problems emerged:

1. **The pass expects a different run from the one you command.** Launch prediction uses the teammate's old velocity. The newly selected receiver then accelerates according to the joystick. With the passing direction held, he can run away from the point the ball was sent to. In the stationary 20-metre practice case, their closest separation was almost 10 metres. A receiver who had been running sideways also causes a stale sideways lead when you immediately request a different direction.
2. **Some successful contacts are not usable receptions.** A pass can be claimed about 2.85 metres behind a moving receiver. The ball is slowed, but subsequent moving dribble touches reject a ball that far behind him. Friction leaves it behind while he continues running. All 36 successful gentle-forward pickups lost control 0.55–0.90 seconds later. A half-second retention check would miss every one of these failures.
3. **The camera can hide the player you now control.** It guarantees visibility of the ball, with only a small bias towards the selected player. On the configured portrait phone view, a teammate 25 metres sideways can already be offscreen; one 40 metres ahead can initially be behind the top HUD. The target marker also changes into the controlled marker without a clear handover cue.

Neutral reception succeeded and retained possession in all 48 cases, including at 40 metres. This does not support a general claim that passes lack enough power to reach their planned destination. The missing part is planning the right destination and arrival for the newly controlled runner, followed by reliable first-touch handling.

The reproducible protocol, exact source hashes, all outcomes and selected traces are in [the diagnostic report](../.test-artifacts/PassingResearch/REPORT.md), [matrix](../.test-artifacts/PassingResearch/matrix.csv) and [traces](../.test-artifacts/PassingResearch/traces.csv). The experiment does not include defenders, offside, crowded match play, camera motion or human touch timing.

## Proposed player experience

### 1. A normal tap requests a pass to a clearly indicated teammate

Show a distinct marker for the intended recipient while aiming. Give direction priority; use distance and open lanes to resolve close choices. A slightly safer candidate far away from the requested angle should not silently replace the obvious intended player.

Commit recipient identity when the short passing action begins, and show that choice. Aim changes used to prepare the receiver's next movement must not change the recipient. A deliberate change to a charged kick or a special gesture gets its own explicit action state. Ordinary tap duration should not require fine power judgement.

### 2. Deliver to the run the receiver will actually make

For an assisted pass, predict the receiver's movement after handover: current velocity, normal acceleration, joystick-requested direction and speed, or automatic interception when neutral. Solve launch direction and pace against that same prediction, including ability modifiers before accepting the solution. Sending towards a new lead point while retaining pace for the old point would preserve the bug.

Choose a useful arrival time and controllable arrival speed within physical limits. Longer passes may need firmer delivery when the receiver is already running away from the passer. Avoid treating every longer hold as the only way to make a medium-distance ground pass work. If a receiving point is outside the pitch or not physically reachable within the available pace, do not silently promise it through the target preview.

### 3. Keep immediate, visible control of the receiver

At pass release, move the controlled-player marker immediately and keep selection stable while that pass remains viable. Any non-neutral joystick direction controls the receiver, including the exact direction held through the pass; no extra dead zone or hidden requirement to recenter first. Neutral input uses a reachable contact point on the real flight path and follows a nearby slowing ball.

A deflection, interception or clearly unreachable pass releases this selection preference promptly. Queuing the next kick preserves its outgoing aim separately from subsequent movement input.

This preserves the user's control preference while borrowing coordinated delivery from the researched games. It does not reproduce SWOS96/97's special post-pass direction mappings.

### 4. Make first touch carry into the next stride

A reachable intended pass should become a controlled first touch from the side or behind as well as directly ahead. Use the desired running direction to guide the ball into the next stride, with appropriate cushioning and foot positioning. A contact must not grant possession and then leave the ball in a location the dribbling code cannot handle.

Allow a queued first-time kick at contact and an immediate subsequent pass. Keep ratings meaningful through touch quality, pressure response and difficult passes; routine open receptions should not break solely because a normal running input remains held. Preserve physical interception, fouls, offside and aerial contact rules.

### 5. Show the passing action clearly

Frame both the ball and selected recipient during a teammate pass. Use bounded camera movement and, if needed, modest temporary zoom; return smoothly to normal play. A controlled player should remain inside the unobscured playing area whenever practical, with an edge marker if the required span exceeds the zoom limit.

Use different shapes for the preview target and controlled player. Make the handover obvious with a brief marker pulse. Receiving guidance should identify the controlled player; the optional next-kick hint should not replace that information. In-possession guidance should say to tap to pass when a teammate is targeted.

### 6. Make the distinction between feet and space predictable

Normal taps towards a viable teammate prioritise a controlled pass to feet or into that player's immediate running path. An open-space pass should be selected through clear spatial intent and visible feedback, rather than the narrow current 0.18–0.26-second tap interval. Long holds continue to mean a shot or long/high kick.

The initial prototype should keep the established one-stick, one-button layout. Exact tap thresholds and any additional through-ball gesture remain tuning decisions; changing them is secondary to fixing the proven delivery and reception faults.

## Prototype order and acceptance

First implement the coordinated launch plan, sustainable first touch, receiver visibility and stable target feedback. Keep normal manual steering immediate. Re-run the same matrix before adding another assistance rule.

A new direction chosen after the ball has left the foot cannot be known by the launch planner. Start with physical flight and measure early direction changes explicitly. If ordinary small corrections still make passing unreliable after the proven defects are fixed, compare a second prototype with a narrowly bounded early adjustment to the intended receiver's path. Such assistance must stop at contact, a deflection or an interception opportunity; it must not change recipient or carry the ball around a defender. This would be an explicit arcade tradeoff, not a claim about FIFA/PES internals.

Proposed acceptance targets, to be tuned through playtesting:

- At least 95% of clear-lane 10–30 metre passes with neutral or sustained requested movement are both received and retained for two seconds; at least 90% at 40 metres when the requested run stays on the pitch. These are engineering goals, not published game statistics.
- Gentle steering immediately after release, diagonals, direction changes and real two-thumb input must be measured separately; a successful pickup alone is insufficient.
- Input changes affect receiver movement on the next simulation tick. Ordinary acceleration remains, and no automatic route suppresses deliberate steering.
- Ten-pass one-two sequences, first-time queues and receive-and-run turns work across rating levels before increasing defender pressure.
- Both ball and receiving player remain visible through typical 10–40 metre handovers on a portrait iPhone, with readable control markers.
- Opponents can still intercept genuine lanes. Add active pressure and 11v11 spacing after the unopposed baseline works, and report failures by cause rather than lowering the baseline to match them.
- Check goalkeeper backpasses, throw-ins, ground-pass chips, high balls, offside and cancellations for regressions.

The deciding test is a short on-device passing drill with moving teammates, followed by match play. A large unit-test count cannot establish that the controls feel natural; the next delivery should include evidence that ordinary complete passing sequences work.
