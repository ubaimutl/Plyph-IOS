import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            NavigationStack {
                EditorView()
            }
            .tabItem {
                Label("Editor", systemImage: "square.and.pencil")
            }

            NavigationStack {
                ActionsView()
            }
            .tabItem {
                Label("Actions", systemImage: "wand.and.stars")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        // Plyph branding is monochrome. UIColor.label automatically
        // becomes black in light mode and white in dark mode.
        .tint(Color(uiColor: .label))
        .background {
            KeyboardDismissInstaller()
        }
        .alert(
            "Plyph",
            isPresented: Binding(
                get: {
                    !state.errorMessage.isEmpty
                },
                set: {
                    if !$0 {
                        state.errorMessage = ""
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                state.errorMessage = ""
            }
        } message: {
            Text(state.errorMessage)
        }
    }
}

private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false

        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: view)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(
        _ uiView: UIView,
        coordinator: Coordinator
    ) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        func installIfNeeded(from view: UIView) {
            guard recognizer == nil,
                  let window = view.window else {
                return
            }

            let recognizer = UITapGestureRecognizer(
                target: self,
                action: #selector(handleTap)
            )

            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delegate = self

            window.addGestureRecognizer(recognizer)

            self.window = window
            self.recognizer = recognizer
        }

        @objc
        private func handleTap() {
            window?.endEditing(true)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var currentView: UIView? = touch.view

            while let view = currentView {
                if view is UITextField || view is UITextView {
                    return false
                }

                currentView = view.superview
            }

            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func uninstall() {
            if let recognizer,
               let window {
                window.removeGestureRecognizer(recognizer)
            }

            recognizer = nil
            window = nil
        }
    }
}
