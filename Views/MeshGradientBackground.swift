//
//  MeshGradientBackground.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 2/17/26.
//

import SwiftUI

/// An animated MeshGradient background for hero sections.
/// Uses iOS 18's MeshGradient API with a fallback LinearGradient for iOS 17.
struct MeshGradientCard: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        if #available(iOS 18.0, *) {
            MeshGradient(
                width: 3,
                height: 2,
                points: [
                    SIMD2(0.0, 0.0), SIMD2(0.5, 0.0), SIMD2(1.0, 0.0),
                    SIMD2(0.0, 1.0), SIMD2(0.5 + 0.1 * Float(sin(phase * .pi)), 1.0), SIMD2(1.0, 1.0)
                ],
                colors: [
                    .indigo, Color(red: 0.4, green: 0.2, blue: 0.7), .purple,
                    Color(red: 0.3, green: 0.15, blue: 0.5), Color(red: 0.5, green: 0.25, blue: 0.7), .indigo
                ]
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
        } else {
            LinearGradient(
                colors: [Color.indigo.opacity(0.8), Color.purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

/// Full-screen animated mesh gradient for onboarding backgrounds
struct MeshGradientBackground: View {
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        if #available(iOS 18.0, *) {
            let drift: Float = 0.08
            let phase = Float(animationPhase)
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2(0.0, 0.0), SIMD2(0.5, 0.0), SIMD2(1.0, 0.0),
                    SIMD2(0.0, 0.5 + drift * sin(phase * .pi)),
                    SIMD2(0.5 + drift * cos(phase * .pi), 0.5 + drift * sin(phase * .pi * 1.5)),
                    SIMD2(1.0, 0.5 - drift * sin(phase * .pi)),
                    SIMD2(0.0, 1.0), SIMD2(0.5, 1.0), SIMD2(1.0, 1.0)
                ],
                colors: [
                    Color(red: 0.15, green: 0.1, blue: 0.35),
                    Color(red: 0.25, green: 0.15, blue: 0.45),
                    Color(red: 0.2, green: 0.1, blue: 0.4),
                    Color(red: 0.3, green: 0.15, blue: 0.5),
                    Color(red: 0.35, green: 0.2, blue: 0.55),
                    Color(red: 0.25, green: 0.1, blue: 0.45),
                    Color(red: 0.2, green: 0.12, blue: 0.4),
                    Color(red: 0.3, green: 0.18, blue: 0.5),
                    Color(red: 0.15, green: 0.1, blue: 0.35)
                ]
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    animationPhase = 1
                }
            }
        } else {
            LinearGradient(
                colors: [Color.indigo, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}
