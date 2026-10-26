import SwiftUI
import UIKit

public struct DistroLogoView: View {
    public let imageName: String?
    public let size: CGFloat

    public init(imageName: String?, size: CGFloat = 36) {
        self.imageName = imageName
        self.size = size
    }

    public var body: some View {
        Group {
            if let name = imageName, let _ = UIImage(named: name) {
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
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
