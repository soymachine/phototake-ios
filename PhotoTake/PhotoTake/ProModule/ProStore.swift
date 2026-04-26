import StoreKit
import SwiftUI

@MainActor
final class ProStore: ObservableObject {

    // MARK: - State

    @Published private(set) var isPro: Bool = false
    @Published private(set) var scansThisMonth: Int = 0
    @Published private(set) var products: [Product] = []
    @Published var purchaseError: String? = nil

    static let freeMonthlyLimit = 10
    static let monthlyProductID = "com.phototake.pro.monthly"
    static let annualProductID  = "com.phototake.pro.annual"

    // MARK: - Computed gates

    var canScan: Bool             { isPro || scansThisMonth < Self.freeMonthlyLimit }
    var scansRemaining: Int       { max(0, Self.freeMonthlyLimit - scansThisMonth) }
    var canUseColor: Bool         { isPro }
    /// Save to in-app gallery: always allowed; Pro removes watermark + enables full res.
    /// Download to system Photos app: Pro only.
    var canDownloadToPhotos: Bool { isPro }
    var needsWatermark: Bool      { !isPro }

    // MARK: - Persistence keys

    private let isProKey = "pro.isPro"
    private var scanKey: String {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return "pro.scans.\(c.year!).\(c.month!)"
    }

    // MARK: - Init

    init() {
        isPro = UserDefaults.standard.bool(forKey: isProKey)
        scansThisMonth = UserDefaults.standard.integer(forKey: scanKey)
        Task { await loadProducts() }
        Task { await listenForTransactions() }
    }

    // MARK: - Scan tracking

    func recordScan() {
        guard !isPro else { return }
        scansThisMonth += 1
        UserDefaults.standard.set(scansThisMonth, forKey: scanKey)
    }

    // MARK: - StoreKit 2

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let fetched = try await Product.products(
                for: [Self.monthlyProductID, Self.annualProductID])
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            // Products not available in this environment (simulator / no entitlement)
        }
    }

    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let tx) = verification else {
                    purchaseError = "Verification failed"; return
                }
                await tx.finish()
                setPro(true)
            case .userCancelled: break
            case .pending:       break
            @unknown default:    break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result, tx.revocationDate == nil {
                setPro(true)
                return
            }
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let tx) = result {
                await tx.finish()
                await refreshEntitlements()
            }
        }
    }

    private func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: isProKey)
    }

    // MARK: - Debug

    #if DEBUG
    func debugTogglePro() { setPro(!isPro) }
    #endif
}
