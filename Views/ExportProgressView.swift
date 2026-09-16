//
//  ExportProgressView.swift
//  MyPianoInstructor
//
//  Shared pieces of the video-export UI, used by the player and by the scan
//  preview so both flows look and behave the same.
//

import SwiftUI
import UIKit

/// Progress ring shown while a video renders.
struct ExportProgressSheet: View {
    let progress: Double
    var subtitle: String = "Rendering your performance at 1080p 60fps…"

    var body: some View {
        VStack(spacing: 20) {
            Text("Exporting Video")
                .font(.title2).bold()
                .padding(.top, 30)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AppTheme.accentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: progress)
                Text("\(Int(progress * 100))%")
                    .font(.title3).bold()
            }

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Keep Cascade open until the export finishes.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }
}

/// UIActivityViewController wrapper for sharing / saving an exported video.
struct VideoShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// URL does not conform to Identifiable by default; add it so we can use
/// `.sheet(item:)` with an exported file URL.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

enum ExportFileNaming {
    /// "Für Elise (Beethoven)" → "Fur-Elise-Beethoven.mp4"
    static func videoFileName(for title: String) -> String {
        let folded = title.folding(options: [.diacriticInsensitive], locale: .current)
        let allowed = CharacterSet.alphanumerics
        var out = ""
        var lastWasDash = false
        for scalar in folded.unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash && !out.isEmpty {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        let base = out.isEmpty ? "Cascade-Export" : String(out.prefix(60))
        return base + ".mp4"
    }
}
