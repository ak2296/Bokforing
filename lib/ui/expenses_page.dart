import 'package:flutter/material.dart';

import '../domain/dates.dart';
import 'record_details.dart';
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
                        title: Text(inv.supplier.isEmpty ? 'Faktura' : inv.supplier),
                        subtitle: Text([
                          SwedishDates.mediumDay(inv.invoiceDate),
                          if (inv.invoiceNumber.isNotEmpty) 'Nr ${inv.invoiceNumber}',
                          'Moms ${inv.vatTotal.format(compact: true)}',
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
