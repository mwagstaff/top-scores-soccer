import AVFAudio
import SwiftUI
import UIKit

@MainActor
final class CelebrationAudioPlayer {
    private var player: AVAudioPlayer?

    func play() {
        guard let url = Bundle.main.url(forResource: "world-cup-cheer", withExtension: "wav") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.65
            player.numberOfLoops = 0
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

struct WorldCupCelebrationView: View {
    let teamName: String
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var gleam = false
    @State private var audio: CelebrationAudioPlayer?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.01, green: 0.08, blue: 0.08),
                                    Color(red: 0.03, green: 0.19, blue: 0.14), .black],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            GoldenTickerTape(animated: !reduceMotion).ignoresSafeArea().accessibilityHidden(true)
            RadialGradient(colors: [Color.yellow.opacity(0.30), .clear], center: .center,
                           startRadius: 20, endRadius: 260).accessibilityHidden(true)

            ScrollView {
                VStack(spacing: 18) {
                    Spacer(minLength: 42)
                    Text("WORLD CHAMPIONS")
                        .font(.system(.title3, design: .rounded, weight: .black)).tracking(3.5)
                        .foregroundStyle(Color(red: 1, green: 0.84, blue: 0.28))
                    Text(teamName)
                        .font(.system(.largeTitle, design: .rounded, weight: .black))
                        .multilineTextAlignment(.center).foregroundStyle(.white)
                        .accessibilityIdentifier("worldcup.celebration.team")

                    trophy
                        .frame(width: 210, height: 300)
                        .scaleEffect(reduceMotion ? 1 : appeared ? 1 : 0.35)
                        .offset(y: reduceMotion ? 0 : appeared ? 0 : 90)
                        .opacity(appeared ? 1 : 0)
                        .shadow(color: .yellow.opacity(0.52), radius: appeared ? 30 : 5)

                    Text("Champions of the world")
                        .font(.title2.bold()).foregroundStyle(.white)
                    Text("Eight matches. One unforgettable finish.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75))

                    Button("Continue") { stopAndContinue() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.94, green: 0.74, blue: 0.18)).foregroundStyle(.black)
                        .controlSize(.large).accessibilityIdentifier("worldcup.celebration.continue")
                    Spacer(minLength: 32)
                }
                .frame(maxWidth: 600).padding(.horizontal, 26).frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .accessibilityElement(children: .contain)
        .onAppear(perform: begin)
        .onDisappear { audio?.stop() }
    }

    private var trophy: some View {
        ZStack {
            TrophySilhouette()
                .fill(LinearGradient(colors: [Color(red: 0.58, green: 0.34, blue: 0.04),
                                              Color(red: 1, green: 0.88, blue: 0.36),
                                              Color(red: 0.72, green: 0.43, blue: 0.05)],
                                     startPoint: .leading, endPoint: .trailing))
            TrophySilhouette()
                .stroke(Color.yellow.opacity(0.8), lineWidth: 2)
            if !reduceMotion {
                LinearGradient(colors: [.clear, .white.opacity(0.05), .white.opacity(0.95), .white.opacity(0.05), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 52).rotationEffect(.degrees(16))
                    .offset(x: gleam ? 150 : -150)
                    .mask(TrophySilhouette())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gleaming gold World Cup trophy")
    }

    private func begin() {
        appeared = reduceMotion
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.72)) {
            appeared = true
        }
        if !reduceMotion {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false).delay(0.45)) { gleam = true }
        }
        let player = CelebrationAudioPlayer()
        player.play()
        audio = player
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "\(teamName) are world champions")
    }

    private func stopAndContinue() {
        audio?.stop()
        onContinue()
    }
}

private struct TrophySilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.addEllipse(in: CGRect(x: w * 0.25, y: h * 0.015, width: w * 0.50, height: h * 0.30))
        path.move(to: CGPoint(x: w * 0.37, y: h * 0.20))
        path.addCurve(to: CGPoint(x: w * 0.30, y: h * 0.49),
                      control1: CGPoint(x: w * 0.23, y: h * 0.27), control2: CGPoint(x: w * 0.23, y: h * 0.42))
        path.addCurve(to: CGPoint(x: w * 0.42, y: h * 0.71),
                      control1: CGPoint(x: w * 0.35, y: h * 0.58), control2: CGPoint(x: w * 0.38, y: h * 0.65))
        path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.71))
        path.addCurve(to: CGPoint(x: w * 0.70, y: h * 0.49),
                      control1: CGPoint(x: w * 0.62, y: h * 0.65), control2: CGPoint(x: w * 0.65, y: h * 0.58))
        path.addCurve(to: CGPoint(x: w * 0.63, y: h * 0.20),
                      control1: CGPoint(x: w * 0.77, y: h * 0.42), control2: CGPoint(x: w * 0.77, y: h * 0.27))
        path.closeSubpath()
        path.addRoundedRect(in: CGRect(x: w * 0.34, y: h * 0.69, width: w * 0.32, height: h * 0.12), cornerSize: .init(width: 8, height: 8))
        path.addRoundedRect(in: CGRect(x: w * 0.24, y: h * 0.79, width: w * 0.52, height: h * 0.10), cornerSize: .init(width: 8, height: 8))
        path.addRoundedRect(in: CGRect(x: w * 0.18, y: h * 0.88, width: w * 0.64, height: h * 0.09), cornerSize: .init(width: 8, height: 8))
        return path
    }
}

private struct GoldenTickerTape: View {
    let animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: animated ? 1.0 / 30.0 : 10)) { timeline in
            Canvas { context, size in
                let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                for index in 0..<76 {
                    let seed = Double((index * 73) % 101) / 101
                    let x = (seed * size.width + sin(Double(index) * 1.7 + time) * 22).truncatingRemainder(dividingBy: size.width + 20)
                    let speed = 34 + Double((index * 17) % 54)
                    let start = Double((index * 113) % 700) / 700 * (size.height + 140) - 100
                    let y = animated ? (start + time.truncatingRemainder(dividingBy: 20) * speed).truncatingRemainder(dividingBy: size.height + 140) - 70 : start
                    let width = CGFloat(3 + (index % 4)), height = CGFloat(12 + (index % 5) * 3)
                    let rect = CGRect(x: CGFloat(x), y: CGFloat(y), width: width, height: height)
                    let color = index.isMultiple(of: 3) ? Color(red: 1, green: 0.88, blue: 0.30)
                        : index.isMultiple(of: 2) ? Color(red: 0.92, green: 0.64, blue: 0.12)
                        : Color(red: 0.72, green: 0.43, blue: 0.05)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color.opacity(0.86)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview("World Cup celebration") {
    WorldCupCelebrationView(teamName: "England", onContinue: {})
}
