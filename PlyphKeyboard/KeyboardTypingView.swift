import SwiftUI

struct KeyboardTypingView: View {
    @ObservedObject var state: KeyboardState
    let onCursorMove: (Int) -> Void
    let onKey: (KeyboardKeyAction) -> Void

    var body: some View {
        let rows = KeyboardLayouts.rows(
            page: state.page,
            language: state.language,
            uppercase: state.usesUppercaseLetters,
            capsLocked: state.shiftState == .capsLocked,
            needsGlobe: state.needsInputModeSwitchKey,
            showLanguageKey: state.enabledLanguages.count > 1
        )

        VStack(spacing: KeyboardMetrics.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                KeyboardRowView(
                    keys: row,
                    keyHeight: KeyboardMetrics.keyHeight,
                    spacing: KeyboardMetrics.keySpacing,
                    cursorTrackingEnabled: !state.aiComposerMode,
                    onCursorMove: onCursorMove,
                    onKey: onKey
                )
                .zIndex(Double(rowIndex))
            }
        }
        .padding(
            .horizontal,
            KeyboardMetrics.rowSidePadding - 5
        )
        .zIndex(1)
        .onAppear {
            HapticFeedback.warmUp()
        }
    }
}

private struct KeyboardRowView: View {
    let keys: [KeyboardKey]
    let keyHeight: CGFloat
    let spacing: CGFloat
    let cursorTrackingEnabled: Bool
    let onCursorMove: (Int) -> Void
    let onKey: (KeyboardKeyAction) -> Void

    var body: some View {
        GeometryReader { geometry in
            let visibleGaps = max(keys.count - 1, 0)
            let availableWidth = geometry.size.width -
                CGFloat(visibleGaps) * spacing
            let totalUnits = keys.reduce(CGFloat.zero) { $0 + $1.width }
            let unitWidth = availableWidth / max(totalUnits, 1)

            HStack(spacing: spacing) {
                ForEach(Array(keys.enumerated()), id: \.element.id) { index, key in
                    if key.style == .spacer {
                        Color.clear
                            .frame(width: unitWidth * key.width)
                    } else {
                        KeyboardTypingKey(
                            key: key,
                            popupAlignment: popupAlignment(for: index),
                            cursorTrackingEnabled: cursorTrackingEnabled,
                            onCursorMove: onCursorMove,
                            action: { onKey(key.action) }
                        )
                        .frame(width: unitWidth * key.width)
                    }
                }
            }
        }
        .frame(height: keyHeight)
    }

    private func popupAlignment(for index: Int) -> KeyboardPopupAlignment {
        let leadingUnits = keys[..<index].reduce(CGFloat.zero) {
            $0 + $1.width
        }
        let trailingUnits = keys[(index + 1)...].reduce(CGFloat.zero) {
            $0 + $1.width
        }

        if leadingUnits < 0.25 {
            return .leading
        }

        if trailingUnits < 0.25 {
            return .trailing
        }

        return .center
    }
}

private struct KeyboardTypingKey: View {
    let key: KeyboardKey
    let popupAlignment: KeyboardPopupAlignment
    let cursorTrackingEnabled: Bool
    let onCursorMove: (Int) -> Void
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var isSpaceCursorMode = false
    @State private var lastSpaceCursorStep = 0

    private let cursorStepWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(
                    cornerRadius: KeyboardMetrics.keyCornerRadius,
                    style: .continuous
                )
                .fill(backgroundColor)
                .shadow(
                    color: Color.black.opacity(
                        isPressed ? 0 :
                            (colorScheme == .dark ? 0.42 : 0.28)
                    ),
                    radius: isPressed ? 0 : 0.6,
                    y: isPressed ? 0 : 1
                )

                if let systemImage = key.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .regular))
                } else {
                    Text(key.label)
                        .font(labelFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .opacity(isSpaceCursorMode ? 0.35 : 1)
                }

                if showsCharacterPopup {
                    KeyboardKeyPopup(
                        label: key.label,
                        keyWidth: geometry.size.width,
                        keyHeight: geometry.size.height,
                        alignment: popupAlignment
                    )
                    .allowsHitTesting(false)
                    .zIndex(2)
                }
            }
            .foregroundStyle(foregroundColor)
            .contentShape(Rectangle())
            .offset(y: isPressed ? 1 : 0)
            .gesture(keyGesture)
            .accessibilityLabel(key.label)
        }
        .zIndex(isPressed ? 100 : 0)
        .onDisappear {
            stopDeleteRepeat()
            resetSpaceCursor()
        }
    }

    private var keyGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isPressed {
                    HapticFeedback.prepareForNextTap()
                    HapticFeedback.keyTapped()
                    isPressed = true

                    if key.action == .delete {
                        action()
                        startDeleteRepeat()
                    }
                }

                if key.action == .space,
                   cursorTrackingEnabled {
                    updateSpaceCursor(
                        horizontalTranslation: value.translation.width
                    )
                }
            }
            .onEnded { _ in
                let usedSpaceCursor =
                    key.action == .space && isSpaceCursorMode
                let shouldPerform =
                    key.action != .delete && !usedSpaceCursor

                stopDeleteRepeat()
                isPressed = false
                resetSpaceCursor()

                if shouldPerform {
                    action()
                }
            }
    }

    private func updateSpaceCursor(
        horizontalTranslation: CGFloat
    ) {
        if !isSpaceCursorMode {
            guard abs(horizontalTranslation) >= cursorStepWidth else {
                return
            }

            isSpaceCursorMode = true
            lastSpaceCursorStep = 0
        }

        let currentStep = Int(
            horizontalTranslation / cursorStepWidth
        )
        let movement = currentStep - lastSpaceCursorStep

        guard movement != 0 else {
            return
        }

        lastSpaceCursorStep = currentStep
        onCursorMove(movement)
        HapticFeedback.keyTapped()
    }

    private func resetSpaceCursor() {
        isSpaceCursorMode = false
        lastSpaceCursorStep = 0
    }

    private var showsCharacterPopup: Bool {
        guard isPressed else { return false }

        if case .insert = key.action {
            return true
        }

        return false
    }

    private var backgroundColor: Color {
        if isPressed {
            return KeyboardMetrics.pressedKeyColor
        }

        switch key.style {
        case .input, .space:
            return KeyboardMetrics.letterKeyColor
        case .function:
            return KeyboardMetrics.functionKeyColor
        case .activeFunction:
            return KeyboardMetrics.activeFunctionKeyColor
        case .spacer:
            return .clear
        }
    }

    private var foregroundColor: Color {
        key.style == .activeFunction ? .black : .primary
    }

    private var labelFont: Font {
        switch key.style {
        case .input:
            let hasLetterCase = key.label.lowercased() !=
                key.label.uppercased()
            let isLowercase = key.label == key.label.lowercased()

            return .system(
                size: hasLetterCase && isLowercase ? 25 : 22,
                weight: .regular
            )
        case .space:
            return .system(size: 15, weight: .regular)
        case .function, .activeFunction, .spacer:
            return .system(size: 15, weight: .medium)
        }
    }

    private func startDeleteRepeat() {
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))

            while !Task.isCancelled {
                HapticFeedback.keyTapped()
                action()
                try? await Task.sleep(for: .milliseconds(75))
            }
        }
    }

    private func stopDeleteRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}

