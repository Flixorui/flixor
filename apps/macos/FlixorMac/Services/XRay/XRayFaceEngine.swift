//
//  XRayFaceEngine.swift
//  FlixorMac
//
//  On-device face finding and face embeddings for X-Ray. Vision finds faces and their
//  landmarks; each face is aligned to SFace's 112x112 template and turned into a
//  128-number embedding by the bundled SFace model (OpenCV Zoo, Apache-2.0).
//  Two embeddings of the same person have a high cosine similarity.
//
//  No app dependencies, so the accuracy test tool can compile it on its own.
//

import Foundation
import CoreGraphics
import CoreML
import Vision

struct XRayDetectedFace {
    /// Pixels, top-left origin.
    let box: CGRect
    let confidence: Float
    /// Unit length.
    let embedding: [Float]
}

final class XRayFaceEngine {
    /// Faces smaller than this (shorter side, pixels at 960 wide) aren't matched: too
    /// little detail, and they're mostly extras in the background.
    static let minFaceSide: CGFloat = 44
    /// Vision confidence below this is usually not a face (a patterned coat, a mask).
    static let minConfidence: Float = 0.6

    private let model: MLModel
    private let inputName: String
    private let outputName: String

    /// SFace's 112x112 template: image-left eye, image-right eye, nose tip, image-left
    /// mouth corner, image-right mouth corner. The same one OpenCV's alignCrop uses.
    private static let template: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366), CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041)
    ]

    init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        // The Neural Engine or GPU; the player keeps the GPU busy, Core ML balances it.
        config.computeUnits = .all
        model = try MLModel(contentsOf: modelURL, configuration: config)
        inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "face"
        outputName = model.modelDescription.outputDescriptionsByName.keys.first ?? "embedding"
    }

    /// The model bundled with the app (compiled by Xcode from SFace.mlpackage).
    static func bundled() -> XRayFaceEngine? {
        guard let url = Bundle.main.url(forResource: "SFace", withExtension: "mlmodelc") else {
            print("⚠️ [XRay] Face model missing from the app bundle")
            return nil
        }
        do {
            return try XRayFaceEngine(modelURL: url)
        } catch {
            print("⚠️ [XRay] Face model failed to load: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: Faces in a frame

    /// Every usable face in `image`, with its embedding. Blocking; call off the main thread.
    func faces(in image: CGImage, minSide: CGFloat = XRayFaceEngine.minFaceSide) -> [XRayDetectedFace] {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        var out: [XRayDetectedFace] = []
        for observation in request.results ?? [] {
            // Vision boxes are normalised with a bottom-left origin.
            let b = observation.boundingBox
            let box = CGRect(x: b.minX * width, y: (1 - b.maxY) * height, width: b.width * width, height: b.height * height)
            guard min(box.width, box.height) >= minSide, observation.confidence >= Self.minConfidence,
                  let points = Self.alignmentPoints(observation, imageSize: CGSize(width: width, height: height)),
                  let crop = Self.alignedCrop(image, points: points),
                  let embedding = embed(crop) else { continue }
            out.append(XRayDetectedFace(box: box, confidence: observation.confidence, embedding: embedding))
        }
        return out
    }

    /// Embedding of the largest face, for reference photos (one person per photo).
    func largestFaceEmbedding(in image: CGImage) -> [Float]? {
        let found = faces(in: image, minSide: 40)
        return found.max { $0.box.width * $0.box.height < $1.box.width * $1.box.height }?.embedding
    }

    // MARK: Alignment

    /// The five template points of a face, in pixels with a top-left origin.
    private static func alignmentPoints(_ face: VNFaceObservation, imageSize: CGSize) -> [CGPoint]? {
        guard let lm = face.landmarks else { return nil }
        func pts(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let region, region.pointCount > 0 else { return [] }
            return region.pointsInImage(imageSize: imageSize).map { CGPoint(x: $0.x, y: imageSize.height - $0.y) }
        }
        func centre(_ p: [CGPoint]) -> CGPoint? {
            guard !p.isEmpty else { return nil }
            return CGPoint(x: p.map(\.x).reduce(0, +) / CGFloat(p.count), y: p.map(\.y).reduce(0, +) / CGFloat(p.count))
        }
        guard let eyeA = centre(pts(lm.leftPupil)) ?? centre(pts(lm.leftEye)),
              let eyeB = centre(pts(lm.rightPupil)) ?? centre(pts(lm.rightEye)) else { return nil }
        let crest = pts(lm.noseCrest), nose = pts(lm.nose)
        // Nose tip: the lowest point of the crest (bridge to tip), else of the nose outline.
        guard let tip = (crest.isEmpty ? nose : crest).max(by: { $0.y < $1.y }) else { return nil }
        let lips = pts(lm.outerLips)
        guard let mouthLeft = lips.min(by: { $0.x < $1.x }), let mouthRight = lips.max(by: { $0.x < $1.x }) else { return nil }
        let eyes = [eyeA, eyeB].sorted { $0.x < $1.x }
        return [eyes[0], eyes[1], tip, mouthLeft, mouthRight]
    }

    /// Least-squares similarity transform (rotation, uniform scale, shift) taking
    /// `src` onto `dst` (Umeyama without reflection).
    static func similarity(from src: [CGPoint], to dst: [CGPoint]) -> CGAffineTransform? {
        let n = CGFloat(src.count)
        guard src.count == dst.count, src.count >= 2 else { return nil }
        let sx = src.map(\.x).reduce(0, +) / n, sy = src.map(\.y).reduce(0, +) / n
        let dx = dst.map(\.x).reduce(0, +) / n, dy = dst.map(\.y).reduce(0, +) / n
        var a: CGFloat = 0, b: CGFloat = 0, varS: CGFloat = 0
        for (p, q) in zip(src, dst) {
            let px = p.x - sx, py = p.y - sy, qx = q.x - dx, qy = q.y - dy
            a += px * qx + py * qy
            b += px * qy - py * qx
            varS += px * px + py * py
        }
        guard varS > 0 else { return nil }
        let c = a / varS, s = b / varS
        // x' = c*x - s*y + tx ; y' = s*x + c*y + ty
        return CGAffineTransform(a: c, b: s, c: -s, d: c, tx: dx - (c * sx - s * sy), ty: dy - (s * sx + c * sy))
    }

    /// The face warped onto the 112x112 template, RGB.
    static func alignedCrop(_ image: CGImage, points: [CGPoint]) -> CGImage? {
        guard let t = similarity(from: points, to: template) else { return nil }
        let size = 112
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // Work in top-left coordinates on both sides: flip the context, apply the
        // transform, then flip the image back so it isn't drawn upside down.
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
        ctx.concatenate(t)
        ctx.translateBy(x: 0, y: CGFloat(image.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage()
    }

    // MARK: Embedding

    private func embed(_ crop: CGImage) -> [Float]? {
        guard let constraint = model.modelDescription.inputDescriptionsByName[inputName]?.imageConstraint,
              let value = try? MLFeatureValue(cgImage: crop, constraint: constraint, options: nil),
              let input = try? MLDictionaryFeatureProvider(dictionary: [inputName: value]),
              let output = try? model.prediction(from: input),
              let array = output.featureValue(for: outputName)?.multiArrayValue else { return nil }
        var v = [Float](repeating: 0, count: array.count)
        for i in 0..<array.count { v[i] = array[i].floatValue }
        return XRayMath.normalised(v)
    }
}

enum XRayMath {
    static func normalised(_ v: [Float]) -> [Float]? {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0, norm.isFinite else { return nil }
        return v.map { $0 / norm }
    }

    /// Cosine similarity of two unit vectors.
    @inline(__always)
    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        for i in 0..<min(a.count, b.count) { s += a[i] * b[i] }
        return s
    }
}
