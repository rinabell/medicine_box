import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../db/database_helper.dart';
import '../models/medicine.dart';
import '../services/barcode_utils.dart';
import '../services/lookup_service.dart';
import '../services/medicine_lookup.dart';
import '../widgets/expiry_dialog.dart';
import 'medicine_edit_page.dart';

/// 页面层：扫码页
///
/// 同时识别二维码和一维条码，覆盖药盒上的「追溯二维码」和「69 开头商品条码」。
/// 使用 mobile_scanner 7.x：旧版 5.2.3 与 Flutter 3.50 的 CameraX / 渲染层
/// 不兼容，会出现相机黑屏、无法调用的问题。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.itf,
      BarcodeFormat.dataMatrix,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  final DatabaseHelper _db = DatabaseHelper.instance;

  bool _busy = false;
  String _status = '把药盒上的二维码或条形码放进框里';

  /// 简单的重复扫码抑制：同一码 2 秒内只处理一次。
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _accept(String code) {
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt) < const Duration(seconds: 2)) {
      return false;
    }
    _lastCode = code;
    _lastAt = now;
    return true;
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// 扫码 / 手输编码的唯一入口：老码计件，新码建档。
  /// 需求3：识别后先弹保质期框（可跳过），结果是本次录入的日期列表
  /// （null 表示用户取消整个流程）。
  Future<void> _handleCode(String raw) async {
    final code = BarcodeUtils.normalize(raw);
    if (code.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _status = '正在核对药箱…';
    });

    final existing = await _db.findByCode(code);
    if (!mounted) return;

    // 先问保质期：老码带出已存日期方便追加，新码留空
    final expiryInput = await showExpiryDialog(
      context,
      initial: existing?.expiryDates,
    );
    if (!mounted) return;
    if (expiryInput == null) {
      // 用户按返回键取消整个流程
      setState(() {
        _busy = false;
        _status = '已取消，可继续扫码';
      });
      return;
    }

    if (existing != null) {
      // 需求②：同款药第二次扫到 → 件数 +1，不再让用户重复填资料
      await _db.increment(code);
      if (expiryInput.isNotEmpty) {
        await _db.appendExpiryDates(code, expiryInput);
      }
      if (!mounted) return;
      Navigator.of(context)
          .pop('已入库：${existing.name}，现有 ${existing.count + 1} 件');
      return;
    }

    setState(() => _status = '新药，正在查药品资料…');
    final outcome = await LookupService.tryLookup(code);
    if (!mounted) return;

    // 查到 → 带预填值进新建页；查不到 → 把「为什么没查到」一起带过去
    final saved = await Navigator.of(context).push<Medicine>(
      MaterialPageRoute(
        builder: (_) => MedicineEditPage(
          code: code,
          suggestion: outcome.result,
          // 需求3：把扫码弹窗录入的保质期带进建档页一起保存
          initialExpiryDates: expiryInput,
          // 带上「怎么办」：例如「没订购 66-24 资源包」会明确提示去订购，
          // 或引导用户改用免费的 1468 药品库按药名补全说明书。
          lookupMessage: outcome.ok ? null : outcome.displayMessage,
        ),
      ),
    );
    if (!mounted) return;
    if (saved != null) {
      Navigator.of(context).pop('已添加：${saved.name}');
    } else {
      setState(() {
        _busy = false;
        _status = '已取消，可继续扫码';
      });
    }
  }

  /// 码花了 / 反光扫不出来时的容错入口
  Future<void> _manualInput() async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入编码'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '药盒上的条码数字'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, input.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null && value.isNotEmpty) await _handleCode(value);
  }

  /// 需求2：药盒没有条码 / 条码扫不出但看得清药名时的入口。
  /// 输入药名 → 先按药名查一次说明书（补成分/说明书）→ 进建档页。
  /// 没有编码也能建档：用 MANUAL-时间戳 作为本机唯一主键，不影响计件和搜索。
  Future<void> _manualNameInput() async {
    final input = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入药名'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '药盒上的名字，例如 蒙脱石散',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, input.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name == null || name.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _status = '正在按药名查说明书…';
    });

    final outcome = await LookupService.lookupByDrugName(name);
    if (!mounted) return;

    final manualCode = 'MANUAL-${DateTime.now().microsecondsSinceEpoch}';
    final saved = await Navigator.of(context).push<Medicine>(
      MaterialPageRoute(
        builder: (_) => MedicineEditPage(
          code: manualCode,
          suggestion: LookupResult(
            name: name,
            ingredient: outcome.result?.ingredient ?? '',
            leaflet: outcome.result?.leaflet ?? '',
            category: outcome.result?.category ?? '',
          ),
          lookupMessage: outcome.ok ? null : outcome.displayMessage,
        ),
      ),
    );
    if (!mounted) return;
    if (saved != null) {
      Navigator.of(context).pop('已添加：${saved.name}');
    } else {
      setState(() {
        _busy = false;
        _status = '已取消，可继续扫码';
      });
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (_) {
      // 没有闪光灯的设备直接忽略
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('扫药盒上的码'),
        actions: [
          IconButton(
            tooltip: '开关闪光灯',
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  // 7.x 内置生命周期管理：切后台自动暂停、回来自动恢复
                  useAppLifecycleState: true,
                  placeholderBuilder: (_) => const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            '正在启动相机…',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),
                  errorBuilder: (context, error) => _CameraErrorView(
                    error: error,
                    onRetry: () => unawaited(_controller.start()),
                    onBack: () => Navigator.of(context).maybePop(),
                  ),
                  onDetect: (capture) {
                    if (_busy) return;
                    for (final barcode in capture.barcodes) {
                      final value = barcode.rawValue;
                      if (value == null) continue;
                      final code = BarcodeUtils.normalize(value);
                      if (code.isEmpty) continue;
                      if (!_accept(code)) return;
                      unawaited(_handleCode(code));
                      return;
                    }
                  },
                ),
                const Center(
                  child: _ScanFrame(),
                ),
                if (_busy)
                  const ColoredBox(
                    color: Color(0x66000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(_status, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _busy ? null : _manualInput,
                  icon: const Icon(Icons.keyboard),
                  label: const Text('扫不出来？手动输入编码'),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _manualNameInput,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('没有条码？手动输入药名'),
                ),
                const Text(
                  '提示：69 开头 13 位条形码命中率最高；20 位追溯码通常查不到资料。\n'
                  '默认查内置的 4.7 万条本地药品库（离线免费）；'
                  '查不到时填好药名再点「按药名查说明书」。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 180,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}

/// 相机出错时的兜底界面：把「权限被拒」「设备不支持」讲清楚，
/// 而不是像旧版本那样只剩一片黑屏。
class _CameraErrorView extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _CameraErrorView({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final code = error.errorCode;

    late final String title;
    late final String detail;
    switch (code) {
      case MobileScannerErrorCode.permissionDenied:
        title = '相机权限被拒绝';
        detail = '请到「系统设置 → 应用 → 药箱小管家 → 权限」里允许使用相机，'
            '然后点下面的「重试」。也可以先用「手动输入编码」建档。';
      case MobileScannerErrorCode.unsupported:
        title = '这台设备不支持相机扫码';
        detail = '可以先用下方「手动输入编码」建档，其余功能不受影响。';
      case MobileScannerErrorCode.controllerInitializing:
      case MobileScannerErrorCode.controllerAlreadyInitialized:
        title = '相机正在启动';
        detail = '稍等一秒再试；若一直停在这里，点「重试」。';
      case MobileScannerErrorCode.controllerDisposed:
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.controllerNotAttached:
      case MobileScannerErrorCode.genericError:
        title = '相机启动失败';
        detail = '${code.message}\n${error.errorDetails?.message ?? ''}'.trim();
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton(
                    onPressed: onBack,
                    child: const Text('返回'),
                  ),
                  ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '也可以下滑手动输入编码或药名',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
