import SwiftUI

/// The small pill in the top-right corner that swaps the document view.
struct ViewSwitcher: View {
    @Binding var mode: ViewMode

    var body: some View {
        HStack(spacing: 2) {
            segment(active: mode.isEditor, label: {
                Image(systemName: "text.alignleft").font(.system(size: 12, weight: .semibold))
            }, action: { mode = .markdown }, help: "Markdown (⌘1)") {
                Button { mode = .markdown } label: {
                    Label("Rich text", systemImage: mode == .markdown ? "checkmark" : "")
                }
                Button { mode = .raw } label: {
                    Label("Raw markdown", systemImage: mode == .raw ? "checkmark" : "")
                }
            }

            segment(active: mode.isX, label: {
                Text("𝕏").font(.system(size: 14, weight: .bold))
            }, action: { mode = .xPost }, help: "X (⌘2)") {
                Button { mode = .xPost } label: {
                    Label("Post", systemImage: mode == .xPost ? "checkmark" : "")
                }
                Button { mode = .xArticle } label: {
                    Label("Article", systemImage: mode == .xArticle ? "checkmark" : "")
                }
            }

            segment(active: mode == .linkedin, label: {
                Text("in").font(.system(size: 14, weight: .heavy, design: .rounded))
            }, action: { mode = .linkedin }, help: "LinkedIn (⌘3)", menu: { EmptyView() })

            segment(active: mode == .slack, label: {
                Image(systemName: "number").font(.system(size: 13, weight: .bold))
            }, action: { mode = .slack }, help: "Slack (⌘4)", menu: { EmptyView() })
        }
        .padding(3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    @ViewBuilder
    private func segment<L: View, M: View>(active: Bool, @ViewBuilder label: () -> L, action: @escaping () -> Void, help: String, @ViewBuilder menu: () -> M) -> some View {
        let hasMenu = !(M.self == EmptyView.self)
        HStack(spacing: 0) {
            Button(action: action) {
                label()
                    .frame(width: 30, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)

            if hasMenu {
                Menu { menu() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .foregroundStyle(active ? Color.primary : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(active ? Color.primary.opacity(0.1) : Color.clear)
        )
    }
}
