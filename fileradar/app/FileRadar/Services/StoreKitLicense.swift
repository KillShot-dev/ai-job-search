import Foundation
import StoreKit

/// Mac App Store purchase path (StoreKit 2).
///
/// Product id comes from Info.plist `FRStoreKitProductID` (public, not a
/// secret). No shared secrets, no receipt-validation private keys, and no
/// hardcoded Apple credentials live in the client — App Store Connect owns
/// pricing; StoreKit owns entitlement verification via
/// `Transaction.currentEntitlements`.
///
/// Direct / website builds keep serial + optional HTTPS licensing server
/// (see `LicenseServerClient`). Do not call StoreKit purchase flows from a
/// Developer ID build that also sells serials on the same binary without a
/// clear UX fork — Apple rejects dual-commerce on MAS builds.
@MainActor
final class StoreKitLicense: ObservableObject {
    @Published private(set) var isEntitled = false
    @Published private(set) var product: Product?
    @Published private(set) var lastError: String?
    @Published private(set) var isLoading = false

    private var listenTask: Task<Void, Never>?

    init() {
        listenTask = Task { await listenForTransactions() }
        Task { await refresh() }
    }

    deinit { listenTask?.cancel() }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        do {
            let products = try await Product.products(for: [DistributionChannel.storeKitProductID])
            product = products.first
        } catch {
            // Generic message only — never echo StoreKit internals that
            // might include account details.
            lastError = "Store products could not be loaded."
            product = nil
        }
        await updateEntitlement()
    }

    func purchase() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        do {
            if product == nil { await refresh() }
            guard let product else {
                lastError = "The full version is not available in the store yet."
                return
            }
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updateEntitlement()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = "Purchase could not be completed."
        }
    }

    func restore() async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil
        do {
            try await AppStore.sync()
            await updateEntitlement()
            if !isEntitled {
                lastError = "No previous purchase was found for this Apple ID."
            }
        } catch {
            lastError = "Purchases could not be restored."
        }
    }

    private func updateEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == DistributionChannel.storeKitProductID,
               transaction.revocationDate == nil {
                entitled = true
                break
            }
        }
        isEntitled = entitled
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if let transaction = try? checkVerified(result) {
                await transaction.finish()
                await updateEntitlement()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.unverified
        case .verified(let safe):
            return safe
        }
    }

    private enum StoreError: Error { case unverified }
}
