import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/medicine.dart';
import 'medicine_edit_page.dart';

/// 页面层：药品详情页
/// 件数 +/-、编辑、删除都在这里；数据按编码重新读取，保证返回首页后是最新的。
class MedicineDetailPage extends StatefulWidget {
  final String code;

  const MedicineDetailPage({super.key, required this.code});

  @override
  State<MedicineDetailPage> createState() => _MedicineDetailPageState();
}

class _MedicineDetailPageState extends State<MedicineDetailPage> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  Medicine? _medicine;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final m = await _db.findByCode(widget.code);
    if (!mounted) return;
    setState(() => _medicine = m);
  }

  Future<void> _changeCount(int delta) async {
    final m = _medicine;
    if (m == null) return;
    final next = m.count + delta < 0 ? 0 : m.count + delta;
    await _db.updateCount(m.code, next);
    await _reload();
  }

  Future<void> _edit() async {
    final m = _medicine;
    if (m == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MedicineEditPage(initial: m)),
    );
    await _reload();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这盒药？'),
        content: const Text('连同备注、说明书和件数一起删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _db.delete(widget.code);
    if (!mounted) return;
    Navigator.of(context).pop(true); // → 回首页并刷新列表
  }

  @override
  Widget build(BuildContext context) {
    final m = _medicine;
    return Scaffold(
      appBar: AppBar(
        title: Text(m?.name ?? '药品详情'),
        actions: [
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: '编辑',
        onPressed: _edit,
        child: const Icon(Icons.edit),
      ),
      body: m == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _countCard(m),
                _field('编码', m.code),
                _field('主要成分', m.ingredient),
                _field('说明书内容', m.leaflet),
                _field('备注', m.note),
                _field('资料来源', m.source == 'remote' ? '联网查询' : '手动填写'),
                _field('最近更新', _formatTime(m.updatedAt)),
                const SizedBox(height: 12),
                const Text(
                  '说明书与成分仅供家庭整理参考，用药请以药盒实物说明书和医嘱为准。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
    );
  }

  Widget _countCard(Medicine m) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('件数', style: TextStyle(fontSize: 16)),
              Row(
                children: [
                  IconButton(
                    onPressed: () => _changeCount(-1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(
                    '${m.count}',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w500),
                  ),
                  IconButton(
                    onPressed: () => _changeCount(1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _field(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            SelectableText(
              value.isEmpty ? '（未填写）' : value,
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
      );

  String _formatTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }
}
