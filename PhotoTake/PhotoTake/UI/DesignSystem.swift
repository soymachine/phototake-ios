import SwiftUI

enum DS {
    enum Color {
        static let accent = SwiftUI.Color.yellow
        static let background = SwiftUI.Color.black
        static let surface = SwiftUI.Color(white: 0.1)
        static let surfaceSecondary = SwiftUI.Color(white: 0.15)
        static let textPrimary = SwiftUI.Color.white
        static let textSecondary = SwiftUI.Color(white: 0.6)
    }

    enum Font {
        static let mono = SwiftUI.Font.system(.body, design: .monospaced)
        static let monoSmall = SwiftUI.Font.system(.caption, design: .monospaced)
        static let title = SwiftUI.Font.system(.title2, design: .monospaced, weight: .semibold)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Corner {
        static let sm: CGFloat = 6
        static let md: CGFloat = 12
    }
}

struct SliderRow: View {
    let label: String
    let systemImage: String
    @Binding var value: Float
    let range: ClosedRange<Float>

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 20)
                    .foregroundStyle(DS.Color.textSecondary)
                Text(label)
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Slider(value: $value, in: range)
                .tint(DS.Color.accent)
        }
    }
}