private enum KeyboardPopupAlignment {
    case leading
    case center
    case trailing
}

private struct KeyboardKeyPopup: View {
    let label: String
    let keyWidth: CGFloat
    let keyHeight: CGFloat
    let alignment: KeyboardPopupAlignment

    private var popupWidth: CGFloat {
        keyWidth + KeyboardMetrics.popupHorizontalGrowth
    }

    private var popupHeight: CGFloat {
        keyHeight * 2
    }

    private var horizontalOffset: CGFloat {
        switch alignment {
        case .leading:
            return KeyboardMetrics.popupHorizontalGrowth / 2
        case .center:
            return 0
        case .trailing:
            return -KeyboardMetrics.popupHorizontalGrowth / 2
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            KeyboardPopupShape(
                keyWidth: keyWidth,
                keyHeight: keyHeight,
                alignment: alignment
            )
            .fill(KeyboardMetrics.popupColor)
            .shadow(
                color: Color.black.opacity(0.35),
                radius: 3,
                y: 2
            )

            Text(label)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(Color.primary)
                .frame(height: keyHeight + 8)
        }
        .frame(width: popupWidth, height: popupHeight)
        .offset(
            x: horizontalOffset,
            y: -(popupHeight - keyHeight) / 2
        )
    }
}

private struct KeyboardPopupShape: Shape {
    let keyWidth: CGFloat
    let keyHeight: CGFloat
    let alignment: KeyboardPopupAlignment

    func path(in rect: CGRect) -> Path {
        let bubbleRadius = KeyboardMetrics.popupCornerRadius
        let keyRadius = KeyboardMetrics.keyCornerRadius
        let neckRadius: CGFloat = 5
        let bubbleBottom = rect.height - keyHeight + 8
        let growth = KeyboardMetrics.popupHorizontalGrowth

        let stemLeft: CGFloat

        switch alignment {
        case .leading:
            stemLeft = 0
        case .center:
            stemLeft = growth / 2
        case .trailing:
            stemLeft = growth
        }

        let stemRight = stemLeft + keyWidth
        let leftConnection = max(0, stemLeft - neckRadius)
        let rightConnection = min(rect.width, stemRight + neckRadius)

        var path = Path()
        path.move(to: CGPoint(x: bubbleRadius, y: 0))
        path.addLine(to: CGPoint(x: rect.width - bubbleRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.width, y: bubbleRadius),
            control: CGPoint(x: rect.width, y: 0)
        )
        path.addLine(to: CGPoint(x: rect.width, y: bubbleBottom - bubbleRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - bubbleRadius, y: bubbleBottom),
            control: CGPoint(x: rect.width, y: bubbleBottom)
        )
        path.addLine(to: CGPoint(x: rightConnection, y: bubbleBottom))
        path.addQuadCurve(
            to: CGPoint(x: stemRight, y: bubbleBottom + neckRadius),
            control: CGPoint(x: stemRight, y: bubbleBottom)
        )
        path.addLine(to: CGPoint(x: stemRight, y: rect.height - keyRadius))
        path.addQuadCurve(
            to: CGPoint(x: stemRight - keyRadius, y: rect.height),
            control: CGPoint(x: stemRight, y: rect.height)
        )
        path.addLine(to: CGPoint(x: stemLeft + keyRadius, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: stemLeft, y: rect.height - keyRadius),
            control: CGPoint(x: stemLeft, y: rect.height)
        )
        path.addLine(to: CGPoint(x: stemLeft, y: bubbleBottom + neckRadius))
        path.addQuadCurve(
            to: CGPoint(x: leftConnection, y: bubbleBottom),
            control: CGPoint(x: stemLeft, y: bubbleBottom)
        )
        path.addLine(to: CGPoint(x: bubbleRadius, y: bubbleBottom))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: bubbleBottom - bubbleRadius),
            control: CGPoint(x: 0, y: bubbleBottom)
        )
        path.addLine(to: CGPoint(x: 0, y: bubbleRadius))
        path.addQuadCurve(
            to: CGPoint(x: bubbleRadius, y: 0),
            control: CGPoint.zero
        )
        path.closeSubpath()

        return path
    }
}
