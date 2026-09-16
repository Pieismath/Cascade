//
//  SheetScanView.swift
//  MyPianoInstructor
//
//  The scan-to-play flow: capture sheet music with the document camera or
//  import a PDF/images, send the pages through optical music recognition,
//  preview the transcription, then save it to the library and/or export a
//  falling-note video straight away.
//

import SwiftUI
import VisionKit
import PDFKit
import UniformTypeIdentifiers
import AuthenticationServices
import StoreKit

/// Bring-your-own-key scanning is a developer convenience. Release builds are
/// cloud-only so no customer is ever asked for an API key.
private var ownKeyAllowed: Bool {
    #if DEBUG
    return true
    #else
    return false
    #endif
}

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
    @State private var progressText = "Reading the notation…"
    /// Set while the loaded pages are a bundled sample; Convert then uses the
    /// prepared transcription instead of the network.
    @State private var activeSample: SampleScan? = nil

    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var showSettings = false
    @State private var errorMessage: String? = nil
    @State private var recognitionTask: Task<Void, Never>? = nil

    // Export straight from the preview
    @State private var exporter = VideoExportManager()
    @State private var showExportSheet = false
    @State private var showExportError = false
    @State private var exportedVideoURL: URL? = nil

    @State private var settings = ScanSettings.shared
    @State private var account: ScanAccountManager
    @State private var store: ScanStore
    @State private var infoMessage: String? = nil

    init(selectedSong: Binding<Song?>, tabSelection: Binding<Int>) {
        _selectedSong = selectedSong
        _tabSelection = tabSelection
        let account = ScanAccountManager()
        _account = State(initialValue: account)
        _store = State(initialValue: ScanStore(account: account))
    }

    private var cameraAvailable: Bool {
        VNDocumentCameraViewController.isSupported
    }

    private var cloudConfigured: Bool {
        ScanCloudConfig.baseURL != nil
    }

    /// Credits this scan will cost (1 per 4 pages by default).
    private var creditsNeeded: Int {
        account.creditsNeeded(forPages: max(1, pages.count))
    }

    private var hasEnoughCredits: Bool {
        (account.remainingScans ?? 1) >= creditsNeeded
    }

    /// Cloud mode (signed in, enough credits) or a developer key — either unlocks Convert.
    /// Bundled samples always work: they don't touch the network.
    private var canRecognize: Bool {
        if activeSample != nil { return true }
        if cloudConfigured && account.isSignedIn && hasEnoughCredits {
            return true
        }
        return ownKeyAllowed && settings.hasAPIKey
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
                        isSample: activeSample != nil,
                        onSave: { save(score) },
                        onExport: { saveAndExport(score) },
                        onRetry: { phase = .collectingPages }
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
                    .disabled(exporter.isExporting)
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
                if activeSample != nil { pages.removeAll(); activeSample = nil }
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
            ScanSettingsView(account: account, store: store)
        }
        .sheet(isPresented: $showExportSheet) {
            ExportProgressSheet(progress: exporter.exportProgress)
                .interactiveDismissDisabled(exporter.isExporting)
        }
        .sheet(item: $exportedVideoURL) { url in
            VideoShareSheet(url: url)
                .ignoresSafeArea()
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not export the video. The song is saved in your library — try exporting again from the player.")
        }
        .task {
            await account.refresh()
            // Purchases whose redemption was interrupted are retried here.
            let granted = await store.redeemPending()
            if granted > 0 { infoMessage = "Added \(granted) scan\(granted == 1 ? "" : "s") from a previous purchase." }
        }
        .alert("Scans Added", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) { infoMessage = nil }
        } message: {
            Text(infoMessage ?? "")
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

                Text("Photograph printed sheet music or import a PDF, and Cascade turns it into a falling-note lesson and video.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                if activeSample != nil {
                    sampleLoadedNote
                } else if cloudConfigured {
                    if !account.isSignedIn {
                        signInCard
                    } else if !hasEnoughCredits {
                        ScanPacksCard(store: store, account: account, creditsNeeded: creditsNeeded,
                                      onGranted: { infoMessage = $0 }, onError: { errorMessage = $0 })
                    } else {
                        scansRemainingPill
                    }
                } else if ownKeyAllowed && !settings.hasAPIKey {
                    apiKeyPrompt
                } else if !ownKeyAllowed {
                    unavailableCard
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

                if pages.isEmpty {
                    samplesSection
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
                                activeSample = nil
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
                                            activeSample = nil
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

                        if activeSample == nil, pages.count > ClaudeSheetMusicRecognizer.maxPagesPerScan {
                            Label(
                                "That's a lot of pages for one scan. For best results scan up to \(ClaudeSheetMusicRecognizer.maxPagesPerScan) pages at a time.",
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
                        Label(activeSample == nil ? "Convert to Falling Notes" : "Convert Sample (free)", systemImage: "wand.and.stars")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canRecognize ? AnyShapeStyle(AppTheme.accentGradient) : AnyShapeStyle(Color.gray))
                            .cornerRadius(14)
                    }
                    .disabled(!canRecognize || pages.count > ClaudeSheetMusicRecognizer.maxPagesPerScan)
                }

                privacyNote

                Spacer(minLength: 30)
            }
            .padding()
        }
    }

    // MARK: - Samples

    /// "Try it" scans: bundled pages with a prepared result — instant, free,
    /// no sign-in — so people see the whole flow before spending anything.
    private var samplesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(AppTheme.accent)
                Text("Try a sample first")
                    .font(.headline)
            }
            Text("Tap a page to load it, then Convert. Samples use a prepared transcription, so they're instant and free.")
                .font(.caption)
                .foregroundColor(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(SampleScan.all) { sample in
                        Button {
                            loadSample(sample)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                if let thumb = sample.thumbnail() {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 110, height: 140, alignment: .top)
                                        .clipped()
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                }
                                Text(sample.title)
                                    .font(.caption).bold()
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                Text(sample.composer)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 110, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Sample: \(sample.title)")
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.cardBackground)
        .cornerRadius(14)
    }

    private var sampleLoadedNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundColor(AppTheme.accent)
            Text("Sample loaded — converting is instant and free. Your own scans need sign-in.")
                .font(.caption).bold()
            Spacer()
        }
        .padding(10)
        .background(AppTheme.accent.opacity(0.08))
        .cornerRadius(10)
    }

    private func loadSample(_ sample: SampleScan) {
        let images = sample.loadPages()
        guard !images.isEmpty else {
            errorMessage = "The sample pages are missing from this build."
            return
        }
        pages = images
        songTitle = sample.title
        activeSample = sample
    }

    // MARK: - Cards

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(freeScanHeadline, systemImage: "sparkles")
                .font(.subheadline).bold()
            Text("Sign in to scan. Your first scan is on us; packs of scans are available after that. We only receive an anonymous account ID, never your name or email.")
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

    private var freeScanHeadline: String {
        let free = account.freeScans ?? 1
        return free == 1 ? "Get a free scan" : "Get \(free) free scans"
    }

    private var scansRemainingPill: some View {
        let remaining = account.remainingScans ?? 0
        let costNote = pages.count > 4 ? " · this scan uses \(creditsNeeded)" : ""
        return HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
            Text("Signed in — \(remaining) scan\(remaining == 1 ? "" : "s") left\(costNote)")
                .font(.caption).bold()
            Spacer()
            Button("Get more") { showSettings = true }
                .font(.caption).bold()
        }
        .padding(10)
        .background(Color.green.opacity(0.1))
        .cornerRadius(10)
    }

    private var unavailableCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.orange)
            Text("Scanning isn't available in this build.")
                .font(.subheadline).bold()
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
                Text("Developer build: add an Anthropic API key to enable scanning")
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

    /// Plain-language disclosure of what leaves the device when you scan.
    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("How scanning works", systemImage: "lock.shield")
                .font(.caption).bold()
                .foregroundColor(.secondary)
            Text("When you tap Convert, the page images are sent over an encrypted connection to Cascade's scan service, where an AI model reads the notation. Pages are processed, not stored, and are never used to identify you. Everything else in Cascade works offline.")
                .font(.caption2)
                .foregroundColor(.secondary)
            if let url = ScanCloudConfig.privacyPolicyURL {
                Link("Privacy Policy", destination: url)
                    .font(.caption2).bold()
            }
        }
        .padding(.top, 6)
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
            Text(progressText)
                .font(.headline)
                .contentTransition(.numericText())
                .animation(.default, value: progressText)
            Text("Transcribing \(pages.count) page\(pages.count == 1 ? "" : "s") of sheet music into playable notes. Longer pieces are read in several parts; this usually takes a minute or two.")
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
        if activeSample != nil { pages.removeAll(); activeSample = nil }

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
                    // Rasterise larger than the upload size so system crops
                    // keep full resolution after splitting.
                    let target = SheetPagePrep.maxDimension * 2
                    let scale = longest > 0 ? target / longest : 1
                    let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                    pages.append(page.thumbnail(of: size, for: .mediaBox))
                }
                if songTitle.isEmpty {
                    songTitle = url.deletingPathExtension().lastPathComponent
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "-", with: " ")
                }
            } else if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                pages.append(image)
            } else {
                errorMessage = "Could not read \(url.lastPathComponent)."
            }
        }
    }

    // MARK: - Recognition

    /// Cloud recognizer when signed in with scans left; otherwise a developer
    /// key. `quality` only matters on the cloud path.
    private func makeRecognizer(quality: String) -> SheetMusicRecognizer? {
        if let baseURL = ScanCloudConfig.baseURL,
           account.isSignedIn,
           let token = account.sessionToken,
           (account.remainingScans ?? 1) > 0 {
            return CascadeCloudRecognizer(baseURL: baseURL, sessionToken: token, quality: quality)
        }
        if ownKeyAllowed && settings.hasAPIKey {
            return settings.makeRecognizer()
        }
        return nil
    }

    private func startRecognition() {
        if let sample = activeSample {
            runSampleConversion(sample)
            return
        }
        guard let recognizer = makeRecognizer(quality: "standard") else {
            if cloudConfigured && account.isSignedIn && !hasEnoughCredits {
                errorMessage = "This scan needs \(creditsNeeded) scan credit\(creditsNeeded == 1 ? "" : "s"). Get a scan pack to continue."
            } else {
                errorMessage = cloudConfigured
                    ? "Sign in to scan."
                    : SheetMusicRecognitionError.missingAPIKey.localizedDescription
            }
            return
        }

        let usingCloud = recognizer is CascadeCloudRecognizer
        let snapshot = pages
        progressText = "Preparing pages…"
        phase = .recognizing

        let report: ScoreTranscriptionJob.Progress = { text in
            Task { @MainActor in progressText = text }
        }

        let jobID = UUID().uuidString.lowercased()
        recognitionTask = Task {
            do {
                var score: RecognizedScore
                do {
                    // Pass 1: system crops, a few per request.
                    var job = ScoreTranscriptionJob(recognizer: recognizer, pages: snapshot, strategy: .systems(perBatch: 4))
                    job.jobID = jobID
                    score = try await job.run(progress: report)

                    // Rhythm badly off → one whole-page pass on the stronger
                    // model (cloud only; rides on the same free scan).
                    if usingCloud, score.measureReport.suspectFraction > 0.25,
                       let retry = makeRecognizer(quality: "high") {
                        progressText = "Double-checking tricky passages…"
                        var second = ScoreTranscriptionJob(recognizer: retry, pages: snapshot, strategy: .wholePages(perBatch: 3))
                        second.jobID = job.jobID   // same scan, same single credit
                        if let better = try? await second.run(progress: report),
                           better.measureReport.suspectFraction < score.measureReport.suspectFraction {
                            score = better
                        }
                    }
                } catch let err as SheetMusicRecognitionError where err.isEscalatable {
                    // Pass 1 produced nothing usable — try whole pages, on the
                    // stronger model when the cloud offers one.
                    let retry = (usingCloud ? makeRecognizer(quality: "high") : nil) ?? recognizer
                    progressText = "Trying again with full pages…"
                    var second = ScoreTranscriptionJob(recognizer: retry, pages: snapshot, strategy: .wholePages(perBatch: 3))
                    second.jobID = jobID
                    score = try await second.run(progress: report)
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

    /// Samples skip the network: the prepared MusicXML goes through the same
    /// validation and preview as a real result, after a short "reading" beat
    /// so the flow feels the same.
    private func runSampleConversion(_ sample: SampleScan) {
        guard let xml = sample.loadMusicXML() else {
            errorMessage = "The sample transcription is missing from this build."
            return
        }
        progressText = "Reading the notation… (sample)"
        phase = .recognizing
        recognitionTask = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            do {
                let score = try SheetMusicValidator.validate(musicXML: xml)
                if songTitle.isEmpty { songTitle = sample.title }
                phase = .preview(score)
            } catch {
                phase = .collectingPages
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Save / Export

    @discardableResult
    private func save(_ score: RecognizedScore, andPlay: Bool = true) -> Song {
        let title = songTitle.trimmingCharacters(in: .whitespaces)
        let newSong = libraryVM.addSong(
            title: title.isEmpty ? "Scanned Music" : title,
            musicXML: score.musicXML
        )
        selectedSong = newSong
        if andPlay {
            dismiss()
            tabSelection = 2
        }
        return newSong
    }

    /// Saves to the library first (so nothing is lost if the export fails),
    /// then renders the video and offers the share sheet.
    private func saveAndExport(_ score: RecognizedScore) {
        let song = save(score, andPlay: false)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(ExportFileNaming.videoFileName(for: song.title))
        try? FileManager.default.removeItem(at: outputURL)
        exportedVideoURL = nil
        showExportSheet = true

        exporter.exportVideo(playbackData: score.playback, outputURL: outputURL) { success in
            showExportSheet = false
            // Give the progress sheet time to dismiss before presenting the
            // share sheet / alert — same-transaction swaps get dropped.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if success {
                    exportedVideoURL = outputURL
                } else {
                    showExportError = true
                }
            }
        }
    }
}

// MARK: - Preview Phase View

private struct ScanPreviewView: View {
    let score: RecognizedScore
    @Binding var songTitle: String
    var isSample: Bool = false
    let onSave: () -> Void
    let onExport: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Transcription ready — check that it looks right", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundColor(.green)

                if isSample {
                    Text("Sample: this transcription was prepared in advance, so no scan credit was used. Your own pages go through live recognition.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.accent.opacity(0.08))
                        .cornerRadius(10)
                }

                // Stats
                HStack(spacing: 10) {
                    previewStat("\(score.playback.notes.count)", "Notes")
                    previewStat(formatDuration(score.playback.totalDuration), "Duration")
                    previewStat("\(Int(score.playback.tempo))", "BPM")
                    previewStat("\(score.measureReport.measureCount)", "Measures")
                }

                if !score.measureReport.suspectMeasures.isEmpty {
                    rhythmWarning
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

                Button(action: onExport) {
                    Label("Save & Export Video", systemImage: "film")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accent)

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

    private var rhythmWarning: some View {
        let report = score.measureReport
        let list = report.suspectMeasures.prefix(6).map(String.init).joined(separator: ", ")
        let more = report.suspectMeasures.count > 6 ? " and \(report.suspectMeasures.count - 6) more" : ""
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "metronome")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(report.suspectMeasures.count) of \(report.measureCount) measures may have rhythm errors")
                    .font(.caption).bold()
                Text("Measure\(report.suspectMeasures.count == 1 ? "" : "s") \(list)\(more) don't add up to the time signature. Listen to those spots; a sharper scan usually fixes them.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
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
    /// Worth one retry with a different strategy; setup problems aren't.
    var isEscalatable: Bool {
        switch self {
        case .unreadableScore, .truncatedResult: return true
        default: return false
        }
    }
}

// MARK: - Scan Settings Sheet

private struct ScanSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let account: ScanAccountManager
    let store: ScanStore
    @State private var settings = ScanSettings.shared
    @State private var restoreMessage: String? = nil
    @State private var keyInput: String = ScanSettings.shared.apiKey
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                if ScanCloudConfig.baseURL != nil {
                    Section {
                        if account.isSignedIn {
                            LabeledContent("Scans left") {
                                Text(account.remainingScans.map(String.init) ?? "—")
                            }
                            if let credits = account.credits, credits > 0 {
                                LabeledContent("Purchased credits", value: "\(credits)")
                            }
                            Button("Sign Out") {
                                account.signOut()
                            }
                            Button("Delete Account…", role: .destructive) {
                                confirmDelete = true
                            }
                            .disabled(deleting)
                        } else {
                            Text("Sign in from the scan screen to get free scans.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Account")
                    } footer: {
                        Text("Your account holds only an anonymous Apple sign-in ID, your scan usage, and any purchased credits. Deleting it removes that record from our servers; unused credits are forfeited.")
                    }

                    Section {
                        ScanPacksList(store: store, account: account,
                                      onGranted: { restoreMessage = $0 }, onError: { restoreMessage = $0 })
                        Button("Restore Purchases") {
                            Task {
                                let granted = await store.redeemPending()
                                restoreMessage = granted > 0
                                    ? "Added \(granted) scan\(granted == 1 ? "" : "s")."
                                    : "No unredeemed purchases were found. Your balance is up to date."
                            }
                        }
                    } header: {
                        Text("Scan Packs")
                    } footer: {
                        Text("One credit covers a scan of up to \(account.pagesPerCredit) pages. Longer pieces use one credit per \(account.pagesPerCredit) pages.")
                    }
                }

                if ownKeyAllowed {
                    Section {
                        SecureField("sk-ant-…", text: $keyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: keyInput) { _, newValue in
                                settings.apiKey = newValue
                            }
                    } header: {
                        Text("Developer — Your Own API Key")
                    } footer: {
                        Text("Debug builds only. Used when you're not signed in or have run out of free scans. Stored in the device Keychain.")
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

                Section {
                    if let url = ScanCloudConfig.privacyPolicyURL {
                        Link("Privacy Policy", destination: url)
                    }
                    LabeledContent("Version", value: Self.versionString)
                } header: {
                    Text("About")
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
            .confirmationDialog(
                "Delete your Cascade account?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    deleting = true
                    Task {
                        do {
                            try await account.deleteAccount()
                        } catch {
                            deleteError = error.localizedDescription
                        }
                        deleting = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your scan record from our servers and signs you out. Songs already in your library stay on this device.")
            }
            .alert("Purchases", isPresented: Binding(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )) {
                Button("OK", role: .cancel) { restoreMessage = nil }
            } message: {
                Text(restoreMessage ?? "")
            }
            .alert("Couldn't Delete Account", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
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


// MARK: - Scan packs (StoreKit 2)

/// Card shown on the scan screen when the account can't cover the next scan.
private struct ScanPacksCard: View {
    let store: ScanStore
    let account: ScanAccountManager
    let creditsNeeded: Int
    let onGranted: (String) -> Void
    let onError: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(headline, systemImage: "sparkles")
                .font(.subheadline).bold()
            Text("One credit covers a scan of up to \(account.pagesPerCredit) pages. Packs never expire.")
                .font(.caption)
                .foregroundColor(.secondary)
            ScanPacksList(store: store, account: account, onGranted: onGranted, onError: onError)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accent.opacity(0.08))
        .cornerRadius(12)
        .task { await store.loadProducts() }
    }

    private var headline: String {
        let remaining = account.remainingScans ?? 0
        if remaining == 0 { return "You're out of scans" }
        return "This scan needs \(creditsNeeded) credits — you have \(remaining)"
    }
}

/// Product rows with Buy buttons, shared by the scan card and settings.
private struct ScanPacksList: View {
    let store: ScanStore
    let account: ScanAccountManager
    let onGranted: (String) -> Void
    let onError: (String) -> Void

    var body: some View {
        Group {
            if store.products.isEmpty {
                if store.isLoadingProducts {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text(store.loadError ?? "Scan packs aren't available right now.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(store.products, id: \.id) { product in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.displayName).font(.subheadline).bold()
                            Text(perScanLabel(product)).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            buy(product)
                        } label: {
                            Text(product.displayPrice)
                                .font(.subheadline).bold()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accent)
                        .disabled(store.isPurchasing)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task { await store.loadProducts() }
    }

    private func perScanLabel(_ product: Product) -> String {
        let credits = ScanStore.credits(for: product)
        guard credits > 0 else { return product.description }
        let each = (product.price / Decimal(credits))
        let formatted = each.formatted(product.priceFormatStyle)
        return "\(credits) scans · \(formatted) each"
    }

    private func buy(_ product: Product) {
        Task {
            do {
                switch try await store.purchase(product) {
                case .granted(let n):
                    onGranted("Added \(n) scan\(n == 1 ? "" : "s") to your account.")
                case .pending:
                    onGranted("Your purchase is waiting for approval. Scans will be added once it's approved.")
                case .cancelled:
                    break
                }
            } catch {
                onError(error.localizedDescription)
            }
        }
    }
}
