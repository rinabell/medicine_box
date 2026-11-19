import 'package:flutter/material.dart';

import '../services/data_source.dart';
import '../services/local_catalog.dart';
import '../services/lookup_service.dart';
import '../services/medicine_lookup.dart';
import '../widgets/test_result_card.dart';

/// 二级配置页：选项1 / 选项2 在这里填 AppKey（和接口地址）并测试；
/// 选项3 在这里查看本地库状态、试查、重建。
///
/// 用户要求「选项1和2在弹窗或者二级页面里再填 api key 和测试按钮」，
/// 这样设置主页保持干净，只有四选一。
class ApiSourceConfigPage extends StatefulWidget {
  final DataSource source;

  /// 测试注入：传了就走它，不发真实网络请求。
  /// action 取值：'primary' | 'barcode' | 'local'。
  final Future<LookupOutcome> Function(String action)? onTest;

  const ApiSourceConfigPage({
    super.key,
    required this.source,
    this.onTest,
  });

  @override
  State<ApiSourceConfigPage> createState() => _ApiSourceConfigPageState();
}

class _ApiSourceConfigPageState extends State<ApiSourceConfigPage> {
  final TextEditingController _key = TextEditingController();
  final TextEditingController _endpoint = TextEditingController();

  bool _loading = true;
  bool _testing = false;
  bool _rebuilding = false;
  LookupOutcome? _outcome;
  String _testTarget = '';
  String? _localStatus;

  DataSource get source => widget.source;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (source == DataSource.showapi) {
      _key.text = await LookupService.readKey();
    } else if (source == DataSource.web) {
      _key.text = await LookupService.readWebKey();
      _endpoint.text = await LookupService.readWebEndpoint();
    } else if (source == DataSource.jisu) {
      _key.text = await LookupService.readJisuKey();
    } else {
      try {
        final installed = await LocalCatalog.isInstalled();
        _localStatus = installed
            ? '本地库已就绪（${LocalCatalog.knownRecordCount} 条）'
            : '首次使用会初始化本地库（约 83MB，只做一次，之后秒查）';
      } catch (e) {
        // 桌面单测 / 某些设备上取不到数据库目录，不影响查看说明。
        _localStatus = '首次扫码时会自动解压本地库（当前无法读取状态：$e）';
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _key.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (source == DataSource.showapi) {
      await LookupService.saveKey(_key.text);
    } else if (source == DataSource.web) {
      await LookupService.saveWebKey(_key.text);
      await LookupService.saveWebEndpoint(_endpoint.text);
    } else if (source == DataSource.jisu) {
      await LookupService.saveJisuKey(_key.text);
    } else {
      // 本地库不在这里强制解压：首次扫码查询时 LocalCatalog 会自动 install，
      // 避免设置页为了一个还没用到的库白等几秒。
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
    Navigator.of(context).pop(true);
  }

  Future<void> _runTest(String action, String target) async {
    if (_testing) return;
    setState(() {
      _testing = true;
      _outcome = null;
      _testTarget = target;
    });

    // 测试前先把当前输入存下来，保证「测的就是刚填的 Key」
    if (source == DataSource.showapi) {
      await LookupService.saveKey(_key.text);
    } else if (source == DataSource.web) {
      await LookupService.saveWebKey(_key.text);
      await LookupService.saveWebEndpoint(_endpoint.text);
    } else if (source == DataSource.jisu) {
      await LookupService.saveJisuKey(_key.text);
    }

    late final LookupOutcome outcome;
    final override = widget.onTest;
    if (override != null) {
      outcome = await override(action);
    } else {
      switch (action) {
        case 'primary':
          outcome = await LookupService.testSource(source);
        case 'barcode':
          outcome = await LookupService.testBarcodeLookup();
        case 'local':
          outcome = await LookupService.testLocalLookup();
        case 'supplement':
          outcome = await LocalCatalog.lookup(LocalCatalog.supplementDemoCode);
        case 'jisu_barcode':
          outcome = await LookupService.testJisuBarcodeLookup();
        default:
          outcome = const LookupOutcome(
            LookupStatus.unknown,
            message: '未知的测试动作',
          );
      }
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _outcome = outcome;
    });
  }

  Future<void> _rebuild() async {
    if (_rebuilding) return;
    setState(() => _rebuilding = true);
    try {
      await LocalCatalog.install(force: true);
      final count = await LocalCatalog.count();
      if (!mounted) return;
      setState(() => _localStatus = '本地库已重建：$count 条记录');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重建完成，共 $count 条')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _localStatus = '重建失败：$e');
    } finally {
      if (mounted) setState(() => _rebuilding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(DataSourceSettings.titleOf(source))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(DataSourceSettings.descriptionOf(source),
                    style: const TextStyle(fontSize: 13, height: 1.5)),
                const SizedBox(height: 16),
                ..._fields(),
                const SizedBox(height: 12),
                ..._testButtons(),
                if (_testing)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (_outcome != null) ...[
                  const SizedBox(height: 12),
                  TestResultCard(
                    outcome: _outcome!,
                    target: _testTarget,
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: Text(source == DataSource.local
                        ? '设为当前数据源并返回'
                        : '保存并返回'),
                  ),
                ),
                const SizedBox(height: 20),
                ..._notes(),
              ],
            ),
    );
  }

