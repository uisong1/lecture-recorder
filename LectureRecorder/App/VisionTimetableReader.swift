import CoreGraphics
import Foundation
import ImageIO
import LectureCore
import Vision

/// 시간표 이미지를 읽는 실제 구현. 글자는 맥에 내장된 Vision으로 읽고(무료, 기기 안에서만 처리),
/// 칸의 위아래와 눈금줄은 이미지 픽셀에서 찾는다. 해석은 `TimetableReader`가 한다.
struct VisionTimetableReader: TimetableImageReading {
    enum ReadError: Error, LocalizedError {
        case unreadableImage
        case noPixels

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "이미지 파일을 해석하지 못했습니다. PNG나 JPEG 캡처인지 확인해 주세요."
            case .noPixels: "이미지의 색을 읽지 못했습니다."
            }
        }
    }

    func readTimetable(from imageData: Data) async throws -> TimetableDraft {
        // Vision과 픽셀 읽기는 오래 걸릴 수 있어 화면을 막지 않도록 따로 돌린다.
        try await Task.detached(priority: .userInitiated) {
            try Self.read(imageData)
        }.value
    }

    private static func read(_ data: Data) throws -> TimetableDraft {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ReadError.unreadableImage }
        let pixels = try pixels(of: image)
        let observations = try recognizeText(in: image)
        return try TimetableReader.read(observations: observations, pixels: pixels)
    }

    /// 이미지를 RGBA(픽셀당 4바이트, 위에서 아래로)로 푼다.
    private static func pixels(of image: CGImage) throws -> TimetablePixels {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw ReadError.noPixels }
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, let pixels = TimetablePixels(width: width, height: height, rgba: bytes) else { throw ReadError.noPixels }
        return pixels
    }

    /// Vision이 읽은 줄마다 낱말 위치를 얻어, 서로 멀리 떨어진 글자(요일 머리글, 옆 칸의 과목명)가
    /// 한 줄로 합쳐졌어도 다시 나눈다. 좌표는 이미지 픽셀(왼쪽 위 원점)로 바꿔 돌려준다.
    private static func recognizeText(in image: CGImage) throws -> [LectureCore.TextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = ["ko-KR", "en-US"].filter { supported.contains($0) }
        if !wanted.isEmpty { request.recognitionLanguages = wanted }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])

        let width = Double(image.width)
        let height = Double(image.height)
        var result: [LectureCore.TextObservation] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            var words: [LectureCore.TextObservation] = []
            for range in TimetableWordGrouping.wordRanges(in: text) {
                guard let box = try? candidate.boundingBox(for: range)?.boundingBox else { continue }
                words.append(LectureCore.TextObservation(
                    text: String(text[range]),
                    x: box.minX * width,
                    y: (1 - box.maxY) * height,
                    width: box.width * width,
                    height: box.height * height
                ))
            }
            if words.isEmpty {
                // 낱말 위치를 얻지 못하면 줄 전체의 위치를 쓴다.
                let box = observation.boundingBox
                result.append(LectureCore.TextObservation(text: text, x: box.minX * width, y: (1 - box.maxY) * height, width: box.width * width, height: box.height * height))
            } else {
                result.append(contentsOf: TimetableWordGrouping.merge(words))
            }
        }
        return result
    }
}
