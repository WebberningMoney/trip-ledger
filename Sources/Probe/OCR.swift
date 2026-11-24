// OCR.swift：文字辨識（從收據照片讀出字）。
//
// 用的是 macOS 內建的 Vision 框架，完全在這台 Mac 上執行、不連網。
// 照片裡的每一小段文字，Vision 會回傳「內容＋在照片上的位置」。
// 收據常常是「左邊標籤、右邊數字」（例如「합계 …… 8,200」），Vision 會把它們拆成兩段，
// 所以這裡再依照上下位置，把同一橫排的文字接回同一行，方便後面的規則判讀。

import Foundation
import Vision
import CoreGraphics
import ImageIO

/// 辨識出來的一小段文字和它在照片上的位置（座標是 0～1 的比例，原點在左下角）。
struct OCRPiece {
    let text: String
    let box: CGRect
}

enum OCR {
    /// 讀取照片。會依照片裡記錄的拍攝方向自動轉正，最長邊縮到 4096 像素以內。
    static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 這台 Mac 的 Vision 支援哪些語言（寫進報告，方便確認有沒有韓文）。
    static func supportedLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? []
    }

    /// 辨識一張照片裡的所有文字（韓文＋英文，用「精準」模式）。
    static func recognize(_ image: CGImage) throws -> [OCRPiece] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            return OCRPiece(text: best.string, box: observation.boundingBox)
        }
    }

    /// 把文字片段依「由上到下、由左到右」排好，同一橫排的接成一行（中間用兩個空白隔開）。
    static func rows(_ pieces: [OCRPiece]) -> [String] {
        let sorted = pieces.sorted { $0.box.midY > $1.box.midY }
        var groups: [[OCRPiece]] = []
        for piece in sorted {
            if let first = groups.last?.first,
               abs(first.box.midY - piece.box.midY) < min(first.box.height, piece.box.height) * 0.6 {
                groups[groups.count - 1].append(piece)
            } else {
                groups.append([piece])
            }
        }
        return groups.map { group in
            group.sorted { $0.box.minX < $1.box.minX }.map { $0.text }.joined(separator: "  ")
        }
    }
}