  List<Widget> _fields() {
    switch (source) {
      case DataSource.showapi:
        return [
          TextField(
            key: const Key('showapi_key_field'),
            controller: _key,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'AppKey（可留空）',
              hintText: '粘贴 showapi 控制台里的 AppKey',
              border: OutlineInputBorder(),
              helperText: '是「AppKey」，不是 AppId / SecretKey / AppCode',
            ),
          ),
        ];
      case DataSource.web:
        return [
          TextField(
            key: const Key('web_endpoint_field'),
            controller: _endpoint,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '接口地址',
              hintText: 'https://68api.com/barcode/{code}.html',
              border: OutlineInputBorder(),
              helperText: '{code} 会被替换成条码，{key} 会被替换成 AppKey',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('web_key_field'),
            controller: _key,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'AppKey / Token（可留空）',
              hintText: '68api 网页查询本身不需要 Key',
              border: OutlineInputBorder(),
              helperText: '留空即免鉴权；填了会自动附加 appKey 参数',
            ),
          ),
        ];
      case DataSource.jisu:
        return [
          TextField(
            key: const Key('jisu_key_field'),
            controller: _key,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'AppKey（极速数据）',
              hintText: '粘贴 jisuapi 个人中心里的 AppKey',
              border: OutlineInputBorder(),
              helperText: '免费会员 100 次/天；注册 14 天后需完成实名认证',
            ),
          ),
        ];
      case DataSource.local:
        return [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('本地药品条码库',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(_localStatus ?? '',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  const Text(
                    '约 ${LocalCatalog.recordCountLabel} 条 · 含药名 / 成分 / 说明书 · '
                    '数据来自 Gitee 开源项目 barcode',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _rebuilding ? null : _rebuild,
            icon: _rebuilding
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: Text(_rebuilding ? '正在重建…' : '重建本地库'),
          ),
        ];
    }
  }

  List<Widget> _testButtons() {
    switch (source) {
      case DataSource.showapi:
        return [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('test_primary_button'),
                  onPressed: _testing
                      ? null
                      : () => _runTest('primary', '1468 药品信息查询（免费）'),
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _testing
                      ? null
                      : () => _runTest('barcode', '66-24 药品条码查询（需订购）'),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('测试条码接口'),
                ),
              ),
            ],
          ),
        ];
      case DataSource.web:
        return [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('test_primary_button'),
              onPressed: _testing
                  ? null
                  : () => _runTest('primary', '自定义网页 / 接口'),
              icon: const Icon(Icons.wifi_tethering, size: 18),
              label: const Text('测试查询'),
            ),
          ),
        ];
      case DataSource.jisu:
        return [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('test_primary_button'),
                  onPressed: _testing
                      ? null
                      : () => _runTest('primary', '极速数据连接（按药名，免费）'),
                  icon: const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('jisu_barcode_button'),
                  onPressed: _testing
                      ? null
                      : () => _runTest('jisu_barcode', '极速数据条码直查'),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('测试条码'),
                ),
              ),
            ],
          ),
        ];
      case DataSource.local:
        return [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('test_primary_button'),
                  onPressed: _testing
                      ? null
                      : () => _runTest('local', '本地药品条码库'),
                  icon: const Icon(Icons.storage, size: 18),
                  label: const Text('测试本地库'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('test_supplement_button'),
                  onPressed: _testing
                      ? null
                      : () => _runTest('supplement', '补充条目（蒙脱石散）'),
                  icon: const Icon(Icons.healing, size: 18),
                  label: const Text('测试补充条目'),
                ),
              ),
            ],
          ),
        ];
    }
  }

  List<Widget> _notes() {
    switch (source) {
      case DataSource.showapi:
        return const [
          Text('两个接口，开通方式不一样',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            '① 1468 药品信息查询（免费）：按药名查成分和说明书，'
            '左侧「测试连接」测的就是它。\n'
            '② 66-24 药品条码查询（收费，需订购）：只有它能用条码直接查出药名。'
            '必须先到接口详情页购买专用资源包（0 元档也要点一次购买）。'
            '没订购就报「此应用无权调用本接口」(-1006 / -1007)，'
            '这时不是 Key 填错了，换 Key 没用。\n\n'
            '测试连接用官方示例药名「阿司匹林」；'
            '测试条码接口用官方示例码 6906618188014（成功会消耗 1 次调用）。',
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey),
          ),
        ];
      case DataSource.web:
        return const [
          Text('关于 68api 的反爬',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            'CSDN 那篇文章发布于 2025-11，当时直接 GET 页面再解析 HTML 就能拿到药名。'
            '2026-11 实测：该站已加入滑块验证，部分响应还是加密文本，'
            'App 内直接抓取大概率拿不到药名（测试按钮会明确告诉你原因）。\n\n'
            '所以这里保留了原文的 HTML 解析规则，同时支持标准 JSON 接口：'
            '如果你有自己的镜像、代理或其它药品条码 API，把地址填到上面即可，'
            '响应里含 name / goods_name / trade_name 等字段就能自动识别。\n\n'
            '不想折腾的话，直接在设置里选「选项3 本地药品条码库」，完全离线可用。',
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey),
          ),
        ];
      case DataSource.jisu:
        return const [
          Text('极速数据 · 免费额度与说明书',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            '免费会员每个接口 100 次/天，对家庭药箱完全够用。'
            '本 App 用的是「药品信息」的详情接口 /medicine/detail，'
            '可以直接按 69 码查出药名、成分、规格、厂家、批准文号和说明书；'
            '编辑页「按药名查说明书」则会先搜索再取详情。\n\n'
            '注册流程：jisuapi.com 注册 → 个人中心复制 AppKey → 填到上面。'
            '新账号 14 天内可免费调试，之后需在网站完成实名认证'
            '（个人身份证或企业营业执照）才能继续调用。\n\n'
            '查过的条码 / 药名会在本机缓存，同一个码只消耗一次额度；'
            '建档后再次扫码直接计件，不再联网。'
            '若提示「无权限」是没有申请这个接口；'
            '提示「超过次数」则是当天 100 次用完，次日 0 点重置。\n\n'
            '说明书仅供家庭整理参考，用药请以药盒实物说明书和医嘱为准。',
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey),
          ),
        ];
      case DataSource.local:
        return const [
          Text('数据来源与免责说明',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            '数据来自 Gitee 开源项目 yzhh/barcode（原始 EricLiuCN/barcode）的 '
            'medicine_info.zip，整理于 2023-09。开源库并不完善，'
            '4.7 万条中约 3.9 万条带说明书全文，也可能混入保健食品、'
            '药妆等非药品（App 会在分类里标出来）。\n\n'
            '另附一个可持续扩充的补充库，收录主库漏掉的常见规格'
            '（如蒙脱石散 6920729170096），查询时优先命中；'
            '「测试补充条目」按钮可以直接验证。\n\n'
            '扫码查不到时会自动退回手动填写一次，之后同码计件照常可用。'
            '说明书仅供家庭整理参考，用药请以药盒实物说明书和医嘱为准。',
            style: TextStyle(fontSize: 12, height: 1.5, color: Colors.grey),
          ),
        ];
    }
  }
}
