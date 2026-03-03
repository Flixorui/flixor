import SwiftUI
import UIKit

struct TVSearchTextField: UIViewRepresentable {
    typealias UIViewType = UITextField

    @Binding var text: String
    let placeholder: String
    var accentColor: Color
    var textColor: Color
    var backgroundColor: Color
    var borderColor: Color

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.returnKeyType = .search
        textField.clearButtonMode = .whileEditing
        textField.enablesReturnKeyAutomatically = false
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.borderStyle = .none
        textField.backgroundColor = UIColor(backgroundColor)
        textField.textColor = UIColor(textColor)
        textField.tintColor = UIColor(accentColor)
        textField.leftView?.tintColor = UIColor(textColor.opacity(0.7))
        textField.layer.cornerRadius = 16
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor(borderColor).cgColor
        let iconView = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        iconView.tintColor = UIColor(textColor.opacity(0.7))
        iconView.contentMode = .center
        iconView.frame = CGRect(x: 0, y: 0, width: 36, height: 24)
        textField.leftView = iconView
        textField.leftViewMode = .always
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(textColor.opacity(0.58))]
        )
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.backgroundColor = UIColor(backgroundColor)
        uiView.textColor = UIColor(textColor)
        uiView.tintColor = UIColor(accentColor)
        uiView.layer.borderColor = UIColor(borderColor).cgColor
        if let iconView = uiView.leftView as? UIImageView {
            iconView.tintColor = UIColor(textColor.opacity(0.7))
        }
        uiView.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(textColor.opacity(0.58))]
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldClear(_ textField: UITextField) -> Bool {
            text = ""
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
