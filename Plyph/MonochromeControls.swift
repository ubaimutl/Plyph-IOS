import SwiftUI
import UIKit

struct MonochromeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                configuration.label

                Spacer(minLength: 12)

                ZStack {
                    Capsule()
                        .fill(
                            configuration.isOn ?
                                Color.primary :
                                Color(uiColor: .tertiarySystemFill)
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color(uiColor: .separator),
                                    lineWidth: configuration.isOn ? 0 : 0.5
                                )
                        }

                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                        .frame(width: 27, height: 27)
                        .shadow(
                            color: Color.black.opacity(0.18),
                            radius: 1.5,
                            y: 1
                        )
                        .offset(x: configuration.isOn ? 10 : -10)
                }
                .frame(width: 51, height: 31)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

struct AutomaticTokenLimitField: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            TextField("Automatic", text: textBinding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 90, maxWidth: 140)
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: {
                value > 0 ? String(value) : ""
            },
            set: { newValue in
                let digits = newValue.filter(\.isNumber)

                guard !digits.isEmpty else {
                    value = 0
                    return
                }

                if let parsed = Int(digits) {
                    value = parsed
                }
            }
        )
    }
}
