import 'package:flutter/material.dart';

import '../services/medicine_lookup.dart';

/// 设置页 / 二级配置页共用的「测试结果」卡片。
/// 成功显示查到的药名，失败显示原因 + 怎么办。
class TestResultCard extends StatelessWidget {
  final LookupOutcome outcome;
  final String target;

  const TestResultCard({
    super.key,
    required this.outcome,
    this.target = '',
  });

  @override
  Widget build(BuildContext context) {
    final ok = outcome.ok;
    final color = ok ? Colors.green.shade700 : Colors.orange.shade800;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ok ? Icons.check_circle : Icons.error_outline,
                  size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                ok ? '测试成功' : '测试未通过',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (target.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('测试对象：$target',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          const SizedBox(height: 6),
          Text(outcome.displayMessage, style: const TextStyle(fontSize: 13)),
          if (ok && outcome.result != null) ...[
            const SizedBox(height: 4),
            Text(
              '查到：${outcome.result!.name}'
              '${outcome.result!.category.isEmpty ? '' : '（${outcome.result!.category}）'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (outcome.result!.isNonMedicine)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '注意：这条被标记为非药品，仅用于验证数据源可用。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
