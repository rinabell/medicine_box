import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformAssetBundle, rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'barcode_utils.dart';
import 'medicine_lookup.dart';

/// 选项3：App 内置的本地静态药品条码库（完全离线、免费、无需 AppKey）。
///
/// 数据来源：Gitee 开源项目 `yzhh/barcode`（原始 EricLiuCN/barcode）的
/// `medicine_info.zip`，MySQL 导出 81MB / 47,737 条。转换脚本筛掉无条码、
/// 无药名的记录，把说明书 HTML 转成纯文本，得到 **47,722 条**：
///   - 39,813 条带说明书全文
///   - 39,114 条带成分
/// 转成 SQLite 后 83MB，切成 11 个 8MB 分片作为 asset 打包
/// （APK 内 deflate 后约 18MB）。
///
/// 【为什么分片】Android Gradle 插件会把 `.gz` 结尾的 asset 自动解压、
/// 去掉后缀再打包，导致运行时按 `.gz` 名字加载不到；而单个 83MB asset
/// 一次性读进内存又容易在低端机上 OOM。分片同时解决这两个问题：
/// 首次使用时逐片写入 App 私有目录（约 1~3 秒，只做一次），内存峰值 ~8MB。
/// 之后用 readonly SQLite 直接查：条码精确命中、药名/成分/说明书模糊搜。
/// 另有 `medicine_supplement.json` 补充库，收录少数主库漏掉的常见规格
/// （如蒙脱石散 6920729170096），查询时优先命中，可随时追加。
/// 数据来自开源项目与公开药品资料，仅用于家庭整理参考，
/// 用药请以实物说明书和医嘱为准。
class LocalCatalog {
  LocalCatalog._();

  /// 分片 asset 的目录、前缀与数量（由构建脚本生成，改动需同步递增版本）。
  static const String assetDir = 'assets/catalog/';
  static const String assetPrefix = 'medicine_catalog.db.';
  static const int partCount = 11;

  static const String dbFileName = 'medicine_catalog.db';
  static const String versionFileName = 'medicine_catalog.version';

  /// 改数据结构时递增，App 会自动重新初始化一次。
  static const int catalogVersion = 2;

  static const String table = 'medicine_catalog';

  /// 本地库里真实存在的示例条码（阿司匹林肠溶片），用于「测试本地库」按钮。
  static const String demoCode = '6900388311184';

  /// 补充库：开源主库漏收录、但已核实过的条目。一个小的 JSON asset，
  /// 查条码时优先于主库命中，方便以后持续补充而不必重做 87MB 分片。
  static const String supplementAsset = '${assetDir}medicine_supplement.json';

  /// 用户反馈的漏收录条码（蒙脱石散/泻利停），用于「测试补充条目」按钮。
  static const String supplementDemoCode = '6920729170096';

  /// 已知的条目数，用于设置页展示（不查库也能显示）。
  static const int knownRecordCount = 47722;

  /// 带千分位的展示文本。
  static const String recordCountLabel = '47,722';

  static Database? _db;

  /// 补充库缓存：asset 很小，只加载一次。加载失败（如桌面单测没有
  /// asset bundle）就当成空库，绝不影响主库工作。
  static Map<String, Map<String, Object?>>? _supplements;

