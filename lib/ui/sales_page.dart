import 'package:flutter/material.dart';

import 'app_icons.dart';

import '../domain/dates.dart';
import 'record_details.dart';
import 'theme.dart';
import 'widgets/common.dart';

class SalesPage extends StatefulWidget {
  const SalesPage({super.key});

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
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
                if (m.sales.isEmpty) {
                  return const EmptyState(
                      icon: AppIcons.register, text: 'Inga Z-rapporter registrerade den här månaden.');
                }
                return ListView(
                  children: [
                    for (final d in m.sales.reversed)
                      ListTile(
                        leading: Icon(!d.hasDifference ? AppIcons.checkCircle : AppIcons.warning,
                            color: !d.hasDifference ? AppTheme.ok : AppTheme.warning),
                        title: Text(SwedishDates.mediumDay(d.businessDate)),
                        subtitle: Text([
                          'Z-rapport',
                          if ((d.zNumber ?? '').isNotEmpty) 'Z-nr ${d.zNumber}',
                          'Moms ${d.outputVat.format(compact: true)}',
                          if (d.hasDifference) 'Skillnad ${d.difference.format(compact: true)}',
                        ].join(' · ')),
                        trailing: Text(d.detailedTotal.format(compact: true), style: moneyStyle),
                        onTap: () => openRecord(context, 'z', d.id!),
                      ),
                    ListTile(
                      title: const Text('Total försäljning'),
                      trailing: Text(m.report.totalSales.format(), style: moneyStyle.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      );
}
