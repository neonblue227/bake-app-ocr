import CoreGraphics
import Vision

/// Thin wrapper around Vision's text recognition.
///
/// Kept deliberately small: it turns a `CGImage` into loose ``RecognizedWord``
/// values and nothing else. All interpretation happens later, in the parser.
struct VisionTextRecognizer {
    var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    var usesLanguageCorrection = true
    var recognitionLanguages: [String]?
    /// Ignore text smaller than this fraction of the image height.
    var minimumTextHeight: Float?

    func recognize(in image: CGImage) throws -> [RecognizedWord] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = usesLanguageCorrection
        if let minimumTextHeight {
            request.minimumTextHeight = minimumTextHeight
        }
        if let recognitionLanguages, !recognitionLanguages.isEmpty {
            // An unsupported code (Thai before iOS 17, or Thai with `.fast`)
            // makes the request fail, so keep only what this system can read.
            let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
            let usable = recognitionLanguages.filter(supported.contains)
            if !usable.isEmpty {
                request.recognitionLanguages = usable
            }
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }

        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedWord(
                text: candidate.string,
                boundingBox: observation.boundingBox,
                confidence: candidate.confidence
            )
        }
    }
}
