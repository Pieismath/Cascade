//
//  ThemePickerView.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/15/26.
//

import SwiftUI

struct ThemePickerView: View {
    @Environment(ThemeManager.self) var themeManager

    // For explosion preview animation
    @State private var previewExplosions: [PreviewExplosion] = []
    @State private var previewTimer: Timer? = nil

    var body: some View {
        @Bindable var themeManager = themeManager
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                Text("Customize Theme")
                    .font(.title).bold()
                    .padding(.top)

                Text("Choose how your falling notes look! Each theme changes the colors of notes, keyboard highlights, and particle effects.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // MARK: - Theme Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(NoteColorTheme.allCases) { theme in
                        themeCard(theme)
                    }
                }

                // MARK: - Custom Color Pickers (shown when Custom theme selected)
                if themeManager.selectedTheme == .custom {
                    customColorSection
                }

                // MARK: - Settings
                VStack(alignment: .leading, spacing: 14) {
                    Text("Effects")
                        .font(.headline)

                    Toggle(isOn: $themeManager.showNoteExplosions) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Note Explosions")
                                    .font(.subheadline).bold()
                                Text("Sparkle effects when notes reach the keyboard")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(AppTheme.accent)
                }
                .padding()
                .background(AppTheme.cardBackground)
                .cornerRadius(14)

