import 'dart:convert';

import 'package:bokforing/ai/ai_result.dart';
import 'package:bokforing/ai/gemini_client.dart';
import 'package:bokforing/domain/classifier.dart';
import 'package:bokforing/domain/models.dart';
import 'package:bokforing/domain/money.dart';
import 'package:bokforing/domain/text_patterns.dart';
import 'package:bokforing/domain/vat.dart';
import 'package:bokforing/domain/z_report_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _cats = [
  Category(id: 1, name: 'Mat', vat: VatRate.six),
  Category(id: 2, name: 'Öl', vat: VatRate.twentyFive),
];

void main() {
  group('AI suggestions go through deterministic parsing', () {
    test('invoice amounts are parsed from printed text, never trusted as numbers', () {
      final r = AiResult.fromJson({
        'document_type': 'faktura',
        'date': '2026-10-15',
        'supplier': 'Centrumgrossisten AB',
        'total_text': '521,00',
        'vat_lines': [
          {'rate_percent': '6', 'vat_text': '29,47', 'net_text': '491,87'},
          {'rate_percent': '25%', 'vat_text': '0,00'},
        ],
      });
      final d = r.toInvoiceDraft();
      expect(r.type, DocumentType.invoice);
      expect(d.total.value, Money.kr(521));
      expect(d.total.confidence, Confidence.medium);
      expect(d.vatLines.single.rate, VatRate.six);
      expect(d.vatTotal.value, const Money(2947));
      expect(d.net, const Money(49187));
      expect(d.notes.first, AiResult.aiNote);
    });

    test('unparseable amounts are left empty, with a note', () {
      final d = AiResult.fromJson({'document_type': 'faktura', 'total_text': 'ca 500', 'date': '15/10'}).toInvoiceDraft();
      expect(d.total.value, isNull);
      expect(d.date.value, isNull);
      expect(d.notes.length, 2);
    });

    test('Z rows use the cautious category matching', () {
      final r = AiResult.fromJson({
        'document_type': 'z_rapport',
        'date': '2026-10-31',
        'total_text': '3 419,00',
        'z_rows': [
          {'label': 'Mat', 'amount_text': '1 912,00'},
          {'label': 'Mat avhämtning', 'amount_text': '1 507,00'},
        ],
      });
      final d = r.toZReportDraft(_cats, const {});
      expect(d.total.value, Money.kr(3419));
      expect(d.lines.length, 2);
      expect(d.lines[0].categoryId, 1);
      expect(d.lines[1].categoryId, isNull);
      expect(d.lines[1].match, MatchKind.possible);
      expect(d.date.value, '2026-10-31');
    });
  });

  group('GeminiClient', () {
    test('sends the image with the key header and reads JSON text', () async {
      late http.Request sent;
      final client = GeminiClient(
        apiKey: 'test-key',
        model: 'gemini-3.8-flash',
        client: MockClient((req) async {
          sent = req;
          final text = jsonEncode({'document_type': 'faktura', 'total_text': '125,00'});
          return http.Response(
              jsonEncode({
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': text}
                      ]
                    }
                  }
                ]
              }),
              200);
        }),
      );
      final r = await client.analyze([utf8.encode('jpeg')]);
      expect(r.totalText, '125,00');
      expect(sent.headers['x-goog-api-key'], 'test-key');
      expect(sent.url.path, '/v1beta/models/gemini-3.8-flash:generateContent');
      final body = jsonDecode(sent.body) as Map;
      final parts = (body['contents'] as List).first['parts'] as List;
      expect(parts.last['inline_data']['mime_type'], 'image/jpeg');
    });

    test('quota errors give a clear Swedish message', () async {
      final client = GeminiClient(
          apiKey: 'k', model: 'm', client: MockClient((_) async => http.Response('{"error":{}}', 429)));
      expect(
          () => client.analyze([utf8.encode('x')]),
          throwsA(isA<AiException>().having((e) => e.message, 'message', contains('Gratiskvoten'))));
    });
  });
}
