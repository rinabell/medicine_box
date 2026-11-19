import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/medicine.dart';
import 'medicine_detail_page.dart';
import 'scan_page.dart';
import 'settings_page.dart';

/// 页面层：首页（药箱列表 + 搜索）
/// 搜索框输入即实时过滤；「模糊 / 精准」切换只换查询算法，不跳页。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final TextEditingController _kwController = TextEditingController();
  List<Medicine> _items = [];
  bool _exact = false; // false = 模糊，true = 精准
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _kwController.addListener(() => _refresh());
  }

  @override
  void dispose() {
    _kwController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final list = await _db.search(_kwController.text, exact: _exact);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _openScan() async {
    // 扫码页返回一句提示文字；老码计件 / 新码建档都在那边完成
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    await _refresh();
    if (message != null && message.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openDetail(Medicine m) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => MedicineDetailPage(code: m.code)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的药箱'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('扫码加药'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _kwController,
              decoration: InputDecoration(
                hintText: '搜药名 / 成分 / 说明书 / 备注',
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                ToggleButtons(
                  isSelected: [!_exact, _exact],
                  onPressed: (i) {
                    setState(() => _exact = i == 1);
                    _refresh();
                  },
                  borderRadius: BorderRadius.circular(8),
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('模糊'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('精准'),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _exact
                        ? '完全一致才显示；说明书按精确短语匹配'
                        : '包含关键词就显示，适合搜说明书内容',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(
                        child: Text('药箱里还没有药，点右下角「扫码加药」开始吧'),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final m = _items[i];
                          return Card(
                            child: ListTile(
                              title: Text(
                                m.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500),
                              ),
                              subtitle: Text(
                                [
                                  '编码：${m.code}',
                                  if (m.ingredient.isNotEmpty)
                                    '成分：${m.ingredient}',
                                  if (m.note.isNotEmpty) '备注：${m.note}',
                                ].join('  ·  '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Chip(label: Text('×${m.count}')),
                              onTap: () => _openDetail(m), // → 详情页
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
