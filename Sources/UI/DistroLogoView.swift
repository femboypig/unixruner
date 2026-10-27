import SwiftUI
import UIKit

public struct DistroLogoView: View {
    public let imageName: String?
    public let size: CGFloat

    private static var thumbnailCache: [String: UIImage] = [:]

    public init(imageName: String?, size: CGFloat = 36) {
        self.imageName = imageName
        self.size = size
    }

    private var thumbnailImage: UIImage? {
        guard let name = imageName, !name.isEmpty else { return nil }
        let cacheKey = "\(name)_\(Int(size))"
        if let cached = Self.thumbnailCache[cacheKey] {
            return cached
        }
        guard let original = UIImage(named: name) else { return nil }
        let targetSize = CGSize(width: size * 2, height: size * 2)
        let thumb = original.preparingThumbnail(of: targetSize) ?? original
        Self.thumbnailCache[cacheKey] = thumb
        return thumb
    }

    public var body: some View {
        Group {
            if let thumb = thumbnailImage {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemFill))
                    Image(systemName: "terminal.fill")
                        .font(.system(size: size * 0.45))
                        .foregroundColor(.primary)
                }
                .frame(width: size, height: size)
            }
        }
    }
}
