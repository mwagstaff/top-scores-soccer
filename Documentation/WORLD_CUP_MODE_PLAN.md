# World Cup mode plan

## Agreed scope

Add **World Cup** as a separate single-player mode alongside Friendly and Career. The player chooses one of 48 national teams, edits that team's starting XI, and plays its tournament matches. Career and World Cup saves are independent and can coexist.

Use the 2026 competition structure:

- 48 teams in 12 groups, A–L, with four teams per group.
- Three group matchdays and three matches per team. Each group contains six fixtures, for 72 group-stage fixtures overall.
- Matchday pairings follow the supplied schedule: **1 v 2 and 3 v 4**, then **1 v 3 and 4 v 2**, then **4 v 1 and 2 v 3**.
- The first two teams in every group and the eight best third-placed teams advance to the Round of 32.
- Single-elimination Round of 32, Round of 16, quarter-finals and semi-finals, followed by the third-place match and final.
- A finalist plays eight matches. A semi-final loser plays the third-place match.
- Regulation time remains the normal **three minutes of active play** and pauses under the existing match rules.

Retain the supplied 2026 stage dates as display metadata: group matchdays run **11–17 June**, **18–23 June** and **24–27 June**; the Round of 32 runs **28 June–3 July**; Round of 16 **4–7 July**; quarter-finals **9–11 July**; semi-finals **14–15 July**; third-place match **18 July**; and final **19 July**. These labels provide tournament flavour and ordering but do not create calendar events or make saves depend on the device date.

This is a fresh playable tournament, not a recreation of the real 2026 results. Bundle a reviewed offline snapshot of the 48 participating national teams and the 2026 group allocation. Do not depend on a network request to start or continue a tournament. Freeze squads, ratings, appearances, kits, group positions and the rules version when a new save is created, just as Career freezes its catalogue.

If licensed national-team player data is unavailable, retain the real country names and reviewed flag/kit colours but use clearly labelled generated stand-ins. Do not ship federation crests, FIFA wordmarks, an exact scan of the current FIFA trophy, or other protected competition artwork without confirmed rights.

## Tournament rules

### Group stage

Award three points for a win, one for a draw and none for a loss. Rank teams by:

1. points in all group matches;
2. goal difference in all group matches;
3. goals scored in all group matches;
4. points in matches among the tied teams;
5. goal difference in matches among the tied teams;
6. goals scored in matches among the tied teams;
7. lower fair-play penalty from cards recorded in tournament fixtures;
8. a deterministic drawing-of-lots value stored in the save.

Compare third-placed teams by points, goal difference, goals scored, fair play and the saved drawing-of-lots value. Never use display name as a sporting tie-break. Store the resolved ordering so a later app or catalogue update cannot change qualification.

Simulate every non-player fixture in a matchday from the tournament seed and frozen team strength. Commit the player's result, the other results due at that checkpoint, updated tables, qualifiers and any newly created knockout fixtures in one atomic save. Repeated completion callbacks must be idempotent.

Use the official 2026 knockout-slot mapping for group winners, runners-up and the possible combinations of best third-placed teams. This must be represented as reviewed static rules data and exhaustively tested; do not fill open Round-of-32 slots by simply sorting the eight third-placed qualifiers.

### Knockout stage

A knockout fixture cannot end level. Keep the ordinary three-minute match as regulation time, then use a compact arcade version of the official resolution sequence:

- one minute of active extra time, presented as two 30-second periods without changing the user's northward attacking direction;
- if still level, a five-kick penalty shoot-out followed by sudden death;
- record regulation, extra-time and shoot-out scores separately so fixture rows can display **AET** or **PENS** correctly.

Penalty shoot-outs are a prerequisite for shipping World Cup mode, not a random result dialog. Build them on the existing one-stick/one-button controls: the kicker aims and charges; the user's keeper chooses a dive direction. The opposition uses bounded deterministic intent. Keep the sequence short, readable and skippable only when the user's team is not participating.

The existing 3–0 forfeit rule remains. Cards reset between fixtures for the first World Cup milestone, but each match contributes a fair-play value for group ranking. Cross-match suspensions, substitutions, injuries, travel and player fatigue remain outside this milestone.

If the user's team is eliminated, show the result and tournament path, then offer **Finish tournament** to simulate the remaining fixtures or **New World Cup**. Do not force the player to watch or play neutral matches.

## User flow and interface

Add a third tab to `FootballHomeView`:

1. **Friendly**
2. **Career**
3. **World Cup**

An empty World Cup save opens a searchable national-team picker. A team card shows country name, short code, kit preview and squad availability. Starting the tournament shows a replacement confirmation only when another World Cup save exists; it never mentions or alters Career.

The active tournament dashboard contains:

- chosen national team and current stage;
- next fixture, opponent and group/knockout context;
- selected team's starting XI and formation editor;
- the selected group's table during the group stage;
- **All groups & results**;
- a complete knockout bracket once the group stage is resolved;
- qualification, elimination, third-place, runner-up or champion status;
- a persistent save-status line and a pinned **Play next match** action.

