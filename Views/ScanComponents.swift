//
//  ScanComponents.swift
//  MyPianoInstructor
//
//  Pieces of the scan experience shared by Home, the scan screen, and
//  Settings: the document camera, Sign in with Apple, scan packs, the scan
//  balance, and the privacy explainer.
//

import SwiftUI
import VisionKit
import AuthenticationServices
import StoreKit

// MARK: - Document camera

/// VisionKit's document scanner: multi-page capture with edge detection,
/// perspective correction, and shadow removal — ideal input for recognition.
struct DocumentCameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onScan: ([UIImage]) -> Void

    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

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
            onScan((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
            dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            dismiss()
        }
    }
}

// MARK: - Sign in

/// Sign in with Apple for the scan service. Asks for no name or email.
struct ScanSignInButton: View {
    @Environment(ScanAccountManager.self) private var account
    var onError: (String) -> Void

    var body: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = []
        } onCompletion: { result in
            Task {
                switch result {
                case .success(let authorization):
                    do {
                        try await account.signIn(with: authorization)
                    } catch {
                        onError(error.localizedDescription)
                    }
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code != .canceled {
                        onError(error.localizedDescription)
                    }
                }
            }
        }
        .signInWithAppleButtonStyle(.white)
        .frame(height: 52)
        .clipShape(Capsule())
    }
}

// MARK: - Scan packs

/// The scan packs for sale, each with its price button.
struct ScanPacksList: View {
    let store: ScanStore
    var onGranted: (String) -> Void
    var onError: (String) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if store.products.isEmpty {
                Group {
                    if store.isLoadingProducts {
                        ProgressView()
                    } else {
                        Text(store.loadError ?? "Scan packs aren't available right now.")
                            .font(.footnote)
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(store.products, id: \.id) { product in
                    row(product)
                }
            }
        }
        .task { await store.loadProducts() }
    }

    private func row(_ product: Product) -> some View {
        let credits = ScanStore.credits(for: product)
        return HStack(spacing: 14) {
            PackBars(count: credits)
            VStack(alignment: .leading, spacing: 2) {
                Text(credits > 0 ? "\(credits) scans" : product.displayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                if credits > 0 {
                    Text("\((product.price / Decimal(credits)).formatted(product.priceFormatStyle)) per scan")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            Spacer()
            Button {
                buy(product)
            } label: {
                Text(product.displayPrice)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Brand.teal, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.isPurchasing)
            .opacity(store.isPurchasing ? 0.5 : 1)
            .accessibilityLabel("Buy \(credits) scans for \(product.displayPrice)")
        }
        .padding(14)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Brand.hairline, lineWidth: 1))
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

/// A tiny cluster of note bars whose size hints at the pack size.
private struct PackBars: View {
    let count: Int
    var body: some View {
        let heights: [CGFloat] = count >= 25 ? [14, 24, 18, 30, 22] : [16, 26, 20]
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(heights.indices, id: \.self) { i in
                Capsule()
                    .fill(i % 2 == 0 ? Brand.teal : Brand.amber)
                    .frame(width: 5, height: heights[i])
            }
        }
        .frame(width: 40, height: 32, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Balance

/// Scans left as a number over a row of note bars, one lit per scan.
struct ScanBalanceView: View {
    let remaining: Int

    private static let heights: [CGFloat] = [18, 30, 22, 38, 26, 16, 34, 24, 40, 20, 30, 18]

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(remaining)")
                    .font(CascadeFont.number(48))
                    .foregroundStyle(Brand.textPrimary)
                    .contentTransition(.numericText())
                Text(remaining == 1 ? "scan left" : "scans left")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Self.heights.indices, id: \.self) { i in
                    let lit = i < remaining
                    Capsule()
                        .fill(lit ? (i % 3 == 1 ? Brand.amber : Brand.teal) : Brand.surfaceHigh)
                        .frame(width: 6, height: Self.heights[i])
                        .shadow(color: lit ? Brand.teal.opacity(0.35) : .clear, radius: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Privacy

struct ScanPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How scanning works")
                        .font(CascadeFont.display(28))
                        .foregroundStyle(Brand.textPrimary)
                    Text("When you convert a scan, the page images are uploaded over an encrypted connection to Cascade's recognition service, which uses a third-party AI provider to read the notation and send back the notes. Cascade doesn't keep the images.")
                    Text("Sign in with Apple gives Cascade an anonymous ID only, never your name or email. It holds your free scan and any scan packs you buy.")
                    Text("Everything else stays on this device: your library, practice history, and exported videos.")
                    if let url = ScanCloudConfig.privacyPolicyURL {
                        Link("Read the privacy policy", destination: url)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                }
                .font(.body)
                .foregroundStyle(Brand.textSecondary)
                .padding(20)
            }
            .stageBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
