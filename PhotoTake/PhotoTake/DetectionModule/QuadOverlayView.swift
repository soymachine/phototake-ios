import SwiftUI

struct QuadOverlayView: View {
    @Binding var corners: [CGPoint]
    let viewSize: CGSize
    var animated: Bool = true

    var body: some View {
        ZStack {
            // Fill
            quadPath
                .fill(Color.yellow.opacity(0.12))

            // Stroke
            quadPath
                .stroke(Color.yellow, lineWidth: 2)

            // Corner handles
            ForEach(corners.indices, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.yellow, lineWidth: 2))
                    .position(corners[i])
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let clamped = CGPoint(
                                    x: max(0, min(viewSize.width, value.location.x)),
                                    y: max(0, min(viewSize.height, value.location.y))
                                )
                                corners[i] = clamped
                            }
                    )
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .animation(animated ? .easeOut(duration: 0.2) : nil, value: corners)
    }

    private var quadPath: Path {
        guard corners.count == 4 else { return Path() }
        return Path { p in
            p.move(to: corners[0])
            p.addLine(to: corners[1])
            p.addLine(to: corners[2])
            p.addLine(to: corners[3])
            p.closeSubpath()
        }
    }
}
