import 'ocr_models.dart';

/// Common interface so specialised parsers (one supplier, one cash register)
/// can be added later next to the generic ones.
abstract class DocumentParser<T> {
  T parse(OcrResult ocr);
}
