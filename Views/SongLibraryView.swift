//
//  SongLibraryView.swift
//  MyPianoInstructor
//
//  Home: the wordmark, the piece you're working on, the two ways to bring
//  music in (Scan opens the camera, Import opens Files), your library, and
//  free things to try — sample scans and the starter pieces.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SongLibraryView: View {
    @Environment(SongLibraryViewModel.self) var libraryVM
    @Environment(PracticeStatsManager.self) var statsManager
    @Environment(AchievementManager.self) var achievementManager
    @Environment(ThemeManager.self) var themeManager
    @Environment(ScanAccountManager.self) var scanAccount
    @Environment(ScanStore.self) var scanStore

    @Binding var selectedSong: Song?
    @Binding var tabSelection: Int
    @Binding var showTutorial: Bool

    @State private var showSettings = false
    @State private var tourAfterSettings = false

    // Bringing music in
    @State private var showCamera = false
    @State private var capturedPages: [UIImage] = []
    @State private var showPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showImporter = false
    @State private var scanSession: ScanSession? = nil
    @State private var importError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                header
                    .padding(.horizontal, 20)

                if let song = libraryVM.recentSongs.first {
                    upNextCard(song)
                        .padding(.horizontal, 20)
                } else {
                    emptyHero
                        .padding(.horizontal, 20)
                }

                addMusic
                    .padding(.horizontal, 20)

                if statsManager.sessionsCount > 0 {
                    momentumStrip
                        .padding(.horizontal, 20)
                }

                if !libraryVM.songs.isEmpty {
                    library
                }

                sampleScans

                starterPieces

                Spacer(minLength: 16)
            }
            .padding(.top, 4)
        }
        .statusBarScrim()
        .stageBackground()
        .navigationBarHidden(true)
        .task { HomeArt.shared.warm() }
        .sheet(isPresented: $showSettings, onDismiss: {
            if tourAfterSettings {
                tourAfterSettings = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showTutorial = true }
            }
        }) {
            SettingsView(startTour: $tourAfterSettings)
                .environment(scanAccount)
                .environment(scanStore)
                .environment(themeManager)
        }
        // Scan: the document camera, then the scan screen with the pages.
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            guard !capturedPages.isEmpty else { return }
            scanSession = ScanSession(pages: capturedPages)
            capturedPages = []
        }) {
            DocumentCameraView { capturedPages = $0 }
                .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection,
                      maxSelectionCount: ScanCloudConfig.maxPagesPerScan, matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let pages = await ScanPageLoader.pages(from: items)
                photoSelection = []
                // Let the picker finish dismissing before presenting.
                try? await Task.sleep(for: .milliseconds(350))
                if pages.isEmpty {
                    importError = "Those photos couldn't be read."
                } else {
                    scanSession = ScanSession(pages: pages)
                }
            }
        }
        // Import: MusicXML goes straight into the library; PDFs and images get scanned.
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.musicXML, .compressedMusicXML, .xml, .pdf, .image],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .fullScreenCover(item: $scanSession) { session in
            SheetScanView(session: session, selectedSong: $selectedSong, tabSelection: $tabSelection)
                .environment(libraryVM)
                .environment(scanAccount)
                .environment(scanStore)
        }
        .alert("Couldn't Import", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("Storage Error", isPresented: Binding(
            get: { libraryVM.saveError != nil },
            set: { if !$0 { libraryVM.saveError = nil } }
        )) {
            Button("OK", role: .cancel) { libraryVM.saveError = nil }
        } message: {
            Text(libraryVM.saveError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            CascadeWordmark(size: 34)
            Spacer(minLength: 8)
            if statsManager.currentStreak > 0 {
                Button { tabSelection = 3 } label: {
                    Chip(text: "\(statsManager.currentStreak)", icon: "flame.fill", tint: Brand.amber)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(statsManager.currentStreak) day streak")
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Up next

    private func upNextCard(_ song: Song) -> some View {
        let playback = libraryVM.cachedPlayback(for: song)
        let difficulty = DifficultyAnalyzer.analyze(playback: playback)

        return Button {
            selectedSong = song
            tabSelection = 2
        } label: {
            ZStack(alignment: .bottomLeading) {
                ScoreArtView(playback: playback, window: 16, cornerRadius: 28)
                    .frame(height: 300)

                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(song.lastPlayedAt == nil ? "Up next" : "Continue practicing")
                        .eyebrowStyle(.white.opacity(0.7))
                    Text(song.title)
                        .font(CascadeFont.display(30))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 8) {
                        Chip(text: difficulty.level.label, icon: difficulty.level.icon, tint: difficulty.level.brandColor, filled: true)
                        Chip(text: formatClock(song.durationSeconds), icon: "clock", tint: .white)
                        Spacer()
                        ZStack {
                            Circle().fill(.white).frame(width: 52, height: 52)
                            Image(systemName: "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(Brand.ink)
                                .offset(x: 2)
                        }
                        .glow(Brand.teal, radius: 14, opacity: 0.6)
                    }
                }
                .padding(22)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue practicing \(song.title)")
    }

    /// No songs yet: the product in one picture.
    private var emptyHero: some View {
        ZStack(alignment: .bottomLeading) {
            ScoreArtView(playback: SongLibraryView.demoPlayback, window: 10, cornerRadius: 28)
                .frame(height: 250)
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Start here").eyebrowStyle(.white.opacity(0.7))
                Text("Sheet music in.\nFalling notes out.")
                    .font(CascadeFont.display(30))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .padding(.bottom, 34)
        }
    }

    /// A little C-major figure so the empty state still shows real art.
    private static let demoPlayback: PlaybackData = {
        let pitches = [60, 64, 67, 72, 76, 72, 67, 64, 62, 65, 69, 74, 77, 74, 69, 65]
        let lh = [48, 43, 45, 41]
        var notes: [NoteEvent] = []
        for (i, p) in pitches.enumerated() {
            notes.append(NoteEvent(pitch: p, startTime: Double(i) * 0.5, duration: 0.45, voice: 1))
        }
        for (i, p) in lh.enumerated() {
            notes.append(NoteEvent(pitch: p, startTime: Double(i) * 2.0, duration: 1.9, voice: 2))
        }
        return PlaybackData(tempo: 120, totalDuration: 8, notes: notes.sorted { $0.startTime < $1.startTime })
    }()

    // MARK: - Scan & Import

    private var addMusic: some View {
        HStack(spacing: 12) {
            Button(action: startScan) {
                ActionTileLabel(title: "Scan", subtitle: "Sheet music on paper", tint: Brand.teal) {
                    ScanTileArt()
                }
            }
            .buttonStyle(TileButtonStyle())
            .contextMenu {
                if DocumentCameraView.isAvailable {
                    Button { showCamera = true } label: { Label("Use camera", systemImage: "camera") }
                }
                Button { showPhotoPicker = true } label: { Label("Choose from Photos", systemImage: "photo.on.rectangle") }
            }
            .accessibilityLabel("Scan sheet music")

            Button { showImporter = true } label: {
                ActionTileLabel(title: "Import", subtitle: "PDF or MusicXML", tint: Brand.amber) {
                    ImportTileArt()
                }
            }
            .buttonStyle(TileButtonStyle())
            .accessibilityLabel("Import a file")
        }
    }

    private func startScan() {
        if DocumentCameraView.isAvailable {
            showCamera = true
        } else {
            showPhotoPicker = true
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        let urls: [URL]
        switch result {
        case .success(let picked): urls = picked
        case .failure(let error):
            importError = error.localizedDescription
            return
        }
        guard !urls.isEmpty else { return }

        // Score files go straight into the library and open in the player.
        let scoreFiles = urls.filter(ScoreFileImport.isScoreFile)
        if !scoreFiles.isEmpty {
            var lastAdded: Song?
            var problems: [String] = []
            for url in scoreFiles {
                do {
                    let score = try ScoreFileImport.read(url)
                    lastAdded = libraryVM.addSong(title: score.title, musicXML: score.musicXML)
                } catch {
                    problems.append(error.localizedDescription)
                }
            }
            if let lastAdded {
                selectedSong = lastAdded
                tabSelection = 2
            }
            if !problems.isEmpty { importError = problems.joined(separator: "\n\n") }
            return
        }

        // PDFs and images are sheet music to scan.
        let loaded = ScanPageLoader.pages(from: urls)
        guard !loaded.pages.isEmpty else {
            importError = "Couldn't read \(loaded.unreadable.joined(separator: ", "))."
            return
        }
        // Let the Files sheet finish dismissing before presenting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            scanSession = ScanSession(pages: loaded.pages, title: loaded.title)
        }
    }

    // MARK: - Momentum

    private var momentumStrip: some View {
        HStack(spacing: 0) {
            momentum(statsManager.formattedTotalTime, "practiced")
            divider
            momentum("\(statsManager.sessionsCount)", "sessions")
            divider
            momentum("\(statsManager.songsCompleted)", "completed")
            divider
            momentum("\(achievementManager.earnedCount)/\(achievementManager.totalCount)", "awards")
        }
        .cascadeCard(padding: 14, radius: 20)
        .onTapGesture { tabSelection = 3 }
    }

    private var divider: some View {
        Rectangle().fill(Brand.hairline).frame(width: 1, height: 28)
    }

    private func momentum(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(CascadeFont.number(17))
                .foregroundStyle(Brand.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Library

    private var library: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Your library", subtitle: "\(libraryVM.songs.count) piece\(libraryVM.songs.count == 1 ? "" : "s")")
                .padding(.horizontal, 20)

            VStack(spacing: 10) {
                ForEach(libraryVM.songs) { song in
                    songRow(song)
                        .scrollTransition(.animated(.spring(response: 0.4, dampingFraction: 0.75))) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0)
                                .offset(y: phase.isIdentity ? 0 : 16)
                        }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func songRow(_ song: Song) -> some View {
        let playback = libraryVM.cachedPlayback(for: song)
        let difficulty = DifficultyAnalyzer.analyze(playback: playback)

        return Button {
            selectedSong = song
            tabSelection = 2
        } label: {
            HStack(spacing: 14) {
                ScoreArtView(playback: playback, window: 8, cornerRadius: 12)
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text(difficulty.level.label)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(difficulty.level.brandColor)
                        Text("·").foregroundStyle(Brand.textTertiary)
                        Text(formatClock(song.durationSeconds))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                        Text("·").foregroundStyle(Brand.textTertiary)
                        Text("\(playback.notes.count) notes")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(Brand.surfaceHigh, in: Circle())
            }
            .cascadeCard(padding: 12, radius: 20)
        }
        .buttonStyle(.plain)
        .contextMenu {
            NavigationLink {
                SongDetailView(song: song, selectedSong: $selectedSong, tabSelection: $tabSelection)
                    .environment(libraryVM)
                    .environment(themeManager)
            } label: {
                Label("Details", systemImage: "info.circle")
            }
            Button(role: .destructive) {
                libraryVM.deleteSong(song)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(song.title), \(difficulty.level.label) difficulty, \(formatClock(song.durationSeconds))")
    }

    // MARK: - Sample scans

    private var sampleScans: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("See a scan", subtitle: "Real sheet music, converted free")
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(SampleScan.all) { sample in
                        Button {
                            scanSession = ScanSession(pages: sample.loadPages(), title: sample.title, sample: sample)
                        } label: {
                            SampleScanCard(sample: sample)
                        }
                        .buttonStyle(TileButtonStyle())
                        .accessibilityLabel("Sample: \(sample.title)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("sampleScans")
        }
    }

    // MARK: - Starter pieces

    private var starterPieces: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Starter pieces", subtitle: "Free and ready to play")
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(DemoSongs.all, id: \.resourceName) { demo in
                        Button {
                            if let song = libraryVM.addStarter(demo) {
                                selectedSong = song
                                tabSelection = 2
                            }
                        } label: {
                            StarterCard(demo: demo, inLibrary: libraryVM.songs.contains { $0.title == demo.title })
                        }
                        .buttonStyle(TileButtonStyle())
                        .accessibilityLabel("\(demo.title) by \(demo.composer)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("starterPieces")
        }
    }
}

// MARK: - Tiles

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ActionTileLabel<Art: View>: View {
    let title: String
    let subtitle: String
    let tint: Color
    @ViewBuilder var art: () -> Art

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            art()
                .frame(height: 70)
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Brand.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Brand.surface)
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(RadialGradient(colors: [tint.opacity(0.24), .clear], center: .top, startRadius: 0, endRadius: 150))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Brand.hairline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// A bar of music inside a viewfinder, with the scan light passing over it.
private struct ScanTileArt: View {
    var body: some View {
        ZStack {
            Canvas { context, size in
                let gap: CGFloat = 6
                let top = size.height / 2 - gap * 2
                let left: CGFloat = 20
                let right = size.width - 20
                for i in 0..<5 {
                    context.fill(Path(CGRect(x: left, y: top + CGFloat(i) * gap, width: right - left, height: 1)),
                                 with: .color(.white.opacity(0.32)))
                }
                // Treble-ish figure: (x fraction, staff step from the top line, stem up)
                let figure: [(CGFloat, CGFloat)] = [(0.18, 3.5), (0.36, 2.5), (0.54, 1.5), (0.72, 2.0), (0.88, 3.0)]
                for (fx, step) in figure {
                    let cx = left + (right - left) * fx
                    let cy = top + step * gap
                    let head = Path(ellipseIn: CGRect(x: -4, y: -3, width: 8, height: 6))
                        .applying(CGAffineTransform(rotationAngle: -0.35))
                        .applying(CGAffineTransform(translationX: cx, y: cy))
                    context.fill(head, with: .color(.white.opacity(0.9)))
                    context.fill(Path(CGRect(x: cx + 3, y: cy - 18, width: 1.3, height: 18)), with: .color(.white.opacity(0.9)))
                }
                // Beam over the last pair
                let bx1 = left + (right - left) * 0.72 + 3, bx2 = left + (right - left) * 0.88 + 4.3
                var beam = Path()
                beam.move(to: CGPoint(x: bx1, y: top + 2.0 * gap - 18))
                beam.addLine(to: CGPoint(x: bx2, y: top + 3.0 * gap - 18))
                beam.addLine(to: CGPoint(x: bx2, y: top + 3.0 * gap - 14.5))
                beam.addLine(to: CGPoint(x: bx1, y: top + 2.0 * gap - 14.5))
                beam.closeSubpath()
                context.fill(beam, with: .color(.white.opacity(0.9)))
            }

            ViewfinderCorners()
                .stroke(Brand.teal, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .padding(.horizontal, 6)

            Capsule()
                .fill(Brand.teal)
                .frame(height: 2.5)
                .padding(.horizontal, 12)
                .shadow(color: Brand.teal, radius: 6)
                .offset(y: 9)
        }
    }
}

private struct ViewfinderCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let arm: CGFloat = 12
        let r: CGFloat = 6
        var p = Path()
        // top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + arm + r))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + arm + r, y: rect.minY))
        // top-right
        p.move(to: CGPoint(x: rect.maxX - arm - r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm + r))
        // bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm - r))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - arm - r, y: rect.maxY))
        // bottom-left
        p.move(to: CGPoint(x: rect.minX + arm + r, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm - r))
        return p
    }
}

/// Two files fanned out: a PDF and a MusicXML score.
private struct ImportTileArt: View {
    var body: some View {
        ZStack {
            sheet(label: "PDF", tagAlignment: .bottomLeading)
                .rotationEffect(.degrees(-10))
                .offset(x: -22, y: 3)
            sheet(label: "XML", tagAlignment: .bottomTrailing)
                .rotationEffect(.degrees(7))
                .offset(x: 18, y: -1)
        }
    }

    private func sheet(label: String, tagAlignment: Alignment) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(red: 0.95, green: 0.94, blue: 0.91))
            .frame(width: 46, height: 60)
            .overlay(alignment: .top) {
                VStack(spacing: 9) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { _ in
                                Rectangle().fill(Color.black.opacity(0.28)).frame(height: 0.7)
                            }
                        }
                    }
                }
                .padding(.horizontal, 7)
                .padding(.top, 9)
            }
            .overlay(alignment: tagAlignment) {
                Text(label)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Brand.amber, in: Capsule())
                    .offset(x: tagAlignment == .bottomLeading ? -7 : 7, y: 4)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

// MARK: - Cards

/// The printed page on top, the falling notes it becomes underneath.
private struct SampleScanCard: View {
    let sample: SampleScan
    private var art: HomeArt { HomeArt.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                if let thumb = art.pageThumbnails[sample.id] {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 136, height: 176, alignment: .top)
                        .clipped()
                        .transition(.opacity)
                }
                if let playback = art.playbacks[sample.xmlResource] {
                    ScoreArtView(playback: playback, window: 6, cornerRadius: 0)
                        .frame(width: 136, height: 84)
                        .mask(
                            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.35)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .transition(.opacity)
                }
            }
            .frame(width: 136, height: 176)
            .background(Color(red: 0.97, green: 0.97, blue: 0.95))
            .animation(.easeOut(duration: 0.3), value: art.pageThumbnails[sample.id] != nil)
            .animation(.easeOut(duration: 0.3), value: art.playbacks[sample.xmlResource] != nil)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Brand.ink)
                    .frame(width: 22, height: 22)
                    .background(Brand.teal, in: Circle())
                    .padding(7)
            }
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 1) {
                Text(sample.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                Text(sample.composer)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(width: 136, alignment: .leading)
    }
}

private struct StarterCard: View {
    let demo: DemoSongs.DemoSong
    let inLibrary: Bool

    private var tint: Color {
        switch demo.difficulty {
        case "Beginner": return Brand.mint
        case "Intermediate": return Brand.amber
        default: return Brand.coral
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Brand.surfaceHigh)
                if let playback = HomeArt.shared.playbacks[demo.resourceName] {
                    ScoreArtView(playback: playback, window: 10, cornerRadius: 18)
                        .transition(.opacity)
                }
            }
            .frame(width: 150, height: 150)
            .animation(.easeOut(duration: 0.3), value: HomeArt.shared.playbacks[demo.resourceName] != nil)
            .overlay(alignment: .topTrailing) {
                if inLibrary {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.ink)
                        .frame(width: 22, height: 22)
                        .background(Brand.mint, in: Circle())
                        .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(demo.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Text(demo.composer)
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 150, alignment: .leading)
    }
}