The match presentation continues to put the user's team in the blue-engine/north-attacking role while the scoreboard, kits and saved result retain the fixture's actual left/right or nominal home/away order. Replace Career-specific labels in the shared match screen with a small competition context containing a competition title, fixture title, return label and completion callback.

Use country short codes in tight score and bracket layouts, but expose full country names to VoiceOver. Tables and the bracket must work in portrait on iPhone and iPad, Dark Mode and the largest supported Dynamic Type size. Prefer a vertically scrolling bracket on phone rather than shrinking text below a readable size.

## State and persistence

Create a dedicated `WorldCupStore` and `WorldCupSave`, stored separately from `CareerStore` under Application Support, for example `WorldCup/world-cup.json`. Use schema-versioned `Codable` values and the same staged-validation-plus-atomic-replacement approach already proven by Career.

The save owns at least:

- schema and rules versions;
- tournament ID, seed, start date and selected national-team ID;
- the 48 frozen teams, squads, ratings, appearances and kit data;
- 12 immutable groups and positions 1–4;
- every group fixture and result;
- group tables, best-third ranking and qualification result;
- every knockout fixture, source slot and resolved participant;
- regulation, extra-time, shoot-out and forfeit result fields;
- selected formation and XI;
- current stage and next playable fixture;
- fair-play totals and deterministic lot values;
- champion and the selected team's finishing state;
- whether the winner celebration is pending or has been acknowledged.

Save at these checkpoints:

- immediately after tournament creation and group allocation;
- after every saved lineup change;
- atomically at the end of every user match, before enabling Continue;
- after every simulated matchday or knockout round;
- before presenting the trophy celebration, with the user's team already recorded as champion;
- when acknowledging the celebration or finishing the tournament.

An unfinished three-minute match restarts from kickoff, matching Career. Mark its fixture as the active ticket before presenting the pitch so it cannot be accidentally simulated, but do not serialize a partly advanced football simulation in the first milestone. Backgrounding pauses play and clears transient input. The maximum lost play is the current short match; all completed tournament progress is already safe.

If a save fails, keep the completed result in memory, keep the match result screen visible, and offer **Retry save**. If a save is unreadable, preserve the file and require explicit confirmation before replacing it. Starting a new World Cup must not delete a Career save, and vice versa.

## Code boundaries

Keep tournament scheduling and ranking in plain Swift, independent of SwiftUI and SpriteKit:

- `WorldCupModels.swift`: save, group, fixture, result, standings and bracket-slot values.
- `WorldCupRules.swift`: group schedule, rankings, best-third selection, knockout mapping and validation.
- `WorldCupStore.swift`: loading, atomic persistence and idempotent mutations.
- `NationalTeamCatalogue.swift` plus a bundled validated JSON snapshot.
- `WorldCupView.swift`: team selection, dashboard, tables and bracket navigation.
- `CompetitionMatchContext.swift`: a replacement for the Career-only match context so Career and World Cup share `GameSession` and `SandboxView` without either mode knowing the other's model.
- `PenaltyShootout` model/controller and a focused presentation layer that reuse existing player, ball, input, kit, audio and haptic primitives.
- `WorldCupCelebrationView` and its presentation/audio controller, isolated from tournament rules.

Do not generalize the entire game around hypothetical competitions. Extract only the match-context and outcome seam already shared by Career and World Cup. Keep the existing `CareerSave` schema readable and migrate only if a concrete shared value type requires it.

## Winner celebration

After the user's final result has been saved successfully, replace the ordinary Continue card with a full-screen celebration:

- an original polished gold trophy inspired by the requested Jules Rimet-era silhouette rises into view;
- a moving gleam sweeps across the trophy without rapid flashing;
- gold ticker tape and small metallic confetti rain behind it;
- the selected team name and **WORLD CHAMPIONS** appear clearly above the effects;
- an original crowd-cheer loop, a short victory sting and restrained success haptics play when sound/haptics are enabled;
- **Continue** becomes available promptly, and **Replay celebration** remains on the champion dashboard.

Implement the ticker tape with a bounded SpriteKit `SKEmitterNode` or an equivalently efficient effect. Keep particle count capped and verify 60 fps on the physical acceptance device. The trophy and title remain legible if particle effects fail or are disabled.

Respect system and game accessibility choices. With Reduce Motion enabled, use a static trophy, gentle opacity change and sparse or static ticker tape instead of the rise, scale and continuous falling motion. Avoid flashing highlights, keep the celebration understandable without sound or haptics, hide decorative particles from accessibility, and announce the selected team as world champions to VoiceOver.

Set `celebrationPending` only after the champion save succeeds. A crash or interruption before acknowledgement may show the celebration again on relaunch, but it must never replay the final, duplicate the result or lose the title.

### Debug-only preview

Provide two DEBUG-build-only entry points that do not mutate a real tournament:

- a **Preview trophy celebration** action in the World Cup toolbar or debug menu;
- a `--world-cup-celebration` launch argument for deterministic UI tests and direct simulator/device review.

Compile both entry points behind `#if DEBUG`. The preview uses a fixed sample team and seed so screenshots, particles and audio timing are repeatable. No preview control, route or launch-argument handling should exist in an Archive/Release build.