                // MARK: - Preview
                VStack(alignment: .leading, spacing: 10) {
                    Text("Preview")
                        .font(.headline)

                    themePreview
                        .frame(height: 160)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(14)
                        .clipped()
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startPreviewExplosions() }
        .onDisappear { stopPreviewExplosions() }
    }

    // MARK: - Custom Color Section

    private var customColorSection: some View {
        @Bindable var themeManager = themeManager
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "eyedropper.full")
                    .foregroundColor(.purple)
                Text("Custom Colors")
                    .font(.headline)
            }

            Text("Pick any color from the color wheel for each note type.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Right Hand color picker
            HStack {
                Circle()
                    .fill(themeManager.customRightHand)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Right Hand Notes")
                        .font(.subheadline).bold()
                    Text("Treble/melody notes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                ColorPicker("", selection: $themeManager.customRightHand, supportsOpacity: false)
                    .labelsHidden()
            }
            .padding(.vertical, 4)

            Divider()

            // Left Hand color picker
            HStack {
                Circle()
                    .fill(themeManager.customLeftHand)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Left Hand Notes")
                        .font(.subheadline).bold()
                    Text("Bass/accompaniment notes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                ColorPicker("", selection: $themeManager.customLeftHand, supportsOpacity: false)
                    .labelsHidden()
            }
            .padding(.vertical, 4)

            Divider()

            // Black Key color picker
            HStack {
                Circle()
                    .fill(themeManager.customBlackKey)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Black Key Notes")
                        .font(.subheadline).bold()
                    Text("Sharp/flat notes")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                ColorPicker("", selection: $themeManager.customBlackKey, supportsOpacity: false)
                    .labelsHidden()
            }
            .padding(.vertical, 4)
        }
        .padding()
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Theme Card

    private func themeCard(_ theme: NoteColorTheme) -> some View {
        let isSelected = themeManager.selectedTheme == theme

        // For custom theme, show actual custom colors in preview
        let previewColors: [Color]
        if theme == .custom {
            previewColors = [themeManager.customRightHand, themeManager.customLeftHand, themeManager.customBlackKey]
        } else {
            previewColors = theme.previewColors
        }

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                themeManager.selectedTheme = theme
            }
        } label: {
            VStack(spacing: 10) {
                // Color preview dots
                HStack(spacing: 6) {
                    ForEach(previewColors.indices, id: \.self) { i in
                        Circle()
                            .fill(previewColors[i])
                            .frame(width: 20, height: 20)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: theme.icon)
                        .font(.caption)
                    Text(theme.rawValue)
                        .font(.caption).bold()
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(AppTheme.accent)
                } else {
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.3))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isSelected ? AppTheme.accent.opacity(0.08) : AppTheme.cardBackground)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? AppTheme.accent : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.rawValue) theme\(isSelected ? ", selected" : "")")
    }

    // MARK: - Theme Preview with Explosions

    private var themePreview: some View {
        let rhColor = themeManager.effectiveRightHand
        let lhColor = themeManager.effectiveLeftHand
        let bkColor = themeManager.effectiveBlackKey

        return TimelineView(.animation(minimumInterval: 1.0/30.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                // ---- FALLING NOTES ----
                let noteData: [(x: Double, speed: Double, isBlack: Bool, isLeft: Bool)] = [
                    (0.12, 40, false, false),
                    (0.25, 55, true, false),
                    (0.38, 35, false, false),
                    (0.50, 48, false, true),
                    (0.62, 42, true, true),
                    (0.75, 58, false, true),
                    (0.88, 37, false, false),
                ]

                for note in noteData {
                    let y = (time * note.speed).truncatingRemainder(dividingBy: Double(size.height + 30)) - 15
                    let x = note.x * size.width
                    let w: CGFloat = note.isBlack ? 12 : 18
                    let h: CGFloat = 30

                    let color: Color
                    if note.isBlack {
                        color = bkColor
                    } else if note.isLeft {
                        color = lhColor
                    } else {
                        color = rhColor
                    }

                    let rect = CGRect(x: x - w/2, y: y, width: w, height: h)
                    let path = Path(roundedRect: rect, cornerRadius: 4)
                    context.fill(path, with: .color(color.opacity(0.85)))
                }

                // ---- KEYBOARD LINE ----
                let lineY = size.height - 4
                let lineRect = CGRect(x: 0, y: lineY, width: size.width, height: 2)
                context.fill(Path(lineRect), with: .color(Color.white.opacity(0.2)))

                // ---- EXPLOSION PARTICLES (only if enabled) ----
                if themeManager.showNoteExplosions {
                    for explosion in previewExplosions {
                        let age = time - explosion.startTime
                        guard age >= 0 && age < explosion.lifetime else { continue }

                        let progress = age / explosion.lifetime

                        for particle in explosion.particles {
                            let opacity = (1.0 - progress) * particle.opacity
                            let spread = CGFloat(age) * particle.speed
                            let px = explosion.x * size.width + Foundation.cos(particle.angle) * spread
                            let py = (size.height - 8) + Foundation.sin(particle.angle) * spread - CGFloat(age * 25)
                            let pSize = particle.size * CGFloat(1.0 - progress * 0.6)

                            let pRect = CGRect(x: px - pSize/2, y: py - pSize/2, width: pSize, height: pSize)
                            let pPath: Path
                            if particle.isCircle {
                                pPath = Path(ellipseIn: pRect)
                            } else {
                                pPath = Path(roundedRect: pRect, cornerRadius: 1)
                            }
                            context.opacity = opacity
                            context.fill(pPath, with: .color(explosion.color))
                            context.opacity = 1.0
                        }
                    }
                }
            }
        }
    }

    // MARK: - Preview Explosion Management

    private func startPreviewExplosions() {
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            spawnPreviewExplosion()
            cleanupPreviewExplosions()
        }
    }

    private func stopPreviewExplosions() {
        previewTimer?.invalidate()
        previewTimer = nil
    }

    private func spawnPreviewExplosion() {
        guard themeManager.showNoteExplosions else {
            previewExplosions.removeAll()
            return
        }

        let xPositions: [Double] = [0.12, 0.25, 0.38, 0.50, 0.62, 0.75, 0.88]
        let randomX = xPositions.randomElement() ?? 0.5

        let colors = [themeManager.effectiveRightHand, themeManager.effectiveLeftHand, themeManager.effectiveBlackKey]
        let color = colors.randomElement() ?? .cyan

        var particles: [PreviewParticle] = []
        let count = Int.random(in: 6...10)
        for _ in 0..<count {
            particles.append(PreviewParticle(
                angle: CGFloat.random(in: -CGFloat.pi...CGFloat.pi),
                speed: CGFloat.random(in: 25...60),
                size: CGFloat.random(in: 2...5),
                opacity: Double.random(in: 0.5...1.0),
                isCircle: Bool.random()
            ))
        }

        previewExplosions.append(PreviewExplosion(
            startTime: Date.timeIntervalSinceReferenceDate,
            lifetime: 0.6,
            x: randomX,
            color: color,
            particles: particles
        ))
    }

    private func cleanupPreviewExplosions() {
        let now = Date.timeIntervalSinceReferenceDate
        previewExplosions.removeAll { now - $0.startTime > $0.lifetime + 0.1 }
    }
}

// MARK: - Preview Explosion Data Types

private struct PreviewExplosion {
    let startTime: TimeInterval
    let lifetime: TimeInterval
    let x: Double         // normalized 0...1
    let color: Color
    let particles: [PreviewParticle]
}

private struct PreviewParticle {
    let angle: CGFloat
    let speed: CGFloat
    let size: CGFloat
    let opacity: Double
    let isCircle: Bool
}
