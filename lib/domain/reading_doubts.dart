import 'invoice_parser.dart';
import 'money.dart';
import 'online_parser.dart';
import 'payslip_parser.dart';
import 'text_patterns.dart';

/// How doubtful a reading is: the number of key fields that are missing or
/// read with low confidence. Zero is a clean reading. A slower second reading
/// of the photo is only done when the first one has doubts, and the reading
/// with fewer doubts is kept. (For Z-reports see `ZReportParser.doubtsOf`.)
bool _weak(Extracted<Object?> e) => !e.hasValue || e.confidence == Confidence.low;

/// Date, supplier and total, and whether net plus moms equals the total.
int invoiceDoubts(InvoiceDraft d) {
  var n = [d.date, d.supplier, d.total].where(_weak).length;
  final net = d.net;
  final total = d.total.value;
  final vat = d.vatTotal.value;
  if (net != null && total != null && vat != null && (net + vat - total).abs() >= Money.ignoredDifference) n++;
  return n;
}

/// Payment date, partner and amount.
int onlineDoubts(OnlineDraft d) => [d.date, d.partner, d.amount].where(_weak).length;

/// Payout date, employee and the three amounts.
int payslipDoubts(PayslipDraft d) => [d.payoutDate, d.employeeName, d.gross, d.employerFee, d.tax].where(_weak).length;
