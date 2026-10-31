import 'money.dart';
import 'vat.dart';

enum RecordSource { ocr, manual, ai }

extension RecordSourceText on RecordSource {
  String get label => switch (this) {
        RecordSource.ocr => 'Skannad',
        RecordSource.manual => 'Manuell',
        RecordSource.ai => 'Skannad (förbättrad analys)',
      };
}

/// Traceability data kept on every accounting record.
class RecordMeta {
  final RecordSource source;
  final bool manuallyEdited;
  final bool confirmed;
  final int? scanId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RecordMeta({
    required this.source,
    this.manuallyEdited = false,
    this.confirmed = false,
    this.scanId,
    this.createdAt,
    this.updatedAt,
  });

  bool get fromOcr => source != RecordSource.manual;

  RecordMeta copyWith({bool? manuallyEdited, bool? confirmed, int? scanId}) => RecordMeta(
        source: source,
        manuallyEdited: manuallyEdited ?? this.manuallyEdited,
        confirmed: confirmed ?? this.confirmed,
        scanId: scanId ?? this.scanId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

class BusinessProfile {
  final String name;
  final String orgNumber;
  final String address;
  const BusinessProfile({this.name = '', this.orgNumber = '', this.address = ''});

  BusinessProfile copyWith({String? name, String? orgNumber, String? address}) =>
      BusinessProfile(
        name: name ?? this.name,
        orgNumber: orgNumber ?? this.orgNumber,
        address: address ?? this.address,
      );
}

/// A user-defined sales category from the Z-report, e.g. "Mat" at 6 %.
class Category {
  final int? id;
  final String name;
  final VatRate vat;
  final int sortOrder;
  final bool active;

  const Category({
    this.id,
    required this.name,
    required this.vat,
    this.sortOrder = 0,
    this.active = true,
  });

  Category copyWith({String? name, VatRate? vat, int? sortOrder, bool? active}) => Category(
        id: id,
        name: name ?? this.name,
        vat: vat ?? this.vat,
        sortOrder: sortOrder ?? this.sortOrder,
        active: active ?? this.active,
      );
}

/// One category amount on a day. Name and VAT rate are snapshots taken when
/// the day was saved, so later category edits never change old records.
class SalesItem {
  final int? categoryId;
  final String categoryName;
  final VatRate vat;
  final Money amount;
  final String? sourceLabel;

  const SalesItem({
    this.categoryId,
    required this.categoryName,
    required this.vat,
    required this.amount,
    this.sourceLabel,
  });

  Money get vatAmount => VatCalculator.vatFromGross(amount, vat);
  Money get netAmount => amount - vatAmount;
}

class DailySales {
  final int? id;
  final String businessDate;
  final String? zNumber;
  final Money reportedTotal;
  final List<SalesItem> items;
  final String note;
  final RecordMeta meta;

  const DailySales({
    this.id,
    required this.businessDate,
    this.zNumber,
    required this.reportedTotal,
    required this.items,
    this.note = '',
    required this.meta,
  });

  Money get detailedTotal => Money.sum(items.map((i) => i.amount));
  Money get outputVat => Money.sum(items.map((i) => i.vatAmount));
  Money get difference => detailedTotal - reportedTotal;
}

class InvoiceVatLine {
  final VatRate rate;
  final Money vat;
  final Money? net;
  final Money? gross;

  /// True when the VAT was calculated by the app rather than printed.
  final bool calculated;

  const InvoiceVatLine({
    required this.rate,
    required this.vat,
    this.net,
    this.gross,
    this.calculated = false,
  });
}

class Invoice {
  final int? id;
  final String invoiceDate;
  final String supplier;
  final String invoiceNumber;
  final Money total;
  final Money vatTotal;
  final bool vatCalculated;
  final String? dueDate;
  final String ocrReference;
  final List<InvoiceVatLine> vatLines;
  final RecordMeta meta;

  const Invoice({
    this.id,
    required this.invoiceDate,
    this.supplier = '',
    this.invoiceNumber = '',
    required this.total,
    required this.vatTotal,
    this.vatCalculated = false,
    this.dueDate,
    this.ocrReference = '',
    this.vatLines = const [],
    required this.meta,
  });
}

/// A row in the history and "Senaste registreringar" lists.
class RegistrationSummary {
  final String kind; // 'invoice' or 'z'
  final int id;
  final String date;
  final Money amount;
  final Money vat;
  final String title;
  final bool confirmed;
  final DateTime createdAt;

  const RegistrationSummary({
    required this.kind,
    required this.id,
    required this.date,
    required this.amount,
    required this.vat,
    required this.title,
    required this.confirmed,
    required this.createdAt,
  });

  String get typeLabel => kind == 'invoice' ? 'Faktura' : 'Z-rapport';
}
