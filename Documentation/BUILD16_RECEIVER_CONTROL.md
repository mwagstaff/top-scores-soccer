# Build 16: immediate receiver control

**Build 16 is installed and launched on the connected iPhone.**

## What changed

An assisted pass already selected its receiver immediately, but build 15 replaced the held passing direction with automatic movement until the joystick moved far enough. It also treated small processed movements as neutral. Both restrictions have been removed.

- Every active joystick direction now controls the selected receiver on the next simulation tick, including the exact direction held through the pass. Normal acceleration and momentum remain.
- Centre or release the stick to let him meet the physical ball trajectory. Manual input takes over immediately whenever it returns.
- A nearby pass that slows down or runs slightly past him is chased while he remains the intended receiver.
- A keeper receiving a backpass gets the same neutral assistance and immediate steering, retaining his weaker foot skills, handling restrictions and catch recovery.
- Pass selection, first-touch cushioning, queued kicks, chips and shot aftertouch retain their existing rules. A deliberate quick pullback can still chip a pass while moving its receiver.

## Checks and delivery

The focused simulation package passed 65 retained passing/receiver/selection/queued-action checks. Eight new movement-priority checks passed independently, covering inherited aim, small inputs, immediate reversal, neutral physical interception, through-ball running, slow or overshot passes and keeper backpasses. Two new native scene/input checks exercise a floating joystick held through the pass and a drag just beyond the actual touch dead zone.

The combined iPhone run passed **410 gameplay/core/native tests and all five selected UI checks**, including floating-joystick movement, passing, keeper backpass steering, catch/distribution and held throw-ins. The result bundle is `.test-artifacts/Build16ReceiverControl.xcresult`; the run exited successfully. The separate World Cup test class was explicitly excluded from this gameplay run; its previously recorded extra-time fixture issue and competition validation remain in that task's record.

The signed app built successfully, passed strict signature verification, and was installed and launched at **12:02 on 7 September 2026**. The installed-app query confirms version **0.1.0, build 16** on the connected iPhone 16 Pro Max running iOS 26.6.1. Device evidence is in `.test-artifacts/Build16DeviceInstall.json`, `Build16DeviceLaunch.json` and `Build16InstalledApp.json`; the build log is `.test-artifacts-build16-device.log`. Installation retained app data. The owned phone simulator was shut down after the run. Physical passing feel remains for the user to assess on the device.

## Try on the phone

1. Aim at a teammate, pass, and keep the stick held in exactly the same direction. His selection ring and movement should respond immediately while the ball is travelling.
2. Move the stick gently sideways, then reverse. Neither movement should need a large swipe or wait for the ball to arrive.
3. Centre or release the stick after a pass to a moving teammate. He should move to meet it; steer again at any point to take over.
4. Repeat with a through ball and a backpass to the keeper, then queue a quick return pass before contact.
