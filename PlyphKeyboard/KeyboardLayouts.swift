import CoreGraphics

enum KeyboardKeyAction: Equatable {
    case insert(String)
    case shift
    case delete
    case letters
    case numbers
    case symbols
    case space
    case returnKey
    case switchLanguage
    case nextKeyboard
    case none
}

struct KeyboardKey: Identifiable, Equatable {
    enum Style: Equatable {
        case input
        case function
        case activeFunction
        case space
        case spacer
    }

    let id: String
    let label: String
    let systemImage: String?
    let action: KeyboardKeyAction
    let width: CGFloat
    let style: Style

    init(
        _ id: String,
        label: String,
        systemImage: String? = nil,
        action: KeyboardKeyAction,
        width: CGFloat = 1,
        style: Style = .input
    ) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.action = action
        self.width = width
        self.style = style
    }
}

enum KeyboardLayouts {
    static func rows(
        page: KeyboardState.Page,
        language: KeyboardLanguage,
        uppercase: Bool,
        capsLocked: Bool,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        switch page {
        case .letters:
            return letterRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .numbers:
            return numberRows(
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .symbols:
            return symbolRows(
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        }
    }

    private static func letterRows(
        language: KeyboardLanguage,
        uppercase: Bool,
        capsLocked: Bool,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        switch language {
        case .english:
            return englishRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .german:
            return germanRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .arabic:
            return arabicRows(
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .french:
            return frenchRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .spanish:
            return spanishRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .italian:
            return englishRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .portuguese:
            return portugueseRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .dutch:
            return englishRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .turkish:
            return turkishRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        case .russian:
            return russianRows(
                language: language,
                uppercase: uppercase,
                capsLocked: capsLocked,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        }
    }

    private static func englishRows(
        language: KeyboardLanguage,
        uppercase: Bool,
        capsLocked: Bool,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(transformed(Array("qwertyuiop").map(String.init), language: language, uppercase: uppercase)),
            [spacer("left-a", 0.5)] +
                inputRow(transformed(Array("asdfghjkl").map(String.init), language: language, uppercase: uppercase)) +
                [spacer("right-l", 0.5)],
            [shiftKey(uppercase: uppercase, capsLocked: capsLocked)] +
                inputRow(transformed(Array("zxcvbnm").map(String.init), language: language, uppercase: uppercase)) +
                [deleteKey],
            bottomRow(
                page: .letters,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func germanRows(
        language: KeyboardLanguage,
        uppercase: Bool,
        capsLocked: Bool,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(transformed(Array("qwertzuiopü").map(String.init), language: language, uppercase: uppercase)),
            inputRow(transformed(Array("asdfghjklöä").map(String.init), language: language, uppercase: uppercase)),
            [shiftKey(uppercase: uppercase, capsLocked: capsLocked)] +
                inputRow(transformed(Array("yxcvbnmß").map(String.init), language: language, uppercase: uppercase)) +
                [deleteKey],
            bottomRow(
                page: .letters,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func arabicRows(
        language: KeyboardLanguage,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح", "ج", "د"]),
            inputRow(["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك", "ط"]),
            inputRow(["ئ", "ء", "ؤ", "ر", "لا", "ى", "ة", "و", "ز", "ظ"]) + [deleteKey],
            bottomRow(
                page: .letters,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func frenchRows(
        language: KeyboardLanguage,
        uppercase: Bool,
        capsLocked: Bool,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(transformed(Array("azertyuiop").map(String.init), language: language, uppercase: uppercase)),
            inputRow(transformed(Array("qsdfghjklm").map(String.init), language: language, uppercase: uppercase)),
            [shiftKey(uppercase: uppercase, capsLocked: capsLocked)] +
                inputRow(transformed(["w", "x", "c", "v", "b", "n", "ç", "é"], language: language, uppercase: uppercase)) +
                [deleteKey],
            bottomRow(
                page: .letters,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func spanishRows(
        language: KeyboardLanguage,
        uppercase: Bool,
        capsLocked: Bool,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(transformed(Array("qwertyuiop").map(String.init), language: language, uppercase: uppercase)),
            inputRow(transformed(["a", "s", "d", "f", "g", "h", "j", "k", "l", "ñ"], language: language, uppercase: uppercase)),
            [shiftKey(uppercase: uppercase, capsLocked: capsLocked)] +
                inputRow(transformed(Array("zxcvbnm").map(String.init), language: language, uppercase: uppercase)) +
                [deleteKey],
            bottomRow(
                page: .letters,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func portugueseRows(
        language: KeyboardLanguage,
        uppercase: Bool,
        capsLocked: Bool,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(transformed(Array("qwertyuiop").map(String.init), language: language, uppercase: uppercase)),
            inputRow(transformed(["a", "s", "d", "f", "g", "h", "j", "k", "l", "ç"], language: language, uppercase: uppercase)),
            [shiftKey(uppercase: uppercase, capsLocked: capsLocked)] +
                inputRow(transformed(Array("zxcvbnm").map(String.init), language: language, uppercase: uppercase)) +
                [deleteKey],
            bottomRow(
                page: .letters,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func turkishRows(
        language: KeyboardLanguage,
        uppercase: Bool,
        capsLocked: Bool,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(transformed(["q", "w", "e", "r", "t", "y", "u", "ı", "o", "p", "ğ", "ü"], language: language, uppercase: uppercase)),
            inputRow(transformed(["a", "s", "d", "f", "g", "h", "j", "k", "l", "ş", "i"], language: language, uppercase: uppercase)),
            [shiftKey(uppercase: uppercase, capsLocked: capsLocked)] +
                inputRow(transformed(["z", "x", "c", "v", "b", "n", "m", "ö", "ç"], language: language, uppercase: uppercase)) +
                [deleteKey],
            bottomRow(
                page: .letters,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func russianRows(
        language: KeyboardLanguage,
        uppercase: Bool,
        capsLocked: Bool,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(transformed(Array("йцукенгшщзхъ").map(String.init), language: language, uppercase: uppercase)),
            inputRow(transformed(Array("фывапролджэ").map(String.init), language: language, uppercase: uppercase)),
            [shiftKey(uppercase: uppercase, capsLocked: capsLocked)] +
                inputRow(transformed(Array("ячсмитьбю").map(String.init), language: language, uppercase: uppercase)) +
                [deleteKey],
            bottomRow(
                page: .letters,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func numberRows(
        language: KeyboardLanguage,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]),
            inputRow(["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""]),
            [
                KeyboardKey(
                    "symbols",
                    label: "#+=",
                    action: .symbols,
                    width: 1.5,
                    style: .function
                ),
                spacer("number-left", 0.5)
            ] + inputRow(
                language == .arabic ? ["،", ".", "؟", "!", "'"] : [".", ",", "?", "!", "'"],
                width: 1.2
            ) + [
                spacer("number-right", 0.5),
                deleteKey
            ],
            bottomRow(
                page: .numbers,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func symbolRows(
        language: KeyboardLanguage,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [[KeyboardKey]] {
        [
            inputRow(["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]),
            inputRow(["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"]),
            [
                KeyboardKey(
                    "numbers",
                    label: "123",
                    action: .numbers,
                    width: 1.5,
                    style: .function
                ),
                spacer("symbol-left", 0.5)
            ] + inputRow(
                language == .arabic ? ["،", ".", "؟", "!", "'"] : [".", ",", "?", "!", "'"],
                width: 1.2
            ) + [
                spacer("symbol-right", 0.5),
                deleteKey
            ],
            bottomRow(
                page: .symbols,
                language: language,
                needsGlobe: needsGlobe,
                showLanguageKey: showLanguageKey
            )
        ]
    }

    private static func bottomRow(
        page: KeyboardState.Page,
        language: KeyboardLanguage,
        needsGlobe: Bool,
        showLanguageKey: Bool
    ) -> [KeyboardKey] {
        var row: [KeyboardKey] = [
            KeyboardKey(
                "page-toggle",
                label: page == .letters ? "123" : language.lettersLabel,
                action: page == .letters ? .numbers : .letters,
                width: 1.5,
                style: .function
            )
        ]

        if showLanguageKey {
            row.append(
                KeyboardKey(
                    "language",
                    label: language.shortCode,
                    action: .switchLanguage,
                    width: 1.2,
                    style: .function
                )
            )
        }

        if needsGlobe {
            row.append(
                KeyboardKey(
                    "globe",
                    label: "Next keyboard",
                    systemImage: "globe",
                    action: .nextKeyboard,
                    width: 1,
                    style: .function
                )
            )
        }

        let spaceWidth: CGFloat
        switch (showLanguageKey, needsGlobe) {
        case (true, true): spaceWidth = 4.3
        case (true, false): spaceWidth = 5.3
        case (false, true): spaceWidth = 5.5
        case (false, false): spaceWidth = 6.5
        }

        row.append(
            KeyboardKey(
                "space",
                label: language.spaceLabel,
                action: .space,
                width: spaceWidth,
                style: .space
            )
        )

        row.append(
            KeyboardKey(
                "return",
                label: language.returnLabel,
                action: .returnKey,
                width: 2,
                style: .function
            )
        )

        return row
    }

    private static func shiftKey(
        uppercase: Bool,
        capsLocked: Bool
    ) -> KeyboardKey {
        KeyboardKey(
            "shift",
            label: "Shift",
            systemImage: capsLocked ? "capslock.fill" : (uppercase ? "shift.fill" : "shift"),
            action: .shift,
            width: 1.5,
            style: uppercase ? .activeFunction : .function
        )
    }

    private static var deleteKey: KeyboardKey {
        KeyboardKey(
            "delete",
            label: "Delete",
            systemImage: "delete.left",
            action: .delete,
            width: 1.5,
            style: .function
        )
    }

    private static func transformed(
        _ values: [String],
        language: KeyboardLanguage,
        uppercase: Bool
    ) -> [String] {
        guard uppercase else { return values }

        return values.map { value in
            if language == .german, value == "ß" {
                return "ẞ"
            }

            if language == .turkish {
                if value == "i" { return "İ" }
                if value == "ı" { return "I" }
            }

            return value.uppercased()
        }
    }

    private static func inputRow(
        _ values: [String],
        width: CGFloat = 1
    ) -> [KeyboardKey] {
        values.enumerated().map { index, value in
            KeyboardKey(
                "\(index)-\(value)",
                label: value,
                action: .insert(value),
                width: width
            )
        }
    }

    private static func spacer(_ id: String, _ width: CGFloat) -> KeyboardKey {
        KeyboardKey(
            id,
            label: "",
            action: .none,
            width: width,
            style: .spacer
        )
    }
}
