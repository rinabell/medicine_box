import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/medicine.dart';
import '../services/lookup_service.dart';
import '../services/medicine_lookup.dart';

/// 页面层：新建 / 编辑共用一页
/// - 新建：传 code（+ 可选的联网预填 suggestion、失败原因 lookupMessage）
/// - 编辑：传 initial
/// 所有字段都可改；联网查到的内容只是预填，不是最终结论。
///
/// 【V1.3】「按药名查说明书」不再绑定某一家接口：由 LookupService 按
/// 设置页选中的数据源路由（showapi 1468 / 本地药品库 / 自定义接口）。
/// 条码查不到时手填药名即可自动补全成分和说明书全文，满足需求④。
class MedicineEditPage extends StatefulWidget {
  final String? code;
  final Medicine? initial;
  final LookupResult? suggestion;

  /// 联网查询失败的原因；不为空时在顶部显示提示条。
  final String? lookupMessage;

  /// 需求3：扫码后弹窗录入的保质期，带入建档页一并保存。
  final List<String> initialExpiryDates;

  const MedicineEditPage({
    super.key,
    this.code,
    this.initial,
    this.suggestion,
    this.lookupMessage,
    this.initialExpiryDates = const [],
  });

  @override
  State<MedicineEditPage> createState() => _MedicineEditPageState();
}

