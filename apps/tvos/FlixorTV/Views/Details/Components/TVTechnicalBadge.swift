import SwiftUI

struct TVTechnicalBadge: View {
    let text: String

    private var imageAssetName: String? {
        let lower = text.lowercased()
        if lower == "4k" || lower == "uhd" || lower == "2160p" { return "4K" }
        if lower == "hd" || lower == "1080p" || lower == "1080i" || lower == "fhd" || lower == "720p" || lower == "hd ready" { return "hd" }
        if lower.contains("hdr10+") || lower.contains("hdr10 plus") { return "hdr10+" }
        if lower.contains("dolby vision") || lower == "dv" || lower.contains("dovi") { return "dolbyVision" }
        if lower.contains("hdr10") || lower.contains("hdr 10") || lower == "hdr" { return "hdr" }
        if lower.contains("atmos") || lower.contains("truehd") { return "dolbyatmos" }
        if lower == "cc" || lower.contains("closed caption") { return "cc" }
        if lower == "sdh" || lower.contains("hard of hearing") { return "sdh" }
        if lower == "ad" || lower.contains("audio desc") { return "ad" }
        return nil
    }

    var body: some View {
        if let assetName = imageAssetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(height: 14)
        } else {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.84))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}
