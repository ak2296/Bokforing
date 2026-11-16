import '../data/activation_cloud.dart';
import '../data/repository.dart';
import '../domain/company_pair.dart';
import '../domain/dates.dart';

/// The activation order: sent from the company in Företag, with the one-week
/// trial, and the code that comes back activates the app by itself.
class ActivationService {
  final Repository repo;
  final ActivationCloud cloud;
  ActivationService(this.repo, this.cloud);

  static String? companyProblem(String name, String org) => name.trim().isEmpty || !CompanyPair.orgValid(org)
      ? 'Fyll i företagsnamn och ett giltigt organisationsnummer under Inställningar → Företag.'
      : null;

  /// Sends the order for the company in Företag. Null when sent, else why not.
  Future<String?> placeOrder() async {
    final p = await repo.profile();
    final problem = companyProblem(p.name, p.orgNumber);
    if (problem != null) return problem;
    try {
      final r = await cloud.order(p.name, p.orgNumber);
      await repo.saveOrder(r.id, p.name, p.orgNumber);
      final start = r.trialStart;
      if (start != null) {
        await repo.startTrial(SwedishDates.iso(start.add(const Duration(days: ActivationCloud.trialDays))), p.name, p.orgNumber);
      }
      return null;
    } on CloudException catch (e) {
      return e.message;
    }
  }

  /// Asks the server about the order. When the owner has sent the code it is
  /// activated and the order is closed. [status] is '' when nothing is known.
  Future<({bool activated, String status})> collect() async {
    final o = await repo.order();
    if (o == null) return (activated: false, status: '');
    try {
      final a = await cloud.answer(o.id);
      if (a == null) return (activated: false, status: '');
      if (a.status == 'skickad' && a.code.isNotEmpty && await repo.activateLicense(a.code) == null) {
        await repo.saveOrder('', '', '');
        return (activated: true, status: a.status);
      }
      return (activated: false, status: a.status);
    } on CloudException {
      return (activated: false, status: '');
    }
  }
}