Also provide a DEBUG-only `--world-cup-final-ui` seed that creates a disposable test save immediately before the final. This tests the real final-result/save/celebration handoff separately from the visual-only preview.

## Delivery sequence

1. **Rules and data foundation:** add and validate the 48-team snapshot, group allocation, three matchdays, standings, third-place comparison, official knockout mapping and deterministic neutral-match simulation.
2. **Independent save:** implement `WorldCupStore`, complete structural validation, atomic writes, recovery behavior and migration boundaries. Add model/store tests before UI.
3. **Mode and dashboard:** add the third tab, national-team choice, lineup editing, group tables, results, stage status and bracket. Generalize the shared competition match context without changing Career behavior.
4. **Tournament match loop:** play group fixtures with the existing three-minute 11v11 engine, simulate other fixtures at checkpoints, advance or eliminate correctly, and persist before Continue.
5. **Knockout resolution:** add compact extra time and the playable penalty shoot-out, then cover every possible user path through Round of 32, Round of 16, quarter-final, semi-final, third-place match and final.
6. **Celebration:** add the original trophy artwork, gleam, ticker tape, cheers, victory sting, haptics, accessibility fallback and both DEBUG-only preview paths.
7. **Verification and device delivery:** run all existing Career/Friendly/gameplay regressions plus the new World Cup suite; visually inspect normal/large-text/Reduce-Motion layouts on phone and iPad; verify celebration performance, sound behavior and a signed device build.

## Required automated checks

### Rules and model tests

- Exactly 48 unique teams, 12 groups of four, six fixtures per group and 72 group fixtures.
- Every team plays once on each matchday, three times in total, and every pair in a group meets exactly once using the supplied pairings.
- Points, all tie-break layers, fair play and deterministic lots produce stable results.
- Exactly 24 first/second-place teams and eight third-place teams qualify.
- Every supported third-place combination produces 16 unique Round-of-32 fixtures with no duplicated or missing qualifier.
- Every knockout winner advances to exactly one correct fixture; the semi-final losers reach the third-place match.
- A finalist has eight tournament fixtures; group elimination and each knockout exit stop offering playable fixtures at the right time.
- Group matches may draw; knockout matches cannot finish unresolved.
- Simulation is deterministic for a saved seed and never resimulates a committed fixture.
- Venue/result translation remains correct while the user's team attacks north.
- Forfeits, extra time and penalties serialize, validate and display correctly.
- Save callbacks are idempotent; corrupt, oversized, stale and failed writes leave the last valid file and in-memory result recoverable.
- Career and World Cup save operations cannot read, replace or delete one another.
- Only a saved user victory in the final sets champion and celebration-pending state.

### UI and accessibility tests

- Friendly, Career and World Cup tabs remain reachable on supported phone and iPad layouts.
- Choose any national team, start a World Cup, edit the XI and relaunch into the same next fixture.
- Complete a shortened group stage in test mode, verify the table and qualification or elimination result, then inspect the Round-of-32 bracket.
- Complete a tied shortened knockout match through extra time and penalties.
- Terminate on a saved result screen and after the final; relaunch without duplicating results or losing progress.
- Win and lose the final; only the win presents the celebration.
- The visual-only debug preview leaves existing Career and World Cup saves unchanged.
- Largest Dynamic Type, Dark Mode, VoiceOver labels and Reduce Motion retain every required action and result.
- A Release configuration contains no debug celebration button or debug launch route.

### Physical acceptance

- Play one complete three-minute group match and one tied knockout match on the nominated iPhone.
- Confirm pause/background/foreground behavior and that a completed match survives force quit.
- Confirm crowd audio respects the existing sound setting and Silent Mode, and that visual feedback carries the celebration with sound and haptics off.
- Verify sustained 60 fps during the heaviest ticker-tape moment; inspect with Instruments if frame pacing drops.
- Confirm the trophy, text, ticker tape, buttons and bracket are readable on a representative iPad as well as iPhone.

## Definition of done

World Cup mode is complete when the user can keep an independent Career save, choose any of 48 national teams, play three-minute matches through a valid 12-group tournament, qualify via the correct first/second/best-third rules, resolve every knockout tie, leave and relaunch without losing completed progress, and receive the accessible animated gold-trophy celebration only after a saved final victory. The celebration must also be directly previewable in a DEBUG build and unreachable in Release.

## References

- [FIFA: 2026 competition format](https://inside.fifa.com/organisation/fifa-council/media-releases/fifa-council-approves-international-match-calendars)
- [FIFA: 2026 fixtures, groups and format](https://www.fifa.com/en/tournaments/mens/worldcup/canadamexicousa2026/articles/fifa-world-cup-2026-hosts-cities-dates-usa-mexico-canada)
- [Apple: SKEmitterNode](https://sosumi.ai/documentation/spritekit/skemitternode)
- [Apple: Reduce Motion in SwiftUI](https://sosumi.ai/documentation/swiftui/environmentvalues/accessibilityreducemotion)
- [Apple: AVAudioPlayer](https://sosumi.ai/documentation/avfaudio/avaudioplayer)
