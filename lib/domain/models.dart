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

/// The company's legal form. Reports differ, e.g. how equity is shown.
enum CompanyForm {
  enskildFirma('Enskild firma'),
  aktiebolag('Aktiebolag');

  final String label;
  const CompanyForm(this.label);

  static CompanyForm? parse(String? name) => values.where((f) => f.name == name).firstOrNull;
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

  /// True when the difference is worth a warning (1 kr or more).
  bool get hasDifference => difference.abs() >= Money.ignoredDifference;
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

  /// A receipt (kvitto) or an invoice stamped BETALD is paid; an invoice to
  /// pay is unpaid until the user marks it as paid.
  final bool paid;
  final String? paidDate;
  final String bankgiro;
  final String plusgiro;

  const Invoice({
    this.paid = false,
    this.paidDate,
    this.bankgiro = '',
    this.plusgiro = '',
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
  final bool paid;
  final String? dueDate;

  const RegistrationSummary({
    this.paid = false,
    this.dueDate,
    required this.kind,
    required this.id,
    required this.date,
    required this.amount,
    required this.vat,
    required this.title,
    required this.confirmed,
    required this.createdAt,
  });

  String get typeLabel => switch (kind) {
        'invoice' => paid && dueDate == null ? 'Kvitto' : 'Faktura',
        'online' => 'Onlineförsäljning',
        _ => 'Z-rapport',
      };
}

extension InvoiceCopy on Invoice {
  /// A copy with other payment details or a new scan link; everything else
  /// is kept as it is.
  Invoice copyWith({bool? paid, String? paidDate, bool clearPaidDate = false, RecordMeta? meta, int? id}) => Invoice(
        id: id ?? this.id,
        invoiceDate: invoiceDate,
        supplier: supplier,
        invoiceNumber: invoiceNumber,
        total: total,
        vatTotal: vatTotal,
        vatCalculated: vatCalculated,
        dueDate: dueDate,
        ocrReference: ocrReference,
        vatLines: vatLines,
        meta: meta ?? this.meta,
        paid: paid ?? this.paid,
        paidDate: clearPaidDate ? null : (paidDate ?? this.paidDate),
        bankgiro: bankgiro,
        plusgiro: plusgiro,
      );
}

/// A payout from a delivery partner (e.g. Foodora), after their commission.
/// It adds to the month's total sales but carries no VAT figure, since the
/// paid amount does not show the VAT on the underlying sales.
class OnlineSale {
  final int? id;
  final String paymentDate;
  final String partner;
  final String documentNumber;
  final Money amount;

  /// Output VAT included in [amount], when the partner's paper shows it
  /// (a självfaktura). Zero for a payout after commission.
  final Money vat;
  final VatRate? vatRate;
  final RecordMeta meta;

  const OnlineSale({
    this.id,
    required this.paymentDate,
    required this.partner,
    this.documentNumber = '',
    required this.amount,
    this.vat = Money.zero,
    this.vatRate,
    required this.meta,
  });
}
