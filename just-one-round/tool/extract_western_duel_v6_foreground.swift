import AppKit
import CoreImage
import Foundation
import Vision

guard CommandLine.arguments.count == 5 else {
    fatalError("Usage: extract_western_duel_v6_foreground.swift raw.png mask.png cutout.png instance-directory")
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let cutoutURL = URL(fileURLWithPath: CommandLine.arguments[3])
let instancesDirectory = URL(fileURLWithPath: CommandLine.arguments[4])
let handler = VNImageRequestHandler(url: inputURL)
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let observation = request.results?.first else {
    fatalError("Vision returned no foreground instances")
}
guard observation.allInstances.count == 6 else {
    fatalError("Expected six foreground instances, found \\(observation.allInstances.count)")
}

let mask = try observation.generateScaledMaskForImage(
    forInstances: observation.allInstances,
    from: handler
)
let maskImage = CIImage(cvPixelBuffer: mask)
let context = CIContext()
let sourceImage = CIImage(contentsOf: inputURL)!
let clearBackground = CIImage(color: .clear).cropped(to: sourceImage.extent)

func writePNG(_ image: CIImage, to url: URL) throws {
    guard let cgImage = context.createCGImage(image, from: sourceImage.extent),
          let data = NSBitmapImageRep(cgImage: cgImage).representation(
            using: .png,
            properties: [:]
          ) else {
        fatalError("Failed to encode \\(url.lastPathComponent)")
    }
    try data.write(to: url)
}

try FileManager.default.createDirectory(
    at: instancesDirectory,
    withIntermediateDirectories: true
)
try writePNG(maskImage, to: outputURL)

let combinedCutout = sourceImage.applyingFilter(
    "CIBlendWithMask",
    parameters: [
        kCIInputBackgroundImageKey: clearBackground,
        kCIInputMaskImageKey: maskImage,
    ]
)
try writePNG(combinedCutout, to: cutoutURL)

for instance in observation.allInstances {
    let instanceMask = try observation.generateScaledMaskForImage(
        forInstances: IndexSet(integer: instance),
        from: handler
    )
    let isolated = sourceImage.applyingFilter(
        "CIBlendWithMask",
        parameters: [
            kCIInputBackgroundImageKey: clearBackground,
            kCIInputMaskImageKey: CIImage(cvPixelBuffer: instanceMask),
        ]
    )
    let instanceURL = instancesDirectory.appendingPathComponent(
        String(format: "instance_%02d.png", instance)
    )
    try writePNG(isolated, to: instanceURL)
}

print("extracted \\(observation.allInstances.count) foreground instances to \\(instancesDirectory.path)")
