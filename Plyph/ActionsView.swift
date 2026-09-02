import SwiftUI

struct ActionsView: View {
    @EnvironmentObject private var state: AppState
    @State private var editedAction: CustomAction?
    @State private var isAdding = false

    var body: some View {
        List {
            Section {
                if state.actions.isEmpty {
                    ContentUnavailableView(
                        "No custom actions",
                        systemImage: "wand.and.stars",
                        description: Text("Correct, Rewrite, and Run prompt are always available.")
                    )
                } else {
                    ForEach(state.actions) { action in
                        Button {
                            editedAction = action
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(actionSummary(action))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !action.prompt.isEmpty {
                                        Text(action.prompt)
                                            .lineLimit(2)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Toggle("Enabled", isOn: Binding(
                                    get: { action.enabled },
                                    set: { state.setAction(action, enabled: $0) }
                                ))
                                .labelsHidden()
                                .tint(Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: state.deleteActions)
                    .onMove(perform: state.moveActions)
                }
            } footer: {
                Text("Custom actions appear in both the app and the Plyph keyboard.")
            }
        }
        .navigationTitle("Custom actions")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add action", systemImage: "plus") { isAdding = true }
            }
        }
        .sheet(isPresented: $isAdding) {
            ActionEditor(action: CustomAction()) { state.saveAction($0) }
        }
        .sheet(item: $editedAction) { action in
            ActionEditor(action: action) { state.saveAction($0) }
        }
    }
}

private struct ActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var action: CustomAction
    let onSave: (CustomAction) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $action.name)
                    Picker("Input mode", selection: $action.inputMode) {
                        Text("Transform selected text").tag(InputMode.transform)
                        Text("Use text as prompt").tag(InputMode.prompt)
                    }
                    Toggle(
                        "Read text from clipboard",
                        isOn: Binding(
                            get: { action.usesClipboard },
                            set: { action.readsClipboard = $0 }
                        )
                    )
                    .toggleStyle(MonochromeToggleStyle())
                    Toggle("Show in action list", isOn: $action.enabled)
                        .toggleStyle(MonochromeToggleStyle())
                } header: {
                    Text("Action")
                } footer: {
                    if action.usesClipboard {
                        Text("This action uses copied text instead of a selection. In the keyboard, its result is inserted at the cursor, so it also works with text you cannot edit.")
                    }
                }

                Section(action.inputMode == .prompt ? "System guidance (optional)" : "Prompt") {
                    TextEditor(text: $action.prompt)
                        .frame(minHeight: 120)
                }

                Section {
                    Picker("Provider", selection: $action.providerID) {
                        Text("Use active provider").tag("")
                        ForEach(Provider.allCases) { provider in
                            Text(provider.displayName).tag(provider.id)
                        }
                    }

                    TextField("Model (optional)", text: $action.model)

                    AutomaticTokenLimitField(
                        title: "Input token limit",
                        value: $action.inputLimit
                    )

                    AutomaticTokenLimitField(
                        title: "Output token limit",
                        value: $action.outputLimit
                    )
                } header: {
                    Text("Overrides")
                } footer: {
                    Text("Automatic uses Plyph's default token handling. Enter a number only when you want a custom cap; clear the field to return to Automatic.")
                }
            }
            .navigationTitle(action.name.isEmpty ? "New action" : "Edit action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(action)
                        dismiss()
                    }
                    .disabled(
                        action.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (action.inputMode == .transform &&
                         action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    )
                }
            }
        }
    }
}

private func actionSummary(_ action: CustomAction) -> String {
    let mode = action.inputMode == .prompt ? "Prompt" : "Transform"
    return action.usesClipboard ? "\(mode) · Clipboard" : mode
}
