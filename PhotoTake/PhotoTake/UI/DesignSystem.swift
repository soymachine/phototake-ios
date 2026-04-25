import SwiftUI

enum DS {
    enum Color {
        static let accent          = SwiftUI.Color(red: 1.0, green: 0.45, blue: 0.1)
        static let background      = SwiftUI.Color.black
        static let surface         = SwiftUI.Color(white: 0.11)
        static let surfaceSecondary = SwiftUI.Color(white: 0.18)
        static let textPrimary     = SwiftUI.Color.white
        static let textSecondary   = SwiftUI.Color(white: 0.55)
    }

    enum Font {
        static let mono        = SwiftUI.Font.system(.body,    design: .monospaced)
        static let monoSmall   = SwiftUI.Font.system(.caption, design: .monospaced)
        static let monoCaption = SwiftUI.Font.system(.caption2, design: .monospaced, weight: .semibold)
        static let title       = SwiftUI.Font.system(.title2,  design: .monospaced, weight: .semibold)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Corner {
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
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
                    .foregroundStyle(DS.Color.accent)
                Text(label)
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(DS.Font.monoCaption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Slider(value: $value, in: range)
                .tint(DS.Color.accent)
        }
    }
}
