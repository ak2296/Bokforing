import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../data/repository.dart';
import 'ai_result.dart';

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}

/// Settings for the optional online analysis. Off unless the owner has
/// switched it on and pasted their own API key; the key is kept in the
/// phone's secure storage, never in the database or backups.
class AiSettings {
  static const enabledKey = 'ai_enabled';
  static const modelKey = 'ai_model';
  static const defaultModel = 'gemini-3.8-flash';
  static const fallbackModel = 'gemini-3.5-flash-lite';
  static const _secureKey = 'gemini_api_key';
  static const _storage = FlutterSecureStorage();

  final bool enabled;
  final String? apiKey;
  final String model;
  const AiSettings(this.enabled, this.apiKey, this.model);

  bool get usable => enabled && (apiKey ?? '').isNotEmpty;

  static Future<AiSettings> load(Repository repo) async {
    final enabled = await repo.boolSetting(enabledKey);
    final model = await repo.setting(modelKey) ?? defaultModel;
    String? key;
    try {
      key = await _storage.read(key: _secureKey);
    } catch (_) {
      key = null;
    }
    return AiSettings(enabled, key, model);
  }

  static Future<void> saveKey(String? key) async {
    if (key == null || key.trim().isEmpty) {
      await _storage.delete(key: _secureKey);
    } else {
      await _storage.write(key: _secureKey, value: key.trim());
    }
  }
}

/// Calls the Gemini API (generateContent) with the document photo and asks
/// for strict JSON. Model names and free limits were checked on
/// ai.google.dev on 2026-10-31.
class GeminiClient {
  final String apiKey;
  final String model;
  final http.Client _http;
  GeminiClient({required this.apiKey, required this.model, http.Client? client}) : _http = client ?? http.Client();

  static const _prompt = '''
You read Swedish bookkeeping documents: supplier invoices or receipts ("faktura", "kvitto") and cash register day reports ("Z-rapport").
Return JSON that follows the schema. Rules:
- Copy every amount EXACTLY as printed (keep spaces, commas, minus signs). Do not calculate, round or convert anything.
- Use null for anything that is not printed. Never guess or invent values.
- Dates as YYYY-MM-DD.
- Invoice/receipt: total_text is the amount to pay or the total including VAT ("Att betala", "Totalt", "Summa"). Never use cash received ("Kontant", "Mottaget"), change ("Växel", "Tillbaka"), net amounts ("Netto", "Exkl. moms", "Momspliktigt belopp") or subtotals.
- vat_lines: one entry per VAT rate printed, with the VAT amount and, if printed, the net and gross amounts for that rate. Skip rates whose VAT is zero.
- Z-report: z_rows lists each sales row per product group/department ("varugrupp", "avdelning", "kategori") with its amount including VAT. total_text is the day's total sales including VAT for this report, never a grand total or accumulated total. date is the business date of the report.
- document_type: "faktura" for invoices and receipts, "z_rapport" for Z-reports, "annat" otherwise.''';

  static const Map<String, dynamic> _schema = {
    'type': 'OBJECT',
    'properties': {
      'document_type': {'type': 'STRING', 'enum': ['faktura', 'z_rapport', 'annat']},
      'date': {'type': 'STRING', 'nullable': true},
      'supplier': {'type': 'STRING', 'nullable': true},
      'invoice_number': {'type': 'STRING', 'nullable': true},
      'ocr_reference': {'type': 'STRING', 'nullable': true},
      'due_date': {'type': 'STRING', 'nullable': true},
      'total_text': {'type': 'STRING', 'nullable': true},
      'vat_total_text': {'type': 'STRING', 'nullable': true},
      'vat_lines': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'rate_percent': {'type': 'STRING'},
            'vat_text': {'type': 'STRING'},
            'net_text': {'type': 'STRING', 'nullable': true},
            'gross_text': {'type': 'STRING', 'nullable': true},
          },
          'required': ['rate_percent', 'vat_text'],
        },
      },
      'z_number': {'type': 'STRING', 'nullable': true},
      'z_rows': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'label': {'type': 'STRING'},
            'amount_text': {'type': 'STRING'},
          },
          'required': ['label', 'amount_text'],
        },
      },
      'notes': {'type': 'STRING', 'nullable': true},
    },
    'required': ['document_type'],
  };

  Future<AiResult> analyze(List<Uint8List> jpegs) async {
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': _prompt},
            for (final j in jpegs) {'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(j)}},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0,
        'response_mime_type': 'application/json',
        'response_schema': _schema,
      },
    });
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    http.Response res;
    try {
      res = await _http
          .post(uri, headers: {'x-goog-api-key': apiKey, 'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 90));
    } on SocketException {
      throw const AiException('Ingen internetanslutning. Kontrollera wifi eller mobildata.');
    } on TimeoutException {
      throw const AiException('Tjänsten svarade inte i tid. Försök igen senare.');
    } on http.ClientException {
      throw const AiException('Ingen kontakt med tjänsten. Kontrollera internetanslutningen.');
    }

    if (res.statusCode != 200) throw AiException(_errorMessage(res));
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const AiException('Svaret från tjänsten kunde inte läsas.');
    }
    final block = (json['promptFeedback'] as Map?)?['blockReason'];
    if (block != null) throw AiException('Tjänsten avböjde att tolka bilden ($block).');
    final candidates = json['candidates'] as List?;
    final parts = candidates == null || candidates.isEmpty
        ? null
        : ((candidates.first as Map)['content'] as Map?)?['parts'] as List?;
    final text = parts?.map((p) => (p as Map)['text'] ?? '').join();
    if (text == null || text.trim().isEmpty) throw const AiException('Tjänsten gav inget svar.');
    try {
      return AiResult.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (_) {
      throw const AiException('Svaret hade fel format och användes inte.');
    }
  }

  String _errorMessage(http.Response res) {
    String detail = '';
    try {
      final e = (jsonDecode(res.body) as Map)['error'] as Map?;
      detail = '${e?['status'] ?? ''} ${e?['message'] ?? ''}';
    } catch (_) {}
    return switch (res.statusCode) {
      429 => 'Gratiskvoten är slut just nu. Försök igen senare (dagskvoten nollställs vid midnatt amerikansk tid).',
      400 when detail.contains('API_KEY') || detail.contains('API key') =>
        'API-nyckeln fungerar inte. Kontrollera den under Inställningar → Förbättrad analys.',
      401 || 403 => 'Åtkomst nekad. Kontrollera API-nyckeln under Inställningar → Förbättrad analys.',
      404 => 'Modellen "$model" finns inte. Byt modell under Inställningar → Förbättrad analys.',
      _ => 'Tjänsten svarade med fel ${res.statusCode}. ${detail.trim()}',
    };
  }

  void close() => _http.close();
}
