import SwiftUI
import CoreImage.CIFilterBuiltins

class QRCodeGenerator {
    static let shared = QRCodeGenerator()
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()
    
    func generate(from string: String) -> UIImage {
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            // Scale up the image so it's sharp
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
}
