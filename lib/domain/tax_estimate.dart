import 'models.dart';
import 'money.dart';

enum TaxMode { percent, amount }

/// A rough estimate of the tax to set aside, shown under Resultat. Never a
/// tax return: aktiebolag pay 20,6 % on the year's profit; an enskild firma
/// pays personally, so the owner chooses a percentage or a fixed amount.
class TaxEstimate {
  /// Bolagsskatt 20,6 %, in tenths of a percent.
  static const abTenths = 206;

  final CompanyForm? form;
  final TaxMode mode;

  /// Enskild firma, percent mode: tenths of a percent (30 % is 300).
  final int percentTenths;

  /// Enskild firma, amount mode: the year's preliminary tax (preliminär skatt).
  final Money yearlyAmount;
  const TaxEstimate({this.form, this.mode = TaxMode.percent, this.percentTenths = 300, this.yearlyAmount = Money.zero});

  bool get _ab => form == CompanyForm.aktiebolag;

  /// Nothing is shown before the company form is chosen, or when the owner
  /// has set nothing.
  bool get active => form != null && (_ab || (mode == TaxMode.percent ? percentTenths > 0 : !yearlyAmount.isZero));

  /// The tax to set aside for [resultBeforeTax]; null when nothing is shown.
  /// A loss gives 0. A yearly amount is spread evenly: [months] of 12 months
  /// (a month is 1, a whole year 12), and never more than the profit.
  Money? tax(Money resultBeforeTax, {int months = 1}) {
    if (!active) return null;
    if (resultBeforeTax.ore <= 0) return Money.zero;
    if (_ab) return _percent(resultBeforeTax, abTenths);
    if (mode == TaxMode.percent) return _percent(resultBeforeTax, percentTenths);
    final fixed = Money((yearlyAmount.ore * months + 6) ~/ 12);
    return fixed > resultBeforeTax ? resultBeforeTax : fixed;
  }

  static Money _percent(Money m, int tenths) => Money((m.ore * tenths + 500) ~/ 1000);

  static String _tenths(int t) => '${t ~/ 10}${t % 10 == 0 ? '' : ',${t % 10}'}';

  String get label => _ab
      ? 'Beräknad skatt, ${_tenths(abTenths)} %'
      : mode == TaxMode.percent
          ? 'Att lägga undan, ${_tenths(percentTenths)} %'
          : 'Att lägga undan (preliminär skatt)';

  String get note => _ab
      ? 'Skatten är en uppskattning att lägga undan. Den räknas egentligen på hela årets resultat.'
      : 'Din egen uppskattning (Inställningar → Företag). Inte en skatteberäkning.';
}
