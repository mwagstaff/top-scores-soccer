import SwiftUI

struct TuningView: View {
    @Bindable var session: GameSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Play is paused. Difficulty is saved for future matches; other tuning lasts for this session.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if session.configuration == nil {
                        Picker("Play mode", selection: $session.mode) {
                            ForEach([ExerciseMode.match, .passing, .solo], id: \.self) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .accessibilityIdentifier("settings.mode")
                        Text(session.mode.description)
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("\(session.modeTitle) · Two halves with added time")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Difficulty") {
                    Picker("Opposition", selection: $session.tuning.difficulty) {
                        ForEach(GameDifficulty.allCases, id: \.self) { difficulty in
                            Text(difficulty.title).tag(difficulty)
                        }
                    }
                    .accessibilityIdentifier("settings.difficulty")
                    Text(session.tuning.difficulty.description)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Movement") {
                    tuningSlider("Running speed", key: \.playerMaxSpeed, range: 6...15, unit: "m/s")
                    tuningSlider("Off-ball speed boost", key: \.offBallSpeedBoost, range: 1...1.3, unit: "×", precision: 2)
                    tuningSlider("Acceleration", key: \.playerAcceleration, range: 20...70, unit: "m/s²")
                    tuningSlider("Stopping strength", key: \.playerDeceleration, range: 12...55, unit: "m/s²")
                    tuningSlider("Turning speed", key: \.playerTurnRate, range: 5...22, unit: "rad/s")
                }
                Section("Ball and dribbling") {
                    tuningSlider("Control reach", key: \.controlAcquireDistance, range: 1.3...3.0, unit: "m")
                    tuningSlider("Rolling resistance", key: \.ballFriction, range: 2...9, unit: "m/s²")
                    tuningSlider("Time between touches", key: \.dribbleTouchInterval, range: 0.05...0.24, unit: "s", precision: 2)
                    tuningSlider("Dribble reach", key: \.dribbleReach, range: 1.5...2.7, unit: "m")
                    tuningSlider("Pass speed", key: \.passSpeed, range: 14...28, unit: "m/s")
                }
                if session.mode != .solo {
                    Section("Passing and defending") {
                        tuningSlider("Pass assistance angle", key: \.passAssistAngle, range: 15...85, unit: "°", precision: 0)
                        tuningSlider("Pass lead", key: \.passLead, range: 0...1.2, unit: "×", precision: 2)
                        tuningSlider("AI running speed", key: \.aiSpeedScale, range: 0.45...1.0, unit: "×", precision: 2)
                        tuningSlider("Running tackle reach", key: \.passiveControlReach, range: 1.3...2.3, unit: "m")
                    }
                }
                Section("Slides and first-time touches") {
                    Text("Aim and tap near a reachable high ball to head it. An early tap waits briefly for contact; holding in that situation keeps the header ready instead of sliding.")
                        .font(.footnote).foregroundStyle(.secondary)
                    tuningSlider("Slide recovery", key: \.slideRecovery, range: 0.5...1.5, unit: "s", precision: 2)
                    tuningSlider("Queued kick window", key: \.queuedPassDuration, range: 0.25...1.5, unit: "s", precision: 2)
                }
                Section("Shooting") {
                    Text("PASS always plays a short ball. The other button shoots inside shooting distance and plays a long ball outside it. Shots farther from goal need more power and have a narrower green band. Excess power reduces accuracy and can send the shot over the bar.")
                        .font(.footnote).foregroundStyle(.secondary)
                    tuningSlider("Shooting distance", key: \.shootingRange, range: 25...40, unit: "m", precision: 0)
                    tuningSlider("Time to full shot power", key: \.shotChargeDuration, range: 0.5...1.4, unit: "s", precision: 2)
                    tuningSlider("Maximum shot speed", key: \.shotMaxSpeed, range: 32...62, unit: "m/s")
                }
                Section("Aftertouch") {
                    Text("After shooting, steer sideways briefly to bend the ball. The influence fades in flight and cannot turn a badly aimed strike into an impossible curve.")
                        .font(.footnote).foregroundStyle(.secondary)
                    tuningSlider("Curve window", key: \.aftertouchDuration, range: 0.4...1.0, unit: "s", precision: 2)
                    tuningSlider("Curve strength", key: \.aftertouchStrength, range: 0.3...1.5, unit: "rad/s")
                    tuningSlider("Curve fade", key: \.aftertouchDecay, range: 1...4, unit: "")
                    tuningSlider("Maximum bend", key: \.aftertouchMaxAngle, range: 4...16, unit: "°", precision: 0)
                }
                Section("Chipping") {
                    tuningSlider("Pull-back window", key: \.chipWindowDuration, range: 0.12...0.4, unit: "s", precision: 2)
                    tuningSlider("Chip lift", key: \.chipLiftSpeed, range: 5...12, unit: "m/s")
                }
                Section("Camera and controls") {
                    tuningSlider("Camera response", key: \.cameraSmoothing, range: 4...16, unit: "1/s")
                    tuningSlider("Camera look ahead", key: \.cameraLookAhead, range: 0...0.55, unit: "s", precision: 2)
                    tuningSlider("Joystick dead zone", key: \.joystickDeadZone, range: 0.04...0.25, unit: "", precision: 2)
                }
                Section("Sound and haptics") {
                    Toggle("Referee whistle", isOn: $session.soundEnabled)
                        .accessibilityIdentifier("settings.sound")
                    Text("Plays for fouls, offside, half-time and full-time. Respects Silent Mode.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("Gameplay haptics", isOn: $session.hapticsEnabled)
                        .accessibilityIdentifier("settings.haptics")
                    Text("Feel kicks, headers and challenge impacts on supported devices.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Diagnostics") {
                    Toggle("Show gameplay overlay and vectors", isOn: $session.debugEnabled)
                        .accessibilityIdentifier("settings.debug")
                    if !session.isCareerMatch {
                        Button(session.mode == .match ? "Start a new match" : "Reset practice") { session.reset() }
                    }
                    if session.mode != .match { Button("Clear goal tally") { session.resetScore() } }
                    Button("Restore default tuning") { session.restoreDefaults() }
                        .accessibilityIdentifier("settings.defaults")
                }
                Section {
                    Text("\(session.modeTitle) · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "15")")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .tint(.blue)
            .navigationTitle("Tune the feel")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { session.showingSettings = false }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }

    private func tuningSlider(_ title: String, key: WritableKeyPath<GameplayTuning, Double>,
                              range: ClosedRange<Double>, unit: String, precision: Int = 1) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    tuningValue(key: key, unit: unit, precision: precision)
                }
            } else {
                HStack {
                    Text(title)
                    Spacer()
                    tuningValue(key: key, unit: unit, precision: precision)
                }
            }
            Slider(value: Binding(get: { session.tuning[keyPath: key] },
                                  set: { session.tuning[keyPath: key] = $0 }), in: range)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 3)
    }

    private func tuningValue(key: WritableKeyPath<GameplayTuning, Double>, unit: String, precision: Int) -> some View {
        Text(session.tuning[keyPath: key].formatted(.number.precision(.fractionLength(precision))) + " " + unit)
            .foregroundStyle(.secondary).monospacedDigit()
    }
}

#Preview("Gameplay tuning") {
    TuningView(session: GameSession())
}
