import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject var proStore: ProStore
    @Environment(\.dismiss) var dismiss

    @State private var selected: String = ProStore.annualProductID
    @State private var isPurchasing = false
    @State private var isRestoring  = false

    private var annualProduct:  Product? { proStore.products.first { $0.id == ProStore.annualProductID  } }
    private var monthlyProduct: Product? { proStore.products.first { $0.id == ProStore.monthlyProductID } }

    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    featureTable
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                    planPicker
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                    ctaButton
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    footer
                        .padding(.top, 12)
                        .padding(.bottom, 36)
                }
            }

            // Close button
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Error", isPresented: Binding(
            get: { proStore.purchaseError != nil },
            set: { if !$0 { proStore.purchaseError = nil } }
        )) {
            Button("OK", role: .cancel) { proStore.purchaseError = nil }
        } message: {
            Text(proStore.purchaseError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(DS.Color.accent)
                .padding(.top, 60)

            Text("PhotoTake Pro")
                .font(.system(.title, design: .monospaced, weight: .bold))
                .foregroundStyle(DS.Color.textPrimary)

            Text("Full resolution. Full color. No limits.")
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Feature table

    private var featureTable: some View {
        VStack(spacing: 0) {
            featureHeader
            ForEach(Feature.all) { f in
                featureRow(f)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.lg))
        .overlay(RoundedRectangle(cornerRadius: DS.Corner.lg)
            .stroke(DS.Color.surfaceSecondary, lineWidth: 1))
    }

    private var featureHeader: some View {
        HStack(spacing: 0) {
            Text("").frame(maxWidth: .infinity, alignment: .leading)
            Text("FREE").font(DS.Font.monoCaption).foregroundStyle(DS.Color.textSecondary)
                .frame(width: 80, alignment: .center)
            Text("PRO").font(DS.Font.monoCaption).foregroundStyle(DS.Color.accent)
                .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DS.Color.surfaceSecondary)
    }

    private func featureRow(_ f: Feature) -> some View {
        HStack(spacing: 0) {
            Text(f.label)
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(f.freeValue)
                .font(DS.Font.monoCaption)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(width: 80, alignment: .center)

            Group {
                if f.proIcon {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 13, weight: .bold))
                } else {
                    Text(f.proValue)
                        .font(DS.Font.monoCaption)
                        .foregroundStyle(DS.Color.accent)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 80, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(DS.Color.surface)
        .overlay(alignment: .top) {
            DS.Color.surfaceSecondary.frame(height: 1)
        }
    }

    // MARK: - Plan picker

    private var planPicker: some View {
        VStack(spacing: 10) {
            planCard(
                productID: ProStore.annualProductID,
                title: "Annual",
                badge: "BEST VALUE",
                price: annualProduct.map { "\($0.displayPrice)/year" } ?? "$19.99/year",
                sub: annualProduct.map { "≈ \(monthlyEquivalent($0))/month" } ?? "≈ $1.67/month"
            )
            planCard(
                productID: ProStore.monthlyProductID,
                title: "Monthly",
                badge: nil,
                price: monthlyProduct.map { "\($0.displayPrice)/month" } ?? "$3.99/month",
                sub: nil
            )
        }
    }

    private func planCard(productID: String, title: String, badge: String?,
                          price: String, sub: String?) -> some View {
        let isSelected = selected == productID
        return Button(action: { selected = productID }) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(DS.Font.mono).foregroundStyle(DS.Color.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(DS.Font.monoCaption)
                                .foregroundStyle(DS.Color.background)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(DS.Color.accent)
                                .clipShape(Capsule())
                        }
                    }
                    if let sub {
                        Text(sub).font(DS.Font.monoCaption).foregroundStyle(DS.Color.textSecondary)
                    }
                }
                Spacer()
                Text(price).font(DS.Font.mono).foregroundStyle(DS.Color.textPrimary)
            }
            .padding(16)
            .background(isSelected ? DS.Color.accent.opacity(0.12) : DS.Color.surface)
            .overlay(RoundedRectangle(cornerRadius: DS.Corner.md)
                .stroke(isSelected ? DS.Color.accent : DS.Color.surfaceSecondary,
                        lineWidth: isSelected ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md))
        }
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button(action: { Task { await buy() } }) {
            Group {
                if isPurchasing {
                    ProgressView().tint(DS.Color.background)
                } else {
                    Text("Start Pro")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.background)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DS.Color.accent)
            .clipShape(RoundedRectangle(cornerRadius: DS.Corner.md))
        }
        .disabled(isPurchasing || isRestoring)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button(action: { Task { await restore() } }) {
                if isRestoring {
                    ProgressView().tint(DS.Color.accent).scaleEffect(0.8)
                } else {
                    Text("Restore purchases")
                        .font(DS.Font.monoCaption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .underline()
                }
            }
            .disabled(isPurchasing || isRestoring)

            Text("Subscription renews automatically. Cancel anytime.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DS.Color.textSecondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Actions

    private func buy() async {
        let product: Product?
        if selected == ProStore.annualProductID { product = annualProduct }
        else { product = monthlyProduct }

        guard let product else {
            // Products not loaded yet (simulator): unlock pro directly in DEBUG
            #if DEBUG
            proStore.debugTogglePro()
            dismiss()
            #endif
            return
        }
        isPurchasing = true
        await proStore.purchase(product)
        isPurchasing = false
        if proStore.isPro { dismiss() }
    }

    private func restore() async {
        isRestoring = true
        await proStore.restorePurchases()
        isRestoring = false
        if proStore.isPro { dismiss() }
    }

    private func monthlyEquivalent(_ product: Product) -> String {
        let monthly = product.price / 12
        return product.priceFormatStyle.format(monthly)
    }
}

// MARK: - Feature list model

private struct Feature: Identifiable {
    let id = UUID()
    let label: String
    let freeValue: String
    let proValue: String
    var proIcon: Bool = false

    static let all: [Feature] = [
        Feature(label: "Scans/month",  freeValue: "10",     proValue: "∞"),
        Feature(label: "Resolution",   freeValue: "1080p",  proValue: "Full"),
        Feature(label: "Color output", freeValue: "B/W",    proValue: "Color", proIcon: true),
        Feature(label: "Save to Gallery", freeValue: "—",   proValue: "",      proIcon: true),
        Feature(label: "Watermark",    freeValue: "Subtle", proValue: "None",  proIcon: false),
    ]
}
