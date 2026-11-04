import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show compute;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/ocr_models.dart';
import '../imaging/preprocess.dart';

/// On-device text recognition with ML Kit's bundled Latin model (offline).
class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Reads [path]. A paper photographed sideways is turned and read again;
  /// the file is replaced when that reads clearly more, so the review screen
  /// also shows it upright.
  Future<OcrResult> recognizeFile(String path, {int width = 0, int height = 0}) async {
    final first = await _read(path, width, height);
    if (!first.looksSideways) return first;
    final original = await File(path).readAsBytes();
    var best = first;
    List<int>? bestBytes;
    for (final degrees in const [90, 270]) {
      final turned = await compute(rotateJpeg, PreprocessRotate(original, degrees));
      final tmp = '$path.$degrees.jpg';
      await File(tmp).writeAsBytes(turned);
      final result = await _read(tmp, width, height);
      await File(tmp).delete();
      if (result.uprightLetters > best.uprightLetters * 1.5) {
        best = result;
        bestBytes = turned;
      }
    }
    if (bestBytes != null) await File(path).writeAsBytes(bestBytes);
    return best;
  }

  Future<OcrResult> _read(String path, int width, int height) async {
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
