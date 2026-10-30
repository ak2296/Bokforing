import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/ocr_document.dart';

/// On-device OCR (bundled Latin model, works offline).
Future<OcrDocument> recognizeDocument(String imagePath) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
    final lines = <OcrLine>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final r = line.boundingBox;
        lines.add(OcrLine(line.text, r.left, r.top, r.right, r.bottom));
      }
    }
    return OcrDocument(result.text, lines);
  } finally {
    await recognizer.close();
  }
}
