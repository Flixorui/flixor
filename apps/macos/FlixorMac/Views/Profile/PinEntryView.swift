//
//  PinEntryView.swift
//  FlixorMac
//
//  PIN entry modal for protected Plex profiles
//

import SwiftUI
import FlixorKit

struct PinEntryView: View {
    @Environment(\.flixorTheme) private var theme
    let user: PlexHomeUser
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    private let pinLength = 4

    var body: some View {
        VStack(spacing: DS.Space.s24) {
            // Header
            VStack(spacing: DS.Space.s16) {
                ProfileAvatarView(user: user, size: 80)

                Text("Enter PIN for \(user.displayName)")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("This profile is protected with a PIN")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            // PIN Input Display
            HStack(spacing: DS.Space.s16) {
                ForEach(0..<pinLength, id: \.self) { index in
                    PinDigitView(
                        digit: digitAt(index),
                        isFilled: index < pin.count
                    )
                }
            }
            .padding(.vertical, DS.Space.s20)

            // Hidden text field for keyboard input
            TextField("", text: $pin)
                .focused($isFocused)
                .frame(width: 1, height: 1)
                .opacity(0)
                .onChange(of: pin) { newValue in
                    // Filter to digits only
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue {
                        pin = filtered
                    }
                    // Limit to 4 digits
                    if pin.count > pinLength {
                        pin = String(pin.prefix(pinLength))
                    }
                    // Auto-submit when 4 digits entered
                    if pin.count == pinLength {
                        submit()
                    }
                }

            // Number Pad
            VStack(spacing: DS.Space.s12) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: DS.Space.s12) {
                        ForEach(1...3, id: \.self) { col in
                            let digit = row * 3 + col
                            NumberPadButton(digit: String(digit)) {
                                appendDigit(String(digit))
                            }
                        }
                    }
                }
                HStack(spacing: DS.Space.s12) {
                    // Empty space for alignment
                    NumberPadButton(digit: "", action: {})
                        .opacity(0)

                    NumberPadButton(digit: "0") {
                        appendDigit("0")
                    }

                    NumberPadButton(digit: "delete.left", isSymbol: true) {
                        deleteLastDigit()
                    }
                }
            }
            .padding(.horizontal, DS.Space.s40)

            Spacer()

            // Buttons
            HStack(spacing: DS.Space.s16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .padding(.horizontal, DS.Space.s24)
                .padding(.vertical, DS.Space.s12)

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pin.count != pinLength || isSubmitting)
                .padding(.horizontal, DS.Space.s24)
                .padding(.vertical, DS.Space.s12)
            }
            .padding(.bottom, DS.Space.s20)
        }
        .frame(width: 400, height: 550)
        .background(theme.settingsWindowBackground)
        .onAppear {
            isFocused = true
        }
    }

    private func digitAt(_ index: Int) -> String? {
        guard index < pin.count else { return nil }
        let pinIndex = pin.index(pin.startIndex, offsetBy: index)
        return String(pin[pinIndex])
    }

    private func appendDigit(_ digit: String) {
        guard pin.count < pinLength else { return }
        pin += digit
        if pin.count == pinLength {
            submit()
        }
    }

    private func deleteLastDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }

    private func submit() {
        guard pin.count == pinLength, !isSubmitting else { return }
        isSubmitting = true
        onSubmit(pin)
    }
}

// MARK: - PIN Digit Display

struct PinDigitView: View {
    @Environment(\.flixorTheme) private var theme
    let digit: String?
    let isFilled: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.r8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 50, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.r8)
                        .stroke(isFilled ? theme.accent : Color.gray.opacity(0.3), lineWidth: 2)
                )

            if isFilled {
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
            }
        }
    }
}

// MARK: - Number Pad Button

struct NumberPadButton: View {
    let digit: String
    var isSymbol: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isPressed ? Color.gray.opacity(0.3) : Color.gray.opacity(0.15))
                    .frame(width: 70, height: 70)

                if isSymbol {
                    Image(systemName: digit)
                        .font(.title2)
                        .foregroundColor(.white)
                } else {
                    Text(digit)
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isPressed = hovering
        }
    }
}

#if DEBUG
struct PinEntryView_Previews: PreviewProvider {
    static var previews: some View {
        // Preview would require mock PlexHomeUser
        Text("PIN Entry Preview")
            .frame(width: 400, height: 550)
    }
}
#endif
