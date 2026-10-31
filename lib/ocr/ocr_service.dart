import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/ocr_models.dart';

/// On-device text recognition with ML Kit's bundled Latin model (offline).
class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<OcrResult> recognizeFile(String path, {int width = 0, int height = 0}) async {
    final recognized = await _recognizer.processImage(InputImage.fromFilePath(path));
    OcrBox box(Rect r) => OcrBox(r.left, r.top, r.right, r.bottom);
    return OcrResult(
      text: recognized.text,
      imageWidth: width,
      imageHeight: height,
      blocks: [
        for (final b in recognized.blocks)
          OcrBlock(b.text, box(b.boundingBox), [
            for (final l in b.lines)
              OcrLine(
                l.text,
                box(l.boundingBox),
                confidence: l.confidence,
                angle: l.angle,
                words: [
                  for (final e in l.elements) OcrElement(e.text, box(e.boundingBox), confidence: e.confidence),
                ],
              ),
          ]),
      ],
    );
  }

  Future<void> close() => _recognizer.close();
}
