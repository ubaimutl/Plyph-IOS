import SwiftUI
import UIKit

struct KeyboardRootView: View {
    @ObservedObject var state: KeyboardState
    let onRun: (ActionRequest) -> Void
    let onReplace: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void
    let onToggleWholeText: () -> Void
    let onStartAsk: () -> Void
    let onGenerateAsk: () -> Void
    let onCancelAsk: () -> Void
    let onStartFollowUp: () -> Void
    let onSendFollowUp: () -> Void
    let onCollapseFollowUp: () -> Void
    let onSelectResponse: (UUID) -> Void
    let onToggleMarkdown: () -> Void
    let onCursorMove: (Int) -> Void
    let onKey: (KeyboardKeyAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusRow

            if state.isConversationActive {
                conversationView

                if state.aiComposerMode {
                    KeyboardTypingView(
                        state: state,
                        onCursorMove: onCursorMove,
                        onKey: onKey
                    )
                }
            } else if state.phase == .review {
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
            Image(
                systemName: state.isConversationActive ?
                    "bubble.left.and.bubble.right" :
                    (state.aiComposerMode ?
                        "bubble.left.and.bubble.right" : "wand.and.stars")
            )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)

            Text(
                state.isConversationActive ?
                    state.conversationTitle : statusText
            )
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

    private var conversationView: some View {
        VStack(alignment: .leading, spacing: 6) {
            conversationHistory
                .frame(
                    maxHeight: state.aiComposerMode ? 126 : .infinity
                )

            followUpComposer

            if !state.conversationError.isEmpty {
                Text(state.conversationError)
                    .font(.caption2)
                    .foregroundStyle(Color.red)
                    .lineLimit(2)
                    .padding(.horizontal, 4)
            }

            conversationControls
        }
        .padding(.horizontal, 2)
    }

    private var conversationHistory: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(state.conversationMessages) { message in
                        conversationMessage(message)
                            .id(message.id)
                    }

                    if state.phase == .running {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)

                            Text("Thinking…")
                                .font(.caption)
                                .foregroundStyle(Color.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                    }
                }
                .padding(6)
            }
            .background(
                Color(uiColor: .systemBackground),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .onChange(of: state.conversationMessages.count) {
                guard let last = state.conversationMessages.last else {
                    return
                }

                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func conversationMessage(
        _ message: KeyboardState.ConversationMessage
    ) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 42)

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(
                        Color(uiColor: .tertiarySystemFill),
                        in: RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                    )
            }
        } else {
            let isActive = state.activeResponseID == message.id

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text("Result")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.secondary)

                    Spacer()

                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.primary)
                    }
                }

                responseText(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(9)
            .background(
                isActive ?
                    Color(uiColor: .tertiarySystemFill) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .onTapGesture {
                onSelectResponse(message.id)
            }
            .accessibilityAddTraits(
                isActive ? .isSelected : AccessibilityTraits(rawValue: 0)
            )
        }
    }

    @ViewBuilder
    private func responseText(_ value: String) -> some View {
        if state.markdownPreviewEnabled,
           let attributed = try? AttributedString(markdown: value) {
            Text(attributed)
        } else {
            Text(value)
        }
    }

    private var followUpComposer: some View {
        HStack(spacing: 6) {
            if state.aiComposerMode {
                Button(action: onCollapseFollowUp) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(ConversationToolbarButtonStyle())
            }

            Button(action: onStartFollowUp) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(
                        state.aiInstruction.isEmpty ?
                            "Ask for changes…" : state.aiInstruction
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(
                        state.aiInstruction.isEmpty ?
                            Color.secondary : Color.primary
                    )
                    .lineLimit(1)
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(
                    Color(uiColor: .systemBackground),
                    in: RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(uiColor: .separator))
                }
            }
            .buttonStyle(.plain)
            .disabled(state.phase == .running)

            Button(action: onSendFollowUp) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(width: 32, height: 32)
                    .background(
                        Color(uiColor: .label),
                        in: Circle()
                    )
            }
            .buttonStyle(.plain)
            .disabled(
                state.aiInstruction
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty || state.phase == .running
            )
            .opacity(
                state.aiInstruction
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? 0.38 : 1
            )
        }
    }

    private var conversationControls: some View {
        HStack(spacing: 5) {
            Button(action: onToggleMarkdown) {
                Label("Markdown", systemImage: "textformat")
            }
            .buttonStyle(
                ConversationToolbarButtonStyle(
                    isSelected: state.markdownPreviewEnabled
                )
            )

            Spacer(minLength: 2)

            Button("Cancel", action: onCancel)
                .buttonStyle(ConversationToolbarButtonStyle())

            Button("Copy", action: onCopy)
                .buttonStyle(ConversationToolbarButtonStyle())
                .disabled(state.phase == .running)

            Button(
                state.aiInsertResultMode ? "Insert" : "Replace",
                action: onReplace
            )
            .buttonStyle(ConversationPrimaryButtonStyle())
            .disabled(state.phase == .running)
        }
        .frame(minHeight: 34)
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

private struct ConversationToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 8)
            .frame(minHeight: 32)
            .background(
                isSelected || configuration.isPressed ?
                    Color(uiColor: .tertiarySystemFill) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.38)
    }
}

private struct ConversationPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(uiColor: .systemBackground))
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(
                Color(uiColor: .label),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .opacity(
                isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.38
            )
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
