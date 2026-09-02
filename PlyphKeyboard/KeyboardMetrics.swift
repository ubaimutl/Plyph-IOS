import SwiftUI
import UIKit

// Adapted from Dictus iOS KeyboardMetrics.swift (MIT).
enum KeyboardMetrics {
    enum DeviceClass {
        case compact
        case standard
        case large
    }

    static let deviceClass: DeviceClass = {
        let height = UIScreen.main.bounds.height

        if height <= 667 {
            return .compact
        } else if height <= 852 {
            return .standard
        } else {
            return .large
        }
    }()

    static let keyHeight: CGFloat = {
        switch deviceClass {
        case .compact: return 40
        case .standard: return 43
        case .large: return 46
        }
    }()

    static let rowSpacing: CGFloat = {
        switch deviceClass {
        case .compact: return 9
        case .standard: return 11
        case .large: return 12
        }
    }()

    static let keySpacing: CGFloat = {
        switch deviceClass {
        case .compact: return 5
        case .standard, .large: return 6
        }
    }()

    static let rowSidePadding: CGFloat = {
        switch deviceClass {
        case .compact: return 3
        case .standard: return 4
        case .large: return 5
        }
    }()

    static let normalHeight: CGFloat = {
        switch deviceClass {
        case .compact: return 274
        case .standard: return 294
        case .large: return 307
        }
    }()

    static let reviewHeight: CGFloat = max(300, normalHeight)
    static let errorHeight: CGFloat = normalHeight + 10
    static let conversationHeight: CGFloat = max(
        320,
        normalHeight + 40
    )
    static let conversationTypingHeight: CGFloat = normalHeight + 180

    static let actionBarHeight: CGFloat = 38
    static let keyCornerRadius: CGFloat = 5
    static let popupCornerRadius: CGFloat = 12
    static let popupHorizontalGrowth: CGFloat = 16

    static let keyboardBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 43.0 / 255.0, alpha: 1)
            : UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 1)
    }

    static let letterKeyColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 107.0 / 255.0, alpha: 1)
            : .white
    })

    static let functionKeyColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 70.0 / 255.0, alpha: 1)
            : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
    })

    static let activeFunctionKeyColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 212.0 / 255.0, alpha: 1)
            : .white
    })

    static let pressedKeyColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.48, alpha: 1)
            : UIColor(white: 0.88, alpha: 1)
    })

    static let popupColor = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 107.0 / 255.0, alpha: 1)
            : .white
    })
}
