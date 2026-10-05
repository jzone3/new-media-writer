import SwiftUI

/// The small pill in the top-right corner that swaps the document view.
struct ViewSwitcher: View {
    @Binding var mode: ViewMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { m in
                Button { mode = m } label: {
                    icon(for: m)
                        .frame(width: 32, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(m.title) (\(m.shortcutLabel))")
                .foregroundStyle(mode == m ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(mode == m ? Color.primary.opacity(0.1) : Color.clear)
                )
            }
        }
        .padding(3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    @ViewBuilder
    private func icon(for mode: ViewMode) -> some View {
        switch mode {
        case .plaintext: Image(systemName: "doc.plaintext").font(.system(size: 12, weight: .semibold))
        case .markdown: Text("M↓").font(.system(size: 11, weight: .heavy, design: .rounded))
        case .xPost: Text("𝕏").font(.system(size: 14, weight: .bold))
        case .linkedin: Text("in").font(.system(size: 14, weight: .heavy, design: .rounded))
        case .slack: Image(systemName: "number").font(.system(size: 13, weight: .bold))
        }
    }
}
