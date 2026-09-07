# Goalkeeper distribution: research and Build 19 design

Research date: 7 September 2026. This is a design record, based on publisher manuals and developer notes. It does not claim to reproduce the games' private targeting or physics algorithms.

## What the games document

| Source | Documented behaviour | Application to our controls |
| --- | --- | --- |
| **Sensible Soccer, original Amiga manual**, printed p. 4 | Set-piece kicks and throws use the ordinary kick/pass controls, with inappropriate angles excluded. Keeper control becomes available when holding the ball or taking a goal kick. This edition describes kicking the ball out; it does not specify underarm/overarm selection. [Original manual scan, PDF p. 8](https://openretro.org/file/4800a502e979f9f7062a8c92f21f4271215c4f3a/Manual%20%28en%2Cfr%2Cde%2Cit%29.pdf#page=8). | Keep restart controls consistent with open play. The requested adaptive throws are an extension, rather than an established Sensi mechanic. |
| **FIFA International Soccer, SNES manual**, printed p. 3 | The same keeper-distribution command throws or kicks according to nearby players. The manual separately lists controls for aiming restarts. [Original manual, mirrored PDF](https://www.retrogames.cz/manualy/SNES/FIFA_International_Soccer_-_SNES_-_Manual.pdf#page=3). | There is historical precedent for selecting the delivery technique from context while retaining a simple action. This does not establish the distance thresholds or trajectory calculations. |
| **PES 2019**, official keeper manual | Stick direction aims the delivery. Throw, throw into space, drop kick and high punt are separate commands. Low-punt and high-punt skills alter available delivery trajectories. [Konami keeper controls](https://dds.konami.com/games/manual/pes2019/PC/en/control_keeper.html). | Distinguish an intended recipient from an intentional long distribution. Ability may change the achievable flight; selecting a teammate should remain predictable. |
| **eFootball**, official mobile Bluetooth-controller manual | High punt is a distinct command with a fixed power gauge. Goal kicks offer low pass, low through ball and lofted pass, with directional aiming and trajectory controls. This source describes connected-controller input, not the ordinary touchscreen scheme. [Konami controls manual](https://www.konami.com/efootball/en-us/page/mobile_controller). | A committed high delivery need not require delicate power timing. Goal kicks should retain both a short option and an explicit long option. |
| **FIFA 23 / FC 25**, developer gameplay notes | FIFA 23 adds a driven roll alongside the existing driven throw and describes improvements to throw pace, accuracy and trajectories. FC 25's Far Throw trait increases throwing speed and distance, with a stronger effect for its enhanced variant. [FIFA 23 goalkeeper changes](https://www.ea.com/ea-originals/news/pitch-notes-fifa-23-gameplay-deep-dive), [FC 25 keeper PlayStyles](https://www.ea.com/games/ea-sports-fc/fc-25/news/pitch-notes-fc-25-gameplay-deep-dive). | Give low and high deliveries visibly different releases. Keeper quality can affect useful range and accuracy without making a routine outlet unreliable. |
| **FC 26**, developer gameplay notes | Keeper throw targeting is improved. Separately, ordinary lob passes use more driven trajectories when the route is unobstructed. No keeper-specific obstruction solver is disclosed. [EA passing changes](https://www.ea.com/games/ea-sports-fc/fc-26/news/pitch-notes-fc26-gameplay-deep-dive). | Context can select a useful arc. Applying that principle to keeper throws is our inference, not a documented FC algorithm. |

The original Sensi scan was visually checked. The historical FIFA claim comes from the original manual's indexed control-summary text. Platform and edition differences matter: none of these sources establishes that all versions use the same assistance. They do not disclose exact underarm thresholds, obstacle margins, rating multipliers, recipient-lock timing or automatic keeper-throw loft selection.

## Recommended rules for one stick and one button

These are our adaptation of the evidence and the user's requested behaviour.

| Situation | Tap | Hold |
| --- | --- | --- |
| Ball in the keeper's hands | Deliver to the highlighted teammate: underarm for a close open outlet; overarm for distance; a higher arc where a reachable flight can clear an intervening opponent. | Force a long, high **overarm throw**, even if a short outlet is available. More hold adds bounded range. |
| Goal kick | Deliver to the highlighted teammate from the ground. Use a low pass when open and an appropriately lofted foot kick when distance or obstruction calls for it. | Force a long, high foot kick. A close highlighted player must not reduce it to a short pass. |
| Keeper controlling a backpass at his feet | Preserve the existing foot-control rules. | Preserve the existing foot-kick rules. |

The requested held overarm throw takes priority over the punt used by several reference games. Use the existing tap/hold distinction; the player should not need another modifier, a force-sensitive screen or a second power-timing game.

**Preserve recipient intent.** Capture the highlighted teammate when the tap starts. Subsequent stick movement can start that receiver's run. If the original route becomes obstructed, change the physically achievable loft rather than silently choosing another teammate. If the recipient becomes ineligible or unreachable, avoid displaying a guaranteed pass to him.

**Plan an arrival, not just an initial speed.** Calculate the trajectory against actual gravity, ball contact heights and the receiver's likely movement. Test low delivery first, then a bounded higher arc. Account for the whole reachable contact region around an intervening defender, rather than just his centre. A marked landing remains a contest: assistance should not bypass an opponent who can physically head or collect the descending ball. A defender moving into the route after release can still intercept it.

**Let ability change useful limits.** Better distribution can add attainable range, pace and accuracy. Keep lower-rated keepers capable of routine uncontested outlets. Apply ability once to the solved launch, use bounded deterministic error, and avoid promoting a selected recipient beyond the keeper's actual reach. Preserve ordinary gravity, collisions and boundary ordering after release.

**Complete the handover.** Neutral input should bring the recipient towards the predicted ball path. Any deliberate stick input must control him immediately, including the same direction held during release. Validate collection followed by two seconds of possession, not merely a highlighted receiver or one contact frame. Queued next passes, backpass handling restrictions and cancellation must continue to work.

## Existing coverage and focused additions

The pre-Build 19 tests already protect manual blue-keeper control, autonomous red distribution, backpasses staying at the feet, cancellation requiring a fresh press, goal-kick clock pausing, and exact release counts. Keep those protections.

Three old expectations describe the behaviour being replaced: `KickMechanicsTests.testKeeperTapThrowsButHeldPuntsTravelFartherWithMorePower`, `KeeperHandlingRegressionTests.testKeeperPuntAcceptsLateralAftertouchWhileThrowStaysStraight`, and `KeeperPossessionTests.testShortHandThrowCannotSelectAnUnreachableDistantReceiver`. Update their intended behaviours, while retaining checks for finite bounded flights, appropriate post-release input, and genuinely unreachable targets.

The main integration matrix should cover close/far/blocked tap deliveries from hands and goal kicks, multiple abilities, changed receiver input, and acquire-plus-retain outcomes. Independent rule coverage should add:

1. A real long goal kick can select and reach a teammate beyond the defensive line under the existing restart exemption; an open-play keeper throw must not borrow that exemption.
2. A defender at the descending landing can physically intercept or head the ball. An obstacle-aware launch is not immunity from a contested reception.
3. Stronger keeper ability increases bounded long-distribution reach across multiple release timings, while very long holds saturate. Goal kicks retain a foot release and held hand distributions retain an overarm release.
4. Keep cancellation, original target identity, immediate receiver movement, foot backpasses, offside involvement, and one physical release per action in the full regression run.

Test outcomes and build evidence belong in the Build 19 implementation/playtest record; this research document does not certify a build.
