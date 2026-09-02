import SwiftUI
import UIKit

struct KeyboardRootView: View {
    @ObservedObject var state: KeyboardState
    let onRun: (ActionRequest) -> Void
    let onReplace: () -> Void
    let onCancel: () -> Void
    let onToggleWholeText: () -> Void
    let onStartAsk: () -> Void
    let onGenerateAsk: () -> Void
    let onCancelAsk: () -> Void
    let onCursorMove: (Int) -> Void
    let onKey: (KeyboardKeyAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow

            if state.phase == .review {
                reviewView
            } else {
                if state.aiComposerMode {
                    askComposerBar
                } else {
                    actionBar
                }

                KeyboardTypingView(
                    state: state,
                    onCursorMove: onCursorMove,
                    onKey: onKey
                )
            }
        }
        .padding(.horizontal, 5)
        .padding(.top, 6)
        .padding(.bottom, 5)
        .background(Color.clear)
        .tint(Color(uiColor: .label))
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            Image(systemName: state.aiComposerMode ? "bubble.left.and.bubble.right" : "wand.and.stars")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)

            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    state.phase == .error ? Color.red : Color.primary
                )
                .lineLimit(state.phase == .error ? 2 : 1)

            Spacer(minLength: 4)

            if state.phase == .running {
                ProgressView()
                    .controlSize(.small)

                Button("Cancel", action: onCancel)
                    .font(.caption.weight(.semibold))
            } else if state.phase == .error {
                Button("Dismiss", action: onCancel)
                    .font(.caption.weight(.semibold))
            }
        }
        .frame(minHeight: 20)
        .padding(.horizontal, 6)
    }

    private var statusText: String {
        if state.phase == .error {
            return state.errorMessage
        }

        if state.aiComposerMode {
            let compact = state.aiContext
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return compact.isEmpty ? "Ask about copied text" : "Ask about: \(compact)"
        }

        if state.wholeTextMode && state.phase == .idle {
            return "Whole text mode — choose an action"
        }

        return state.status
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionToolbarButton(
                title: "All",
                systemImage: "doc.text",
                isSelected: state.wholeTextMode
            ) {
                onToggleWholeText()
            }
            .disabled(
                state.secureField ||
                state.phase == .running
            )
            .padding(.trailing, 6)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(width: 1, height: 24)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    actionToolbarButton(
                        title: "Ask",
                        systemImage: "bubble.left.and.bubble.right"
                    ) {
                        onStartAsk()
                    }
                    .disabled(
                        state.secureField ||
                        !state.fullAccessEnabled ||
                        state.phase == .running
                    )

                    ForEach(state.actions) { action in
                        actionToolbarButton(
                            title: action.label,
                            systemImage: action.systemImage ?? "sparkles"
                        ) {
                            onRun(action)
                        }
                        .disabled(
                            state.secureField ||
                            !state.fullAccessEnabled ||
                            state.phase == .running
                        )
                    }
                }
                .padding(.leading, 6)
                .padding(.trailing, 2)
            }
            .clipped()
        }
        .frame(height: KeyboardMetrics.actionBarHeight)
    }

    private func actionToolbarButton(
        title: String,
        systemImage: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))

                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .buttonStyle(
            ActionToolbarButtonStyle(isSelected: isSelected)
        )
    }

    private var askComposerBar: some View {
        HStack(spacing: 7) {
            Button {
                onCancelAsk()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 30, height: 34)
            }
            .buttonStyle(AnyKeyboardButtonStyle.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(
                    state.aiInstruction.isEmpty ?
                        "Type what you want to ask…" :
                        state.aiInstruction
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    state.aiInstruction.isEmpty ? Color.secondary : Color.primary
                )
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 34)
            }
            .background(
                Color(uiColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(uiColor: .separator))
            }

            Button("Go") {
                onGenerateAsk()
            }
            .buttonStyle(AnyKeyboardButtonStyle.primary)
            .disabled(
                state.aiInstruction
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ||
                state.phase == .running
            )
        }
        .frame(height: KeyboardMetrics.actionBarHeight)
        .padding(.horizontal, 1)
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(state.result)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
            }
            .frame(maxHeight: 190)
            .padding(10)
            .background(
                Color(uiColor: .systemBackground),
                in: RoundedRectangle(cornerRadius: 10)
            )

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)
                    .buttonStyle(KeyboardButtonStyle())

                Button(state.aiInsertResultMode ? "Insert" : "Replace", action: onReplace)
                    .buttonStyle(KeyboardPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 7)
    }
}

private struct ActionToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 9)
            .frame(minHeight: 34)
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(Color.primary)
                        .frame(height: 2)
                        .padding(.horizontal, 7)
                }
            }
            .contentShape(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .opacity(
                isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.38
            )
    }
}

private struct AnyKeyboardButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    static let primary = AnyKeyboardButtonStyle(kind: .primary)
    static let secondary = AnyKeyboardButtonStyle(kind: .secondary)

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(
                kind == .primary ?
                    Color(uiColor: .systemBackground) :
                    Color.primary
            )
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(
                kind == .primary ?
                    Color(uiColor: .label) :
                    Color(uiColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(uiColor: .separator))
                }
            }
            .opacity(configuration.isPressed ? 0.68 : 1)
    }
}

private struct KeyboardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(
                Color(uiColor: .tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color(uiColor: .separator))
            )
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private struct KeyboardPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(
                Color(uiColor: .label),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