class _MedicineEditPageState extends State<MedicineEditPage> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _db = DatabaseHelper.instance;

  late final TextEditingController _name;
  late final TextEditingController _ingredient;
  late final TextEditingController _leaflet;
  late final TextEditingController _note;
  late final TextEditingController _count;
  late String _source;
  late String _code;
  late String _category;
  late List<String> _expiryDates;
  String? _lookupMessage;
  bool _looking = false;
  bool _lookingByName = false;

  @override
  void initState() {
    super.initState();
    final m = widget.initial;
    final s = widget.suggestion;
    _code = m?.code ?? widget.code ?? '';
    _name = TextEditingController(text: m?.name ?? s?.name ?? '');
    _ingredient =
        TextEditingController(text: m?.ingredient ?? s?.ingredient ?? '');
    _leaflet = TextEditingController(text: m?.leaflet ?? s?.leaflet ?? '');
    _note = TextEditingController(text: m?.note ?? '');
    _count = TextEditingController(text: '${m?.count ?? 1}');
    _source = m?.source ?? (s != null ? 'remote' : 'manual');
    _category = s?.category ?? '';
    // 编辑已有药时保留原保质期；新建时用扫码弹窗带入的日期
    _expiryDates = m?.expiryDates ?? widget.initialExpiryDates;
    _lookupMessage = widget.lookupMessage;
  }

  @override
  void dispose() {
    _name.dispose();
    _ingredient.dispose();
    _leaflet.dispose();
    _note.dispose();
    _count.dispose();
    super.dispose();
  }

  void _apply(LookupResult r) {
    setState(() {
      // 只补空字段，不覆盖用户已经手写的内容
      if (_name.text.trim().isEmpty) _name.text = r.name;
      if (_ingredient.text.trim().isEmpty) _ingredient.text = r.ingredient;
      if (_leaflet.text.trim().isEmpty) _leaflet.text = r.leaflet;
      _source = 'remote';
      _category = r.category;
      _lookupMessage = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('已补全说明书：${r.name}')));
  }

  /// 用户填好 Key 之后，或者网络恢复后，可以在这里再查一次（按条码）。
  Future<void> _retryLookup() async {
    if (_looking || _code.isEmpty) return;
    setState(() => _looking = true);
    final outcome = await LookupService.tryLookup(_code);
    if (!mounted) return;
    setState(() => _looking = false);

    if (!outcome.ok) {
      setState(() => _lookupMessage = outcome.displayMessage);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('没查到：${outcome.message}')));
      return;
    }
    _apply(outcome.result!);
  }

  /// 【兜底】按药名查当前数据源的药品库，补全成分 + 说明书。
  /// 条码接口没订购、扫到 20 位追溯码、或数据源未收录时走这条路。
  Future<void> _lookupByName() async {
    final keyword = _name.text.trim();
    if (keyword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先填写药名，再点这个按钮')));
      return;
    }
    if (_lookingByName) return;
    setState(() => _lookingByName = true);
    final outcome = await LookupService.lookupByDrugName(keyword);
    if (!mounted) return;
    setState(() => _lookingByName = false);

    if (!outcome.ok) {
      setState(() => _lookupMessage = outcome.displayMessage);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('没查到：${outcome.message}')));
      return;
    }
    // 不覆盖药名：用户就是拿这个名字去查的
    final r = outcome.result!;
    setState(() {
      if (_ingredient.text.trim().isEmpty) _ingredient.text = r.ingredient;
      if (_leaflet.text.trim().isEmpty) _leaflet.text = r.leaflet;
      _source = 'remote';
      _category = r.category;
      _lookupMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已补全说明书：${r.name}')));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final parsed = int.tryParse(_count.text.trim()) ?? 1;
    final medicine = Medicine(
      code: _code,
      name: _name.text.trim(),
      ingredient: _ingredient.text.trim(),
      leaflet: _leaflet.text.trim(),
      note: _note.text.trim(), // 需求③：用户自定义文字，也参与搜索
      count: parsed < 0 ? 0 : parsed,
      source: _source,
      expiryDates: _expiryDates,
      createdAt: widget.initial?.createdAt ?? now,
      updatedAt: now,
    );
    if (widget.initial != null) {
      await _db.update(medicine);
    } else {
      await _db.insert(medicine);
    }
    if (!mounted) return;
    Navigator.of(context).pop(medicine); // → 返回扫码页 / 详情页
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    final tip = _lookupMessage;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? '编辑药品' : '第一次见到这盒药')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('编码：$_code', style: Theme.of(context).textTheme.bodySmall),
            if (tip != null && tip.isNotEmpty) ...[
              const SizedBox(height: 10),
              _NoticeBanner(
                text: '没能自动查到说明书：$tip',
                actionLabel: _looking ? '查询中…' : '重新查询',
                onAction: _looking ? null : _retryLookup,
              ),
            ] else if (_code.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _looking ? null : _retryLookup,
                  icon: _looking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_looking ? '查询中…' : '重新查询'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '药名 *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请填药名' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _lookingByName ? null : _lookupByName,
                icon: _lookingByName
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.medication_outlined, size: 18),
                label: Text(
                  _lookingByName
                      ? '正在查药品库…'
                      : '按药名查说明书（免费药品库 / 本地库）',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextFormField(
              controller: _ingredient,
              decoration: const InputDecoration(
                labelText: '主要成分',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _leaflet,
              decoration: const InputDecoration(
                labelText: '说明书内容（可粘贴全文）',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 6,
            ),
            const SizedBox(height: 4),
            Text(
              _source == 'remote'
                  ? '来源：自动查询（仅供参考，请核对实物说明书）'
                  : '来源：手动填写',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_category.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '接口分类：$_category'
                '${_category.contains('非药品') ? '（注意：这可能不是药品，请核对实物）' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: _category.contains('非药品')
                      ? Colors.orange.shade800
                      : Colors.grey,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: '备注（随便写，也会被搜索）',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _count,
              decoration: const InputDecoration(
                labelText: '件数',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  int.tryParse(v?.trim() ?? '') == null ? '请填数字' : null,
            ),
            if (_expiryDates.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '保质期',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  for (final date in _expiryDates)
                    Chip(
                      key: Key('expiry_chip_$date'),
                      label: Text(date),
                      avatar: const Icon(Icons.event_outlined, size: 16),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('保存到药箱'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final String text;
  final String actionLabel;
  final VoidCallback? onAction;

  const _NoticeBanner({
    required this.text,
    required this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(fontSize: 12, color: color)),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: Text(actionLabel, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
