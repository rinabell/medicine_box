import 'package:flutter/material.dart';

import '../services/expiry_utils.dart';

/// 需求3：扫码后弹出的保质期录入框。
///
/// 返回 null 表示用户取消（点返回键），返回空列表表示「跳过」，
/// 返回非空列表表示录入的一个或多个规整后日期。
/// 支持一次输入多个：用逗号 / 分号 / 空格分隔。
Future<List<String>?> showExpiryDialog(
  BuildContext context, {
  List<String>? initial,
}) {
  final controller = TextEditingController(
    text: initial == null || initial.isEmpty ? '' : initial.join(', '),
  );
  String? error;

  return showDialog<List<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('记录保质期（可选）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入药盒上的有效期，例如 2027-05-20；'
              '多个日期用逗号隔开。也可以直接跳过。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('expiry_field'),
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '2027-05-20',
                border: const OutlineInputBorder(),
                errorText: error,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, const <String>[]),
            child: const Text('跳过'),
          ),
          ElevatedButton(
            onPressed: () {
              final raw = controller.text.trim();
              if (raw.isEmpty) {
                Navigator.pop(ctx, const <String>[]);
                return;
              }
              final dates = ExpiryUtils.parseMany(raw);
              if (dates.isEmpty) {
                setState(() => error = '日期格式不对，请按 年-月-日 填写，如 2027-05-20');
                return;
              }
              Navigator.pop(ctx, dates);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
}
