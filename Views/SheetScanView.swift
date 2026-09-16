//
//  SheetScanView.swift
//  MyPianoInstructor
//
//  The scan-to-play flow: capture sheet music with the document camera or
//  import a PDF/images, send the pages through optical music recognition,
//  preview the transcription, and save it to the library as a normal song.
//

import SwiftUI
import VisionKit
import PDFKit
import UniformTypeIdentifiers
import AuthenticationServices

struct SheetScanView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedSong: Song?
    @Binding var tabSelection: Int

    private enum Phase {
        case collectingPages
        case recognizing
        case preview(RecognizedScore)
    }

    @State private var phase: Phase = .collectingPages
    @State private var pages: [UIImage] = []
    @State private var songTitle = ""

    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showSettings = false
    @State private var errorMessage: String? = nil
    @State private var recognitionTask: Task<Void, Never>? = nil

    @State private var settings = ScanSettings.shared
    @State private var account = ScanAccountManager()

    private var cameraAvailable: Bool {
        VNDocumentCameraViewController.isSupported
    }

    private var cloudConfigured: Bool {
        ScanCloudConfig.baseURL != nil
    }

    /// Cloud mode (signed in, scans left) or BYOK — either unlocks Convert.
    /// A signed-in user who runs dry falls back to their own key if they set one.
    private var canRecognize: Bool {
        if cloudConfigured && account.isSignedIn && (account.remainingScans ?? 1) > 0 {
            return true
        }
        return settings.hasAPIKey
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .collectingPages:
                    collectPagesView
                case .recognizing:
                    recognizingView
                case .preview(let score):
                    ScanPreviewView(
                        score: score,
                        songTitle: $songTitle,
                        onSave: { save(score) },
                        onRetry: {
                            phase = .collectingPages
                        }
                    )
                }
            }
            .navigationTitle("Scan Sheet Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        recognitionTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Scan settings")
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView { scannedPages in
                pages.append(contentsOf: scannedPages)
            }
            .ignoresSafeArea()
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result)
        }
        .sheet(isPresented: $showSettings) {
            ScanSettingsView(account: account)
        }
        .task {
            await account.refresh()
        }
        .alert("Scanning Problem", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Phase 1: Collect Pages

    private var collectPagesView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                Text("Photograph printed sheet music or import a PDF, and Cascade turns it into a falling-note lesson.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if cloudConfigured {
                    if !account.isSignedIn {
                        signInCard
                    } else if account.remainingScans == 0 {
                        outOfScansCard
                    } else {
                        scansRemainingPill
                    }
                } else if !settings.hasAPIKey {
                    apiKeyPrompt
                }

                // Source buttons
                VStack(spacing: 10) {
                    sourceButton(
                        icon: "camera.viewfinder",
                        title: "Scan with Camera",
                        subtitle: cameraAvailable
                            ? "Auto-crops and straightens each page"
                            : "Not available on this device",
                        disabled: !cameraAvailable
                    ) {
                        showCamera = true
                    }

                    sourceButton(
                        icon: "doc.richtext",
                        title: "Import PDF or Images",
                        subtitle: "PDF pages are converted automatically",
                        disabled: false
                    ) {
                        showFileImporter = true
                    }
                }

                // Page thumbnails
                if !pages.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("\(pages.count) page\(pages.count == 1 ? "" : "s") ready")
                                .font(.headline)
                            Spacer()
                            Button("Clear All", role: .destructive) {
                                pages.removeAll()
                            }
                            .font(.caption)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(pages.indices, id: \.self) { i in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: pages[i])
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 130)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                            )
                                        Button {
                                            pages.remove(at: i)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                        .padding(4)
                                        .accessibilityLabel("Remove page \(i + 1)")
                                    }
                                }
                            }
                        }

                        if pages.count > ClaudeSheetMusicRecognizer.maxPagesPerRequest {
                            Label(
                                "Long pieces may come back incomplete. For best results scan up to \(ClaudeSheetMusicRecognizer.maxPagesPerRequest) pages at a time.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.caption)
                            .foregroundColor(.orange)
                        }
                    }
                    .padding(.top, 4)

                    // Recognize button
                    Button {
                        startRecognition()
                    } label: {
                        Label("Convert to Falling Notes", systemImage: "wand.and.stars")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canRecognize ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(Color.gray))
                            .cornerRadius(14)
                    }
                    .disabled(!canRecognize)
                }

                Spacer(minLength: 30)
            }
            .padding()
        }
    }

    // MARK: - Cloud account cards

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Get \(account.freeScans ?? 5) free scans", systemImage: "sparkles")
                .font(.subheadline).bold()
            Text("Sign in and your free scans follow your account — no setup, no API key.")
                .font(.caption)
                .foregroundColor(.secondary)
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = []   // identity only — no name or email
            } onCompletion: { result in
                Task {
                    switch result {
                    case .success(let authorization):
                        do {
                            try await account.signIn(with: authorization)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    case .failure(let error):
                        // User-cancelled sign-in isn't an error worth showing
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 46)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.08))
        .cornerRadius(12)
    }

    private var scansRemainingPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
            Text("Signed in — \(account.remainingScans.map(String.init) ?? "…") free scan\(account.remainingScans == 1 ? "" : "s") left")
                .font(.caption).bold()
            Spacer()
        }
        .padding(10)
        .background(Color.green.opacity(0.1))
        .cornerRadius(10)
    }

    private var outOfScansCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hourglass")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("You've used all your free scans")
                    .font(.subheadline).bold()
                Text("More scan options are coming soon. Power users can add their own API key under scan settings → Advanced.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private var apiKeyPrompt: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Add your Anthropic API key to enable scanning")
                    .font(.subheadline).bold()
                Text("Recognition runs on the Claude vision API. Your key is stored securely in the Keychain and used only for your own scans.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Enter API Key…") { showSettings = true }
                    .font(.caption).bold()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    private func sourceButton(icon: String, title: String, subtitle: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(AppTheme.cardBackground)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    // MARK: - Phase 2: Recognizing

    private var recognizingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Reading the notation…")
                .font(.headline)
            Text("Transcribing \(pages.count) page\(pages.count == 1 ? "" : "s") of sheet music into playable notes. This usually takes under a minute.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Cancel") {
                recognitionTask?.cancel()
                phase = .collectingPages
            }
            .padding(.top, 10)
            Spacer()
        }
    }

    // MARK: - File Import (PDF + images)

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            if case .failure(let error) = result { errorMessage = "Import failed: \(error.localizedDescription)" }
            return
        }

        for url in urls {
            let gotAccess = url.startAccessingSecurityScopedResource()
            defer { if gotAccess { url.stopAccessingSecurityScopedResource() } }

            if url.pathExtension.lowercased() == "pdf" {
                guard let document = PDFDocument(url: url) else {
                    errorMessage = "Could not open the PDF."
                    continue
                }
                for pageIndex in 0..<document.pageCount {
                    guard let page = document.page(at: pageIndex) else { continue }
                    let bounds = page.bounds(for: .mediaBox)
                    let longest = max(bounds.width, bounds.height)
                    let scale = longest > 0 ? SheetPagePrep.maxDimension / longest : 1
                    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                    pages.append(page.thumbnail(of: size, for: .mediaBox))
                }
            } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                pages.append(image)
            } else {
                errorMessage = "Could not read \(url.lastPathComponent)."
            }
        }
    }

    // MARK: - Recognition

    /// Cloud recognizer when signed in with scans left; otherwise the user's
    /// own key. `quality` only matters on the cloud path.
    private func makeRecognizer(quality: String) -> SheetMusicRecognizer? {
        if let baseURL = ScanCloudConfig.baseURL,
           account.isSignedIn,
           let token = account.sessionToken,
           (account.remainingScans ?? 1) > 0 {
            return CascadeCloudRecognizer(baseURL: baseURL, sessionToken: token, quality: quality)
        }
        if settings.hasAPIKey {
            return settings.makeRecognizer()
        }
        return nil
    }

    private func recognizeAndValidate(_ recognizer: SheetMusicRecognizer, pages: [Data]) async throws -> RecognizedScore {
        let musicXML = try await recognizer.recognize(pages: pages)
        try Task.checkCancellation()
        return try SheetMusicValidator.validate(musicXML: musicXML)
    }

    private func startRecognition() {
        let jpegs = pages.compactMap { SheetPagePrep.jpegData(from: $0) }
        guard jpegs.count == pages.count else {
            errorMessage = SheetMusicRecognitionError.imageEncodingFailed.localizedDescription
            return
        }
        guard let recognizer = makeRecognizer(quality: "standard") else {
            errorMessage = cloudConfigured
                ? "Sign in to scan, or add your own API key in scan settings."
                : SheetMusicRecognitionError.missingAPIKey.localizedDescription
            return
        }

        let usingCloud = recognizer is CascadeCloudRecognizer
        phase = .recognizing

        recognitionTask = Task {
            do {
                var score: RecognizedScore
                do {
                    score = try await recognizeAndValidate(recognizer, pages: jpegs)
                } catch let err as SheetMusicRecognitionError where usingCloud && err.isEscalatable {
                    // Standard pass produced unusable notation — one retry on
                    // the stronger model before giving up.
                    guard let retry = makeRecognizer(quality: "high") else { throw err }
                    score = try await recognizeAndValidate(retry, pages: jpegs)
                }

                if songTitle.isEmpty {
                    songTitle = "Scanned Music \(Date().formatted(date: .abbreviated, time: .omitted))"
                }
                phase = .preview(score)
                if usingCloud { await account.refresh() }
            } catch is CancellationError {
                // User backed out — no error surface needed
            } catch ScanCloudError.sessionExpired {
                account.signOut()
                phase = .collectingPages
                errorMessage = ScanCloudError.sessionExpired.localizedDescription
            } catch {
                phase = .collectingPages
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save(_ score: RecognizedScore) {
        let title = songTitle.trimmingCharacters(in: .whitespaces)
        let newSong = libraryVM.addSong(
            title: title.isEmpty ? "Scanned Music" : title,
            musicXML: score.musicXML
        )
        selectedSong = newSong
        dismiss()
        tabSelection = 2
    }
}

// MARK: - Preview Phase View

private struct ScanPreviewView: View {
    let score: RecognizedScore
    @Binding var songTitle: String
    let onSave: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Transcription ready — check that it looks right", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundColor(.green)

                // Stats
                HStack(spacing: 10) {
                    previewStat("\(score.playback.notes.count)", "Notes")
                    previewStat(formatDuration(score.playback.totalDuration), "Duration")
                    previewStat("\(Int(score.playback.tempo))", "BPM")
                    previewStat("\(score.playback.pedalEvents.count)", "Pedals")
                }

                // Note preview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note Preview")
                        .font(.headline)
                    notePreview
                        .frame(height: 110)
                        .background(Color.black.opacity(0.85))
                        .cornerRadius(12)
                }

                // Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Song title")
                        .font(.subheadline).bold()
                    TextField("Enter song title", text: $songTitle)
                        .textFieldStyle(.roundedBorder)
                }

                // Actions
                Button(action: onSave) {
                    Label("Add to Library & Play", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppTheme.accentGradient)
                        .cornerRadius(14)
                }

                Button(action: onRetry) {
                    Label("Scan Again", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Text("Complex passages can lose detail in scanning — listen once before practicing, and rescan sharper photos if something sounds off.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer(minLength: 20)
            }
            .padding()
        }
    }

    private var notePreview: some View {
        Canvas { context, size in
            let notes = score.playback.notes
            guard !notes.isEmpty, score.playback.totalDuration > 0 else { return }
            let total = score.playback.totalDuration

            let minPitch = notes.map(\.pitch).min() ?? 21
            let maxPitch = notes.map(\.pitch).max() ?? 108
            let pitchRange = max(1, maxPitch - minPitch)

            for note in notes {
                let x = CGFloat(note.startTime / total) * size.width
                let w = max(2, CGFloat(note.duration / total) * size.width)
                let y = size.height - CGFloat(note.pitch - minPitch) / CGFloat(pitchRange) * (size.height - 8) - 4
                let color: Color = note.voice >= 2 ? AppTheme.leftHandNote : AppTheme.rightHandNote
                context.fill(
                    Path(roundedRect: CGRect(x: x, y: y - 2, width: w, height: 4), cornerRadius: 1),
                    with: .color(color)
                )
            }
        }
    }

    private func previewStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3).bold()
                .foregroundColor(AppTheme.accent)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppTheme.cardBackground)
        .cornerRadius(10)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Escalation policy

