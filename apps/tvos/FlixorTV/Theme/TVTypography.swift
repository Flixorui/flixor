import CoreText
import SwiftUI
import UIKit

struct TVTypographySet: Equatable {
    let appFont: TVAppFont

    var hero: Font { font(size: 68, weight: .bold) }
    var title: Font { font(size: 38, weight: .bold) }
    var section: Font { font(size: 32, weight: .bold) }
    var nav: Font { font(size: 28, weight: .semibold) }
    var body: Font { font(size: 20, weight: .medium) }
    var label: Font { font(size: 18, weight: .semibold) }
    var meta: Font { font(size: 16, weight: .medium) }
    var settingsHeader: Font { font(size: 46, weight: .bold) }

    func custom(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        font(size: size, weight: weight)
    }

    private func font(size: CGFloat, weight: Font.Weight) -> Font {
        TVFontRegistry.registerBundledFontsIfNeeded()

        guard let fontName = TVFontRegistry.fontName(for: appFont) else {
            return .system(size: size, weight: weight)
        }

        return .custom(fontName, size: size).weight(weight)
    }
}

enum TVFontRegistry {
    private static var didRegister = false
    private static var fontNames: [TVAppFont: String] = [:]

    static func registerBundledFontsIfNeeded() {
        guard !didRegister else { return }
        didRegister = true

        register(appFont: .inter, fileName: "InterVariable", fallbacks: ["Inter", "Inter-Regular"])
        register(appFont: .dmSans, fileName: "DMSansVariable", fallbacks: ["DMSans-Regular", "DM Sans", "DMSans 18pt"])
        register(appFont: .openSans, fileName: "OpenSansVariable", fallbacks: ["OpenSans-Regular", "Open Sans", "OpenSans"])
    }

    static func fontName(for appFont: TVAppFont) -> String? {
        guard appFont != .system else { return nil }
        return fontNames[appFont]
    }

    private static func register(appFont: TVAppFont, fileName: String, fallbacks: [String]) {
        if let url = Bundle.main.url(forResource: fileName, withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.url(forResource: fileName, withExtension: "ttf"),
           let resolved = registerFont(at: url) {
            fontNames[appFont] = resolved
            return
        }

        if let fallback = fallbacks.first(where: { UIFont(name: $0, size: 18) != nil }) {
            fontNames[appFont] = fallback
        }
    }

    private static func registerFont(at url: URL) -> String? {
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)

        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let descriptor = descriptors.first,
           let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
           UIFont(name: postScriptName, size: 18) != nil {
            return postScriptName
        }

        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider),
              let postScriptName = cgFont.postScriptName as String?,
              UIFont(name: postScriptName, size: 18) != nil else {
            return nil
        }

        return postScriptName
    }
}
