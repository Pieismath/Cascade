//
//  ScanStore.swift
//  MyPianoInstructor
//
//  In-app purchases for scan credits (StoreKit 2 consumables). The device
//  never decides how many credits it has: after a purchase the signed
//  transaction goes to the cascade-scan worker, which verifies Apple's
//  signature and adds credits to the account. Only then is the transaction
//  finished, so a redemption that fails (no network) is retried later.
//

import StoreKit
import Observation

@MainActor
@Observable
final class ScanStore {

    /// Must match App Store Connect and the worker's PRODUCTS table.
    static let productIDs = [
        "jhfang.MyPianoInstructor2.scans10",
        "jhfang.MyPianoInstructor2.scans25",
    ]

    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var loadError: String? = nil

    /// Set after a successful redemption so the UI can celebrate briefly.
    var lastGrantedCredits: Int? = nil

    let account: ScanAccountManager

    init(account: ScanAccountManager) {
        self.account = account
        // Transactions can arrive outside a purchase call (Ask to Buy,
        // interrupted purchases, other devices). Redeem them as they come.
        // The loop holds self weakly and ends on its own when the store goes away.
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.redeem(result)
            }
        }
    }

    // MARK: Products

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted { $0.price < $1.price }
            loadError = fetched.isEmpty ? "Scan packs aren't available right now." : nil
        } catch {
            loadError = "Couldn't load scan packs: \(error.localizedDescription)"
        }
    }

    /// Credits granted by a product, for display before purchase.
    static func credits(for product: Product) -> Int {
        if product.id.hasSuffix("scans25") { return 25 }
        if product.id.hasSuffix("scans10") { return 10 }
        return 0
    }

    // MARK: Purchase

    enum PurchaseOutcome {
        case granted(Int)
        case pending
        case cancelled
    }

    func purchase(_ product: Product) async throws -> PurchaseOutcome {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let granted = try await redeemOrThrow(verification)
            return .granted(granted)
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Re-sends any transaction whose redemption never completed. Also what
    /// "Restore Purchases" does for consumables.
    func redeemPending() async -> Int {
        var granted = 0
        for await result in Transaction.unfinished {
            granted += (try? await redeemOrThrow(result)) ?? 0
        }
        return granted
    }

    // MARK: Redemption

    private func redeem(_ result: VerificationResult<Transaction>) async {
        _ = try? await redeemOrThrow(result)
    }

    @discardableResult
    private func redeemOrThrow(_ result: VerificationResult<Transaction>) async throws -> Int {
        guard case .verified(let transaction) = result else {
            // StoreKit itself couldn't verify it; leave it unfinished.
            throw ScanCloudError.invalidPurchase("This purchase could not be verified.")
        }
        guard Self.productIDs.contains(transaction.productID) else {
            await transaction.finish()
            return 0
        }
        if transaction.revocationDate != nil {
            await transaction.finish()
            return 0
        }

        let response = try await account.redeem(signedTransaction: result.jwsRepresentation)
        await transaction.finish()
        if response.added > 0 { lastGrantedCredits = response.added }
        return response.added
    }
}