private extension SheetMusicRecognitionError {
    /// Worth one retry on a stronger model; truncation and setup problems aren't.
    var isEscalatable: Bool {
        if case .unreadableScore = self { return true }
        return false
    }
}

// MARK: - Scan Settings Sheet

private struct ScanSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let account: ScanAccountManager
    @State private var settings = ScanSettings.shared
    @State private var keyInput: String = ScanSettings.shared.apiKey

    var body: some View {
        NavigationStack {
            Form {
                if ScanCloudConfig.baseURL != nil {
                    Section {
                        if account.isSignedIn {
                            LabeledContent("Free scans left") {
                                Text(account.remainingScans.map(String.init) ?? "—")
                            }
                            Button("Sign Out", role: .destructive) {
                                account.signOut()
                            }
                        } else {
                            Text("Sign in from the scan screen to get free scans — no API key needed.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Account")
                    }
                }

                Section {
                    SecureField("sk-ant-…", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: keyInput) { _, newValue in
                            settings.apiKey = newValue
                        }
                } header: {
                    Text(ScanCloudConfig.baseURL != nil ? "Advanced — Your Own API Key" : "Anthropic API Key")
                } footer: {
                    Text(ScanCloudConfig.baseURL != nil
                         ? "Optional. Used only when you're not signed in or you've run out of free scans. Create a key at console.anthropic.com; it's stored in the device Keychain."
                         : "Create a key at console.anthropic.com → API Keys. It is stored in the device Keychain and sent only to Anthropic with your scans. A typical scan costs a few cents.")
                }

                Section {
                    Picker("Model", selection: Binding(
                        get: { settings.model },
                        set: { settings.model = $0 }
                    )) {
                        ForEach(ScanSettings.availableModels, id: \.id) { model in
                            Text(model.label).tag(model.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Recognition Model (own-key scans)")
                }
            }
            .navigationTitle("Scan Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Document Camera Wrapper

/// VisionKit's document scanner: multi-page capture with automatic edge
/// detection, perspective correction, and shadow removal — ideal preprocessing
/// for music recognition.
private struct DocumentCameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onScan: ([UIImage]) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScan: ([UIImage]) -> Void
        let dismiss: () -> Void

        init(onScan: @escaping ([UIImage]) -> Void, dismiss: @escaping () -> Void) {
            self.onScan = onScan
            self.dismiss = dismiss
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for pageIndex in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: pageIndex))
            }
            onScan(images)
            dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            print("Document camera failed:", error)
            dismiss()
        }
    }
}
