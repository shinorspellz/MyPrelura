//
//  BackgroundRemovalService.swift
//  Prelura-swift
//
//  On-device background removal: Vision person segmentation + Core Image CIBlendWithMask.
//  Same approach as Outfeatz. Not supported in Simulator.
//

import Foundation
import Vision
import CoreImage
import UIKit

enum BackgroundRemovalError: LocalizedError {
    case noPersonInImage
    case simulatorUnsupported
    case segmentationFailed
    case compositeFailed

    var errorDescription: String? {
        switch self {
        case .noPersonInImage:
            return "No person detected. Use a photo with a clear person."
        case .simulatorUnsupported:
            return "Background removal isn't supported in the Simulator. Try on a device."
        case .segmentationFailed:
            return "Could not analyze the image."
        case .compositeFailed:
            return "Could not apply the theme."
        }
    }
}

/// Theme background for shop photos (no custom upload – app-provided only).
struct ThemeBackground: Identifiable {
    let id: String
    let name: String
    let colorTop: UIColor
    let colorBottom: UIColor?

    init(id: String, name: String, color: UIColor) {
        self.id = id
        self.name = name
        self.colorTop = color
        self.colorBottom = nil
    }

    init(id: String, name: String, gradientTop: UIColor, gradientBottom: UIColor) {
        self.id = id
        self.name = name
        self.colorTop = gradientTop
        self.colorBottom = gradientBottom
    }

    func ciImage(size: CGSize) -> CIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            if let bottom = colorBottom {
                let colors = [colorTop.cgColor, bottom.cgColor]
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) else { return }
                ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
            } else {
                colorTop.setFill()
                ctx.cgContext.fill(rect)
            }
        }
        return CIImage(image: image)
    }
}

extension ThemeBackground {
    static let all: [ThemeBackground] = [
        ThemeBackground(id: "white", name: "Clean White", color: UIColor(white: 0.98, alpha: 1)),
        ThemeBackground(id: "grey", name: "Soft Grey", color: UIColor(white: 0.94, alpha: 1)),
        ThemeBackground(id: "beige", name: "Warm Beige", color: UIColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1)),
        ThemeBackground(id: "coolgrey", name: "Cool Grey", color: UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1)),
        ThemeBackground(id: "mint", name: "Light Mint", gradientTop: UIColor(red: 0.85, green: 0.97, blue: 0.92, alpha: 1), gradientBottom: UIColor(red: 0.75, green: 0.95, blue: 0.88, alpha: 1)),
        ThemeBackground(id: "lavender", name: "Soft Lavender", gradientTop: UIColor(red: 0.95, green: 0.92, blue: 0.98, alpha: 1), gradientBottom: UIColor(red: 0.90, green: 0.85, blue: 0.96, alpha: 1)),
        ThemeBackground(id: "blush", name: "Blush", gradientTop: UIColor(red: 1, green: 0.95, blue: 0.95, alpha: 1), gradientBottom: UIColor(red: 0.98, green: 0.90, blue: 0.92, alpha: 1)),
        ThemeBackground(id: "sky", name: "Soft Sky", gradientTop: UIColor(red: 0.88, green: 0.94, blue: 1, alpha: 1), gradientBottom: UIColor(red: 0.80, green: 0.90, blue: 0.98, alpha: 1)),
    ]
}

@MainActor
final class BackgroundRemovalService {
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Max dimension for Vision input (balance quality vs speed).
    private let maxDimension: CGFloat = 1024

    /// Removes background using Vision person segmentation, then composites onto the theme.
    /// Flow: normalize image → Vision mask → CIBlendWithMask (person kept, background = theme).
    /// On Simulator, Vision is unsupported → throws .simulatorUnsupported.
    func removeBackground(from image: UIImage, theme: ThemeBackground) async throws -> UIImage {
        #if targetEnvironment(simulator)
        throw BackgroundRemovalError.simulatorUnsupported
        #endif

        let normalized = normalizeImage(image)
        guard let inputCIImage = CIImage(image: normalized) else { throw BackgroundRemovalError.compositeFailed }
        let size = inputCIImage.extent.size

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler: VNImageRequestHandler
        if inputCIImage.extent.origin != .zero {
            let translated = inputCIImage.transformed(by: CGAffineTransform(translationX: -inputCIImage.extent.origin.x, y: -inputCIImage.extent.origin.y))
            handler = VNImageRequestHandler(ciImage: translated, options: [:])
        } else {
            handler = VNImageRequestHandler(ciImage: inputCIImage, options: [:])
        }

        do {
            try handler.perform([request])
        } catch {
            throw BackgroundRemovalError.segmentationFailed
        }

        guard let result = request.results?.first else {
            throw BackgroundRemovalError.noPersonInImage
        }

        let maskBuffer = result.pixelBuffer
        let maskImage = CIImage(cvPixelBuffer: maskBuffer)

        guard let background = theme.ciImage(size: size) else {
            throw BackgroundRemovalError.compositeFailed
        }

        let maskExt = maskImage.extent
        let scaleX = size.width / maskExt.width
        let scaleY = size.height / maskExt.height
        let scaledMask = maskImage.transformed(by: CGAffineTransform(translationX: -maskExt.minX, y: -maskExt.minY).scaledBy(x: scaleX, y: scaleY))

        guard let blend = CIFilter(name: "CIBlendWithMask") else {
            throw BackgroundRemovalError.compositeFailed
        }
        blend.setValue(inputCIImage, forKey: kCIInputImageKey)
        blend.setValue(background, forKey: kCIInputBackgroundImageKey)
        blend.setValue(scaledMask, forKey: kCIInputMaskImageKey)

        guard let output = blend.outputImage else {
            throw BackgroundRemovalError.compositeFailed
        }

        let cropRect = output.extent
        guard let cgImage = context.createCGImage(output, from: cropRect) else {
            throw BackgroundRemovalError.compositeFailed
        }
        return UIImage(cgImage: cgImage, scale: normalized.scale, orientation: .up)
    }

    /// Normalize to single orientation and reasonable resolution for Vision.
    private func normalizeImage(_ image: UIImage) -> UIImage {
        let targetSize = scaledSize(for: image.size, maxDimension: maxDimension)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalized
    }

    private func scaledSize(for size: CGSize, maxDimension: CGFloat) -> CGSize {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return size }
        let scale = maxDimension / maxSide
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