  static Future<Map<String, Map<String, Object?>>> supplements() async {
    final cached = _supplements;
    if (cached != null) return cached;
    final map = <String, Map<String, Object?>>{};
    try {
      final text = await rootBundle.loadString(supplementAsset);
      final decoded = jsonDecode(text);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map &&
              item['barcode'] is String &&
              item['name'] is String) {
            map[item['barcode'] as String] = item.map(
              (k, v) => MapEntry<String, Object?>(k.toString(), v),
            );
          }
        }
      }
    } catch (_) {
      // 补充库是附加增强，加载失败时静默降级为「没有补充条目」。
    }
    _supplements = map;
    return map;
  }

  /// 把一条补充记录转成统一的查询结果，并明确标注资料来源。
  static LookupOutcome outcomeFromSupplement(Map<String, Object?> row) {
    final result = fromRow(row);
    if (result.name.isEmpty) {
      return const LookupOutcome(
        LookupStatus.notFound,
        message: '补充资料缺少药名',
      );
    }
    return LookupOutcome(
      LookupStatus.success,
      result: result,
      message: '查到（补充资料）：${result.name}',
      hint: '该条码是开源主库未收录的规格，资料已按药盒核实补充；'
          '建档前请再和实物说明书核对一次。',
    );
  }

  static Future<String> get _dir => getDatabasesPath();

  static Future<bool> isInstalled() async {
    final dir = await _dir;
    final dbFile = File(p.join(dir, dbFileName));
    final versionFile = File(p.join(dir, versionFileName));
    if (!await dbFile.exists() || !await versionFile.exists()) return false;
    try {
      if ((await versionFile.readAsString()).trim() != '$catalogVersion') {
        return false;
      }
    } catch (_) {
      return false;
    }
    // 解压到一半的残文件不算装好
    return await dbFile.length() > 1024 * 1024;
  }

  /// 把分片 asset 依次写入私有目录。
  /// 用 PlatformAssetBundle（不缓存）而不是 rootBundle，避免 11 个分片
  /// 全部留在内存里；每片写完就释放，峰值内存约 8MB。
  static Future<void> install({bool force = false}) async {
    if (!force && await isInstalled()) return;

    final dir = await _dir;
    final target = File(p.join(dir, dbFileName));
    final tmp = File(p.join(dir, '$dbFileName.tmp'));
    if (await tmp.exists()) await tmp.delete();

    await close();

    final bundle = PlatformAssetBundle();
    final sink = tmp.openWrite();
    try {
      for (var i = 0; i < partCount; i++) {
        final key = '$assetDir$assetPrefix${i.toString().padLeft(2, '0')}';
        final data = await bundle.load(key);
        final bytes =
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        await sink.addStream(Stream<List<int>>.fromIterable([bytes]));
      }
    } finally {
      await sink.close();
    }

    if (await target.exists()) await target.delete();
    await tmp.rename(target.path);
    await File(p.join(dir, versionFileName)).writeAsString('$catalogVersion');
  }

  static Future<Database> open() async {
    final opened = _db;
    if (opened != null) return opened;
    await install();
    final path = p.join(await _dir, dbFileName);
    final db = await openDatabase(path, readOnly: true);
    _db = db;
    return db;
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<int> count() async {
    final db = await open();
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return (rows.first['n'] as int?) ?? 0;
  }

  /// 供查询链路调用：条码 → 药名 / 成分 / 说明书。永不抛异常。
  static Future<LookupOutcome> lookup(String code) async {
    final normalized = BarcodeUtils.normalize(code);
    if (!BarcodeUtils.looksLikeBarcode(normalized)) {
      return LookupOutcome(
        LookupStatus.invalidCode,
        message: '“$code” 不像商品条码（应为 8~20 位数字）',
      );
    }
    try {
      // 补充条目优先：将来若主库某条数据有误，补充库可以直接覆盖纠正。
      final extra = (await supplements())[normalized];
      if (extra != null) return outcomeFromSupplement(extra);
      final db = await open();
      return await queryByCode(db, normalized);
    } catch (e) {
      return LookupOutcome(
        LookupStatus.unknown,
        message: '本地药品库读取失败：$e',
        hint: '到「设置 → 选项3」点一次「重建本地库」；也可以手动填写资料。',
      );
    }
  }

  /// 按药名补全说明书（编辑页的「按药名查说明书」在本地库模式下走这里）。
  static Future<LookupOutcome> lookupByName(String drugName) async {
    final keyword = drugName.trim();
    if (keyword.isEmpty) {
      return const LookupOutcome(
        LookupStatus.invalidCode,
        message: '请先填写药名，再点「按药名查说明书」',
      );
    }
    try {
      for (final row in (await supplements()).values) {
        if ((row['name'] ?? '').toString().contains(keyword)) {
          return outcomeFromSupplement(row);
        }
      }
      final db = await open();
      return await queryByName(db, keyword);
    } catch (e) {
      return LookupOutcome(
        LookupStatus.unknown,
        message: '本地药品库读取失败：$e',
        hint: '到「设置 → 选项3」点一次「重建本地库」；也可以手动填写资料。',
      );
    }
  }

  /// 纯查询函数：接受 DatabaseExecutor，方便用内存 SQLite 做单元测试。
  static Future<LookupOutcome> queryByCode(
    DatabaseExecutor db,
    String normalizedCode,
  ) async {
    final rows = await db.query(
      table,
      where: 'barcode = ?',
      whereArgs: [normalizedCode],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const LookupOutcome(
        LookupStatus.notFound,
        message: '本地药品库里没有这个条码',
        hint: '这个库收录了 4.7 万条常见药品条码，并不覆盖全部药品；'
            '可直接手动填写一次，之后扫码计件照常可用。'
            '也可以在设置里临时切到在线数据源再试。',
      );
    }
    final result = fromRow(rows.first);
    if (result.name.isEmpty) {
      return const LookupOutcome(
        LookupStatus.notFound,
        message: '本地药品库这条记录没有药名',
      );
    }
    return LookupOutcome.success(result);
  }

  /// 药名模糊匹配；转义 LIKE 通配符，避免用户输入 `%` 命中全部。
  static Future<LookupOutcome> queryByName(
    DatabaseExecutor db,
    String keyword,
  ) async {
    final escaped = keyword
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = await db.query(
      table,
      where: "name LIKE ? ESCAPE '\\'",
      whereArgs: ['%$escaped%'],
      orderBy: 'LENGTH(name) ASC',
      limit: 5,
    );
    if (rows.isEmpty) {
      return LookupOutcome(
        LookupStatus.notFound,
        message: '本地药品库没有匹配的药名：$keyword',
        hint: '换个通用名试试（去掉品牌、括号里的内容），或直接手填成分和说明书。',
      );
    }
    return LookupOutcome.success(fromRow(rows.first));
  }

  /// 把 SQLite 行拼成 App 统一的 LookupResult。
  /// 说明书全文 = 结构化字段 + 原始说明书，全部进搜索范围（需求④）。
  static LookupResult fromRow(Map<String, Object?> row) {
    String field(String key) => (row[key] ?? '').toString().trim();

    final parts = <String>[];
    void add(String label, String value) {
      if (value.isNotEmpty && value != 'null') parts.add('$label：$value');
    }

    add('规格', field('spec'));
    add('剂型', field('drug_form'));
    add('适应症', field('indication'));
    add('批准文号', field('approval'));
    add('生产企业', field('manufacturer'));
    final leaflet = field('leaflet');
    if (leaflet.isNotEmpty) parts.add(leaflet);

    return LookupResult(
      name: field('name'),
      ingredient: field('component'),
      leaflet: parts.join('\n'),
      category: field('category'),
    );
  }
}
