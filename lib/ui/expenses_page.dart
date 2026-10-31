import 'package:flutter/material.dart';

import '../domain/dates.dart';
import 'record_details.dart';
import 'unpaid_page.dart';
import 'theme.dart';
import 'widgets/common.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  YearMonth _ym = YearMonth.now();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          MonthSwitcher(value: _ym, onChanged: (v) => setState(() => _ym = v)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Obetalda fakturor'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UnpaidPage())),
            ),
          ),
          Expanded(
            child: Reloading<MonthData>(
              deps: _ym.title,
              loader: (c) => MonthData.load(c, _ym),
              builder: (context, m) {
                if (m.invoices.isEmpty) {
                  return const EmptyState(
                      icon: Icons.receipt_long_outlined, text: 'Inga fakturor registrerade den här månaden.');
                }
                return ListView(
                  children: [
                    for (final inv in m.invoices.reversed)
                      ListTile(
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text([
                          if (inv.total.isNegative) 'Kreditnota',
                          if (inv.supplier.isNotEmpty) inv.supplier else if (!inv.total.isNegative) 'Faktura',
                        ].join(' · ')),
                        subtitle: Text([
                          SwedishDates.mediumDay(inv.invoiceDate),
                          if (inv.invoiceNumber.isNotEmpty) 'Nr ${inv.invoiceNumber}',
                          'Moms ${inv.vatTotal.format(compact: true)}',
                          if (!inv.paid) 'Obetald',
                        ].join(' · ')),
                        trailing: Text(inv.total.format(compact: true), style: moneyStyle),
                        onTap: () => openRecord(context, 'invoice', inv.id!),
                      ),
                    ListTile(
                      title: const Text('Totala utgifter'),
                      subtitle: Text('Ingående moms ${m.report.totalInputVat.format()}'),
                      trailing: Text(m.report.totalExpenses.format(),
                          style: moneyStyle.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
}
