//
//  SheetScanView.swift
//  MyPianoInstructor
//
//  The scan-to-play flow. Home hands it pages (from the camera, Photos, or
//  Files, or a bundled sample); this screen converts them into notes,
//  previews the result, then saves it to the library and/or exports a video.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SheetScanView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(ScanAccountManager.self) private var account
    @Environment(ScanStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedSong: Song?
    @Binding var tabSelection: Int

    private enum Phase {
        case review
        case recognizing
        case preview(RecognizedScore)
    }

    @State private var phase: Phase = .review
    @State private var pages: [UIImage]
    @State private var songTitle: String
    /// Set while the pages are a bundled sample; converting then uses the
    /// prepared transcription instead of the network.
    @State private var activeSample: SampleScan?
    @State private var progressText = "Reading the notation"

    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showPrivacyInfo = false
    @State private var errorMessage: String? = nil
    @State private var infoMessage: String? = nil
    @State private var recognitionTask: Task<Void, Never>? = nil

    // Export straight from the preview
    @State private var exporter = VideoExportManager()
    @State private var showExportSheet = false
    @State private var showExportError = false
    @State private var exportedVideoURL: URL? = nil

    init(session: ScanSession, selectedSong: Binding<Song?>, tabSelection: Binding<Int>) {
        _selectedSong = selectedSong
        _tabSelection = tabSelection
        _pages = State(initialValue: session.pages)
        _songTitle = State(initialValue: session.title)
        _activeSample = State(initialValue: session.sample)
    }

    private var cloudConfigured: Bool { ScanCloudConfig.baseURL != nil }

    /// Credits this scan costs (one per few pages).
    private var creditsNeeded: Int {
        account.creditsNeeded(forPages: max(1, pages.count))
    }

    private var hasEnoughCredits: Bool {
        (account.remainingScans ?? 1) >= creditsNeeded
    }

    private var tooManyPages: Bool {
        activeSample == nil && pages.count > ScanCloudConfig.maxPagesPerScan
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .review:
                    reviewView
                case .recognizing:
                    recognizingView
                case .preview(let score):
                    ScanPreviewView(
                        score: score,
                        songTitle: $songTitle,
                        isSample: activeSample != nil,
                        onSave: { save(score) },
                        onExport: { saveAndExport(score) },
                        onRetry: { phase = .review }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .stageBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        recognitionTask?.cancel()
                        dismiss()
                    }
                    .disabled(exporter.isExporting)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCameraView { scanned in
                pages.append(contentsOf: scanned)
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection,
                      maxSelectionCount: ScanCloudConfig.maxPagesPerScan, matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                pages.append(contentsOf: await ScanPageLoader.pages(from: items))
                photoSelection = []
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let loaded = ScanPageLoader.pages(from: urls)
                pages.append(contentsOf: loaded.pages)
                if songTitle.isEmpty { songTitle = loaded.title }
                if !loaded.unreadable.isEmpty {
                    errorMessage = "Couldn't read \(loaded.unreadable.joined(separator: ", "))."
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showPrivacyInfo) { ScanPrivacySheet() }
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
            if activeSample == nil { await account.refresh() }
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

    // MARK: - Review

    private var reviewView: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    pageStrip
                    VStack(spacing: 6) {
                        Text(activeSample?.title ?? (pages.isEmpty ? "No pages yet" : "\(pages.count) page\(pages.count == 1 ? "" : "s")"))
                            .font(CascadeFont.display(28))
                            .foregroundStyle(Brand.textPrimary)
                            .multilineTextAlignment(.center)
                        if let sample = activeSample {
                            Text("Sample scan · \(sample.composer)")
                                .font(.subheadline)
                                .foregroundStyle(Brand.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }

            convertPanel
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(alignment: .top) {
                    LinearGradient(colors: [Brand.ink.opacity(0), Brand.ink], startPoint: .top, endPoint: .init(x: 0.5, y: 0.25))
                        .padding(.top, -28)
                        .ignoresSafeArea()
                }
        }
    }

    private var pageStrip: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                pageRow
                    .frame(minWidth: geo.size.width)
            }
        }
        .frame(height: 364)
    }

    private var pageRow: some View {
        HStack(spacing: 14) {
            ForEach(pages.indices, id: \.self) { i in
                Image(uiImage: pages[i])
                    .resizable()
                    .scaledToFit()
                    .frame(height: 340)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                    .overlay(alignment: .bottomLeading) {
                        if pages.count > 1 {
                            Text("\(i + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(.black.opacity(0.6), in: Circle())
                                .padding(8)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if activeSample == nil {
                            Button {
                                withAnimation(.snappy) { _ = pages.remove(at: i) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 26, height: 26)
                                    .background(.black.opacity(0.6), in: Circle())
                            }
                            .padding(8)
                            .accessibilityLabel("Remove page \(i + 1)")
                        }
                    }
            }
            if activeSample == nil {
                addPageTile
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var addPageTile: some View {
        Menu {
            if DocumentCameraView.isAvailable {
                Button { showCamera = true } label: { Label("Camera", systemImage: "camera") }
            }
            Button { showPhotoPicker = true } label: { Label("Photos", systemImage: "photo.on.rectangle") }
            Button { showFileImporter = true } label: { Label("Files", systemImage: "folder") }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                Text("Add page")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Brand.textSecondary)
            .frame(width: pages.isEmpty ? 240 : 130, height: 340)
            .background(Brand.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Brand.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
        }
        .accessibilityLabel("Add page")
    }

    /// Status line, the one action that matters right now, and the privacy note.
    private var convertPanel: some View {
        VStack(spacing: 12) {
            statusLine

            if activeSample != nil {
                convertButton(title: "Make falling notes")
                    .accessibilityLabel("Convert Sample")
            } else if !cloudConfigured {
                convertButton(title: "Scanning unavailable")
                    .disabled(true)
                    .opacity(0.45)
            } else if !account.isSignedIn {
                ScanSignInButton(onError: { errorMessage = $0 })
            } else if !hasEnoughCredits {
                ScanPacksList(store: store, onGranted: { infoMessage = $0 }, onError: { errorMessage = $0 })
                Button("Restore purchases") {
                    Task {
                        let granted = await store.redeemPending()
                        if granted > 0 { infoMessage = "Added \(granted) scan\(granted == 1 ? "" : "s")." }
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Brand.textSecondary)
            } else {
                convertButton(title: "Make falling notes")
                    .disabled(pages.isEmpty || tooManyPages)
                    .opacity(pages.isEmpty || tooManyPages ? 0.45 : 1)
                    .accessibilityLabel("Convert to Falling Notes")
            }

            if activeSample == nil {
                Button { showPrivacyInfo = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "lock.fill").font(.system(size: 9))
                        Text("Uploaded securely, never kept.")
                        Text("How it works").bold()
                    }
                    .font(.caption2)
                    .foregroundStyle(Brand.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func convertButton(title: String) -> some View {
        Button {
            startRecognition()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                Text(title)
            }
        }
        .buttonStyle(.cascadePrimary)
    }

    private var statusLine: some View {
        let (text, tint): (String, Color) = {
            if activeSample != nil { return ("Free · converts instantly", Brand.teal) }
            if tooManyPages { return ("Up to \(ScanCloudConfig.maxPagesPerScan) pages per scan", Brand.amber) }
            if !cloudConfigured { return ("Scanning isn't available in this build", Brand.amber) }
            if !account.isSignedIn {
                let free = account.freeScans ?? 1
                return (free == 1 ? "Your first scan is free" : "Your first \(free) scans are free", Brand.teal)
            }
            let remaining = account.remainingScans ?? 0
            if !hasEnoughCredits {
                return (remaining == 0
                        ? "You're out of scans"
                        : "This scan needs \(creditsNeeded) · you have \(remaining)", Brand.amber)
            }
            return ("Uses \(creditsNeeded) of your \(remaining) scan\(remaining == 1 ? "" : "s")", Brand.textSecondary)
        }()
        return Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
    }

    // MARK: - Recognizing

    private var recognizingView: some View {
        VStack(spacing: 30) {
            Spacer()
            ScanningPagesView(pages: pages)
            VStack(spacing: 8) {
                Text(progressText)
                    .font(CascadeFont.display(24))
                    .foregroundStyle(Brand.textPrimary)
                    .contentTransition(.opacity)
                    .animation(.default, value: progressText)
                Text(activeSample != nil ? "Sample scan" : "Usually a minute or two")
                    .font(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
            Spacer()
            Button("Stop") {
                recognitionTask?.cancel()
                phase = .review
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(Brand.textSecondary)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Recognition

    private func makeRecognizer(quality: String) -> SheetMusicRecognizer? {
        guard let baseURL = ScanCloudConfig.baseURL,
              account.isSignedIn,
              let token = account.sessionToken,
              (account.remainingScans ?? 1) > 0 else { return nil }
        return CascadeCloudRecognizer(baseURL: baseURL, sessionToken: token, quality: quality)
    }

    private func startRecognition() {
        if let sample = activeSample {
            runSampleConversion(sample)
            return
        }
        guard let recognizer = makeRecognizer(quality: "standard") else {
            errorMessage = account.isSignedIn
                ? "This scan needs \(creditsNeeded) scan\(creditsNeeded == 1 ? "" : "s"). Get a scan pack to continue."
                : "Sign in to scan."
            return
        }

        let snapshot = pages
        progressText = "Preparing pages"
        phase = .recognizing

        let report: ScoreTranscriptionJob.Progress = { text in
            Task { @MainActor in progressText = text.trimmingCharacters(in: CharacterSet(charactersIn: "…")) }
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

                    // Rhythm badly off → one whole-page pass at higher quality,
                    // on the same scan credit.
                    if score.measureReport.suspectFraction > 0.25,
                       let retry = makeRecognizer(quality: "high") {
                        progressText = "Double-checking tricky passages"
                        var second = ScoreTranscriptionJob(recognizer: retry, pages: snapshot, strategy: .wholePages(perBatch: 3))
                        second.jobID = job.jobID
                        if let better = try? await second.run(progress: report),
                           better.measureReport.suspectFraction < score.measureReport.suspectFraction {
                            score = better
                        }
                    }
                } catch let err as SheetMusicRecognitionError where err.isEscalatable {
                    // Pass 1 produced nothing usable — try whole pages at higher quality.
                    let retry = makeRecognizer(quality: "high") ?? recognizer
                    progressText = "Trying again with full pages"
                    var second = ScoreTranscriptionJob(recognizer: retry, pages: snapshot, strategy: .wholePages(perBatch: 3))
                    second.jobID = jobID
                    score = try await second.run(progress: report)
                }

                if songTitle.isEmpty {
                    songTitle = "Scanned Music \(Date().formatted(date: .abbreviated, time: .omitted))"
                }
                phase = .preview(score)
                await account.refresh()
            } catch is CancellationError {
                // User backed out — no error surface needed
            } catch ScanCloudError.sessionExpired {
                account.signOut()
                phase = .review
                errorMessage = ScanCloudError.sessionExpired.localizedDescription
            } catch {
                phase = .review
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
        progressText = "Reading the notation"
        phase = .recognizing
        recognitionTask = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            do {
                let score = try SheetMusicValidator.validate(musicXML: xml)
                if songTitle.isEmpty { songTitle = sample.title }
                phase = .preview(score)
            } catch {
                phase = .review
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

// MARK: - Reading animation

/// The pages stacked, with a light sweeping down the top one while the notes
/// are read.
private struct ScanningPagesView: View {
    let pages: [UIImage]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let width: CGFloat = 230
        let height: CGFloat = 300
        ZStack {
            ForEach(Array(pages.prefix(3).enumerated().reversed()), id: \.offset) { index, page in
                Image(uiImage: page)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height, alignment: .top)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
                    .rotationEffect(.degrees(Double(index) * 3.5))
                    .offset(x: CGFloat(index) * 10, y: CGFloat(index) * -6)
                    .opacity(index == 0 ? 1 : 0.7)
            }

            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = reduceMotion ? 0.5 : (sin(t * 1.6) + 1) / 2
                ZStack(alignment: .top) {
                    LinearGradient(colors: [Brand.teal.opacity(0), Brand.teal.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                        .offset(y: -68)
                    Capsule()
                        .fill(Brand.teal)
                        .frame(height: 3)
                        .shadow(color: Brand.teal, radius: 8)
                }
                .frame(width: width, height: 2, alignment: .top)
                .offset(y: (phase - 0.5) * (height - 20))
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .accessibilityHidden(true)
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
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                ScoreArtView(playback: score.playback, window: 16, cornerRadius: 24)
                    .frame(height: 220)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Brand.mint)
                        Text(isSample ? "Sample transcription" : "Transcription ready").eyebrowStyle(Brand.mint)
                    }
                    TextField("Song title", text: $songTitle)
                        .font(CascadeFont.display(28))
                        .foregroundStyle(Brand.textPrimary)
                        .textFieldStyle(.plain)
                    Text("\(score.playback.notes.count) notes · \(formatDuration(score.playback.totalDuration)) · \(Int(score.playback.tempo)) BPM · \(score.measureReport.measureCount) measures")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Brand.textSecondary)
                }

                if !score.measureReport.suspectMeasures.isEmpty {
                    rhythmWarning
                }

                Button(action: onSave) {
                    HStack(spacing: 8) { Image(systemName: "play.fill"); Text("Add to library & play") }
                }
                .buttonStyle(.cascadePrimary)

                Button(action: onExport) {
                    HStack(spacing: 8) { Image(systemName: "film"); Text("Save & export video") }
                }
                .buttonStyle(.cascadeSecondary)

                Button(action: onRetry) {
                    Text(isSample ? "Back" : "Scan again")
                        .font(.subheadline)
                        .foregroundStyle(Brand.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Spacer(minLength: 20)
            }
            .padding(20)
        }
    }

    private var rhythmWarning: some View {
        let report = score.measureReport
        let list = report.suspectMeasures.prefix(6).map(String.init).joined(separator: ", ")
        let more = report.suspectMeasures.count > 6 ? " and \(report.suspectMeasures.count - 6) more" : ""
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Brand.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(report.suspectMeasures.count) of \(report.measureCount) measures may have rhythm errors")
                    .font(.caption).bold()
                    .foregroundStyle(Brand.textPrimary)
                Text("Measure\(report.suspectMeasures.count == 1 ? "" : "s") \(list)\(more) don't add up to the time signature. Listen to those spots; a sharper scan usually fixes them.")
                    .font(.caption2)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
