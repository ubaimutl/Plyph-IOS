import SwiftUI
import UIKit

struct EditorView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Paste text, then choose an action.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .trailing, spacing: 8) {
                    TextEditor(text: $state.input)
                        .frame(minHeight: 180)
                        .padding(8)
                        .background(
                            Color(uiColor: .systemBackground),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(uiColor: .separator))
                        }
                        .accessibilityLabel("Text to transform")

                    HStack(spacing: 8) {
                        Text("\(state.input.count) characters")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            state.input = UIPasteboard.general.string ?? ""
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(EditorUtilityButtonStyle())

                        Button {
                            state.cancelRequest()
                            state.input = ""
                            state.output = ""
                        } label: {
                            Label("Clear", systemImage: "xmark")
                        }
                        .buttonStyle(EditorUtilityButtonStyle())
                        .disabled(state.input.isEmpty && state.output.isEmpty)
                    }
                }

                Text("Choose an action")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(BuiltInAction.allCases) { action in
                            Button(action.rawValue) {
                                state.run(action)
                            }
                            .buttonStyle(EditorActionButtonStyle())
                        }

                        ForEach(state.actions.filter(\.enabled)) { action in
                            Button(action.name) {
                                state.run(action)
                            }
                            .buttonStyle(EditorActionButtonStyle())
                        }
                    }
                }

                if state.isRunning {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Generating with \(state.settings.provider.displayName)…")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            state.cancelRequest()
                        }
                    }
                    .padding(14)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }

                if !state.output.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Review and edit")
                                .font(.headline)

                            Spacer()

                            Button("Copy", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = state.output
                            }
                        }

                        TextEditor(text: $state.output)
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(
                                Color(uiColor: .systemBackground),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(uiColor: .separator))
                            }

                        Button("Use as input", systemImage: "arrow.up.doc") {
                            state.input = state.output
                            state.output = ""
                        }
                        .buttonStyle(EditorActionButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Plyph")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EditorUtilityButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(Color(uiColor: .separator))
            }
            .opacity(!isEnabled ? 0.35 : (configuration.isPressed ? 0.62 : 1))
    }
}

private struct EditorActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(
                Color(uiColor: .secondarySystemFill),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(uiColor: .separator))
            }
            .opacity(!isEnabled ? 0.35 : (configuration.isPressed ? 0.62 : 1))
    }
}
