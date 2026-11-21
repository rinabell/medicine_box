import 'package:flutter/material.dart';

import '../services/data_source.dart';
import '../services/font_scale.dart';
import '../services/local_catalog.dart';
import 'api_source_config_page.dart';

/// 设置页（首页右上角齿轮进入）：**只做四选一**。
///
/// 【V1.3】用户反馈选项1（showapi 条码接口）是收费的，于是把资料来源
/// 拆成三个可切换的数据源；选项1、选项2 各自的 AppKey 输入和测试按钮
/// 收进二级配置页（ApiSourceConfigPage），主页保持一眼能看懂。
///
/// 默认「选项3 本地药品条码库」：装好 App 不用注册、不用填 Key、不用联网
/// 就能扫码查出药名与说明书。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  DataSource _selected = DataSourceSettings.defaultSource;
  int _fontLevel = FontScaleSettings.defaultLevel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.wait([
      DataSourceSettings.current(),
      FontScaleSettings.current(),
    ]).then((values) {
      if (mounted) {
        setState(() {
          _selected = values[0] as DataSource;
          _fontLevel = values[1] as int;
          _loading = false;
        });
      }
    });
  }

  Future<void> _chooseFont(int level) async {
    await FontScaleSettings.save(level);
    if (!mounted) return;
    setState(() => _fontLevel = level);
  }

  Future<void> _choose(DataSource? value) async {
    if (value == null) return;
    await DataSourceSettings.save(value);
    if (!mounted) return;
    setState(() => _selected = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换：${DataSourceSettings.titleOf(value)}')),
    );
  }

  Future<void> _openConfig(DataSource source) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ApiSourceConfigPage(source: source)),
    );
    if (!mounted) return;
    // 二级页可能改过配置，回来重新读一次选中项
    final current = await DataSourceSettings.current();
    if (mounted) setState(() => _selected = current);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置 · 药品资料来源')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '字体大小',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '默认 3 档（比原来大一号）；觉得太大或太小可随时切换，立即生效。',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          key: const Key('font_level_group'),
                          children: [
                            for (final level in FontScaleSettings.levels) ...[
                              Expanded(
                                child: GestureDetector(
                                  key: Key('font_level_$level'),
                                  onTap: () => _chooseFont(level),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    decoration: BoxDecoration(
                                      color: _fontLevel == level
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      FontScaleSettings.labelOf(level).split(' · ').first,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _fontLevel == level
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (level != FontScaleSettings.levels.last)
                                const SizedBox(width: 6),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '当前：${FontScaleSettings.labelOf(_fontLevel)}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '扫到新药时，用哪套资料自动补全药名和说明书？',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  '随时可切换，只存在本机。四种方式都查不到时会自动退回手动填写一次，'
                  '不影响扫码计件、备注和搜索。',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                for (final source in DataSource.values) ...[
                  _SourceCard(
                    source: source,
                    selected: _selected == source,
                    onChoose: () => _choose(source),
                    onConfig: () => _openConfig(source),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 8),
                const Text(
                  '关于收费与反爬',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  '选项1 的条码直查（66-24）是收费接口，必须先购买资源包；'
                  '它附带的按药名查询（1468）是免费的。\n'
                  '选项2 参照的 68api 网页现在有滑块验证，App 内直接抓取常被挡，'
                  '但可以在二级页改成自己的 JSON 接口。\n'
                  '选项3 的数据随 App 一起打包，完全离线，'
                  '收录约 4.7 万条药品条码，不是全部药品。\n'
                  '选项4 的极速数据免费 100 次/天，按条码直查且带说明书；'
                  '注册 14 天后需实名认证，查过的码会缓存不重复扣次数。',
                  style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                const Text(
                  '说明书来自第三方开源 / 接口数据，仅供家庭整理参考，'
                  '用药请以药盒实物说明书和医嘱为准。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Text(
                  '当前：${DataSourceSettings.titleOf(_selected)}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final DataSource source;
  final bool selected;
  final VoidCallback onChoose;
  final VoidCallback onConfig;

  const _SourceCard({
    required this.source,
    required this.selected,
    required this.onChoose,
    required this.onConfig,
  });

  @override
  Widget build(BuildContext context) {
    final isLocal = source == DataSource.local;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          width: selected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Radio<DataSource>(
                  value: source,
                  groupValue: selected ? source : null,
                  onChanged: (_) => onChoose(),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: onChoose,
                    child: Text(
                      DataSourceSettings.titleOf(source),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isLocal
                        ? Colors.green.withValues(alpha: 0.12)
                        : Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    DataSourceSettings.tagOf(source),
                    style: TextStyle(
                      fontSize: 11,
                      color: isLocal
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Text(
                DataSourceSettings.descriptionOf(source),
                style: const TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: Key('config_${DataSourceSettings.idOf(source)}'),
                  onPressed: onConfig,
                  icon: Icon(isLocal ? Icons.storage : Icons.key, size: 16),
                  label: Text(
                    isLocal
                        ? '查看本地库 / 测试'
                        : '填写 AppKey 与测试',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
            if (isLocal)
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 6),
                child: Text(
                  '内置 ${LocalCatalog.recordCountLabel} 条 · 无需联网 · 无需 Key',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
