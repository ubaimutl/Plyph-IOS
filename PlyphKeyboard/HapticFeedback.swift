import UIKit

// Adapted from DictusCore/HapticFeedback.swift (MIT). Plyph keeps
// haptics enabled by default and has no Dictus app-group settings dependency.
enum HapticFeedback {
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func warmUp() {
        selectionGenerator.prepare()
    }

    static func prepareForNextTap() {
        selectionGenerator.prepare()
    }

    static func keyTapped() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }
}
