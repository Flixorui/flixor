//
//  PinEntryView.swift
//  FlixorMac
//
//  PIN entry modal for protected Plex profiles
//

import SwiftUI
import FlixorKit

struct PinEntryView: View {
    let user: PlexHomeUser
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    private let pinLength = 4

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 16) {
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
            HStack(spacing: 16) {
                ForEach(0..<pinLength, id: \.self) { index in
                    PinDigitView(
                        digit: digitAt(index),
                        isFilled: index < pin.count
                    )
                }
            }
            .padding(.vertical, 20)

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
            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 12) {
                        ForEach(1...3, id: \.self) { col in
                            let digit = row * 3 + col
                            NumberPadButton(digit: String(digit)) {
                                appendDigit(String(digit))
                            }
                        }
                    }
                }
                HStack(spacing: 12) {
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
            .padding(.horizontal, 40)

            Spacer()

            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

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
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 550)
        .background(Color(nsColor: .windowBackgroundColor))
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
    let digit: String?
    let isFilled: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 50, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isFilled ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 2)
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
