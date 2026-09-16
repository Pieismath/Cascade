//
//  CelebrationView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/15/26.
//

import SwiftUI

/// A full-screen confetti/sparkle celebration overlay
/// Shown when earning achievements or completing songs
struct CelebrationOverlay: View {
    let achievement: Achievement?
    let onDismiss: () -> Void

    @State private var particles: [ConfettiParticle] = []
    @State private var showContent = false
    @State private var timer: Timer? = nil
    @State private var screenWidth: Double = 400

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Confetti Canvas
            GeometryReader { geo in
                Color.clear.onAppear { screenWidth = geo.size.width }
            }
            .ignoresSafeArea()

            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    for particle in particles {
                        let age = now - particle.startTime
                        guard age >= 0 && age < particle.lifetime else { continue }

                        let progress = age / particle.lifetime
                        let opacity = 1.0 - progress

                        let x = particle.startX + particle.velocityX * age + sin(age * particle.wobbleFreq) * particle.wobbleAmp
                        let y = particle.startY + particle.velocityY * age + 0.5 * 200 * age * age // gravity

                        let rotation = Angle.degrees(age * particle.rotationSpeed)
                        let size = particle.size * (1.0 - progress * 0.3)

                        var ctx = context
                        ctx.opacity = opacity
                        ctx.translateBy(x: x, y: y)
                        ctx.rotate(by: rotation)

                        let rect = CGRect(x: -size/2, y: -size/2, width: size, height: size)

                        switch particle.shape {
                        case .circle:
                            ctx.fill(Path(ellipseIn: rect), with: .color(particle.color))
                        case .square:
                            ctx.fill(Path(rect), with: .color(particle.color))
                        case .star:
                            ctx.fill(starPath(in: rect), with: .color(particle.color))
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Achievement card
            if let achievement, showContent {
                VStack(spacing: 20) {
                    // Glowing icon
                    ZStack {
                        Circle()
                            .fill(achievementColor(achievement).opacity(0.2))
                            .frame(width: 100, height: 100)
                            .blur(radius: 10)

                        Circle()
                            .fill(achievementColor(achievement).opacity(0.3))
                            .frame(width: 80, height: 80)

                        Image(systemName: achievement.icon)
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }

                    Text("Achievement Unlocked!")
                        .font(.caption).bold()
                        .foregroundColor(.white.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(2)

                    Text(achievement.title)
                        .font(.title).bold()
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)

                    Text(achievement.description)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)

                    Button {
                        dismiss()
                    } label: {
                        Text("Awesome!")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 12)
                            .background(achievementColor(achievement))
                            .cornerRadius(25)
                    }
                    .padding(.top, 8)
                }
                .padding(30)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            spawnConfetti()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showContent = true
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Achievement unlocked: \(achievement?.title ?? "")")
        .accessibilityAddTraits(.isModal)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            showContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    private func spawnConfetti() {
        let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]
        let now = Date.timeIntervalSinceReferenceDate
        let width = screenWidth

        // Initial burst
        for _ in 0..<60 {
            particles.append(ConfettiParticle(
                startTime: now + Double.random(in: 0...0.3),
                lifetime: Double.random(in: 2.0...4.0),
                startX: Double.random(in: 0...width),
                startY: Double.random(in: -50...0),
                velocityX: Double.random(in: -50...50),
                velocityY: Double.random(in: 20...80),
                rotationSpeed: Double.random(in: -360...360),
                wobbleFreq: Double.random(in: 2...6),
                wobbleAmp: Double.random(in: 5...20),
                size: Double.random(in: 6...14),
                color: colors.randomElement()!,
                shape: ConfettiShape.allCases.randomElement()!
            ))
        }

        // Continuous gentle confetti for 3 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { t in
            let elapsed = Date.timeIntervalSinceReferenceDate - now
            if elapsed > 3.0 {
                t.invalidate()
                return
            }

            for _ in 0..<3 {
                particles.append(ConfettiParticle(
                    startTime: Date.timeIntervalSinceReferenceDate,
                    lifetime: Double.random(in: 2.0...3.5),
                    startX: Double.random(in: 0...width),
                    startY: -20,
                    velocityX: Double.random(in: -30...30),
                    velocityY: Double.random(in: 30...60),
                    rotationSpeed: Double.random(in: -200...200),
                    wobbleFreq: Double.random(in: 2...5),
                    wobbleAmp: Double.random(in: 5...15),
                    size: Double.random(in: 5...10),
                    color: colors.randomElement()!,
                    shape: ConfettiShape.allCases.randomElement()!
                ))
            }
        }
    }

    private func starPath(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = rect.width / 2
        let innerRadius = outerRadius * 0.4
        var path = Path()

        for i in 0..<10 {
            let angle = Angle.degrees(Double(i) * 36 - 90)
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + Foundation.cos(angle.radians) * radius,
                y: center.y + Foundation.sin(angle.radians) * radius
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func achievementColor(_ achievement: Achievement) -> Color {
        switch achievement.category {
        case .practice:   return .indigo
        case .mastery:    return .orange
        case .dedication: return .green
        case .explorer:   return .purple
        }
    }
}

// MARK: - Confetti Data

private struct ConfettiParticle {
    let startTime: TimeInterval
    let lifetime: TimeInterval
    let startX: Double
    let startY: Double
    let velocityX: Double
    let velocityY: Double
    let rotationSpeed: Double
    let wobbleFreq: Double
    let wobbleAmp: Double
    let size: Double
    let color: Color
    let shape: ConfettiShape
}

private enum ConfettiShape: CaseIterable {
    case circle, square, star
}

