import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/services/local_catalog.dart';
import 'package:medicine_box/services/medicine_lookup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 选项3：用桌面 VM 的真实 SQLite（内存库）验证查询逻辑，
/// 不依赖手机、也不依赖打包进 APK 的 17MB asset。
void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE ${LocalCatalog.table} (
        barcode TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        component TEXT DEFAULT '',
        indication TEXT DEFAULT '',
        spec TEXT DEFAULT '',
        drug_form TEXT DEFAULT '',
        approval TEXT DEFAULT '',
        manufacturer TEXT DEFAULT '',
        leaflet TEXT DEFAULT '',
        category TEXT DEFAULT ''
      )
    ''');
    await db.insert(LocalCatalog.table, {
      'barcode': '6900388311184',
      'name': '阿司匹林肠溶片',
      'component': '乙酰水杨酸',
      'indication': '解热镇痛',
      'spec': '100mg*30片',
      'drug_form': '片剂',
      'approval': '国药准字H12345678',
      'manufacturer': '拜耳医药',
      'leaflet': '用法用量：一次1片，一日1次\n注意事项：饭后服用',
      'category': '药品',
    });
    await db.insert(LocalCatalog.table, {
      'barcode': '6900251001013',
      'name': '布洛芬软胶囊 (奥森)',
      'component': '布洛芬',
      'spec': '0.2g*12粒',
      'leaflet': '适应症：缓解轻至中度疼痛',
      'category': '药品',
    });
    await db.insert(LocalCatalog.table, {
      'barcode': '958193728058',
      'name': '汤臣倍健牌维生素B族片',
      'category': '保健食品',
    });
  });

  tearDown(() async => db.close());

  test('内置数据库分片齐全，首片是有效 SQLite 文件头', () {
    final dir = Directory(LocalCatalog.assetDir);
    expect(dir.existsSync(), true,
        reason: 'pubspec.yaml 需声明 assets/catalog/');
    final parts = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('medicine_catalog.db.'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(parts.length, LocalCatalog.partCount);

    final total = parts.fold<int>(0, (sum, f) => sum + f.lengthSync());
    expect(total, greaterThan(80 * 1024 * 1024));
    expect(parts.first.lengthSync(), 8 * 1024 * 1024);
    expect(parts.last.lengthSync(), lessThan(8 * 1024 * 1024));

    final head = parts.first.readAsBytesSync().sublist(0, 16);
    expect(String.fromCharCodes(head.sublist(0, 15)), 'SQLite format 3');
  });

  test('条目数与示例条码是有效常量', () {
    expect(LocalCatalog.knownRecordCount, 47722);
    expect(LocalCatalog.demoCode, '6900388311184');
    expect(LocalCatalog.demoCode.length, 13);
  });

  test('fromRow 把结构化字段和说明书全文都拼进可搜索文本', () {
    final row = {
      'name': '阿司匹林肠溶片',
      'component': '乙酰水杨酸',
      'spec': '100mg*30片',
      'drug_form': '片剂',
      'indication': '解热镇痛',
      'approval': '国药准字H12345678',
      'manufacturer': '拜耳医药',
      'leaflet': '用法用量：一次1片',
      'category': '药品',
    };
    final r = LocalCatalog.fromRow(row);
    expect(r.name, '阿司匹林肠溶片');
    expect(r.ingredient, '乙酰水杨酸');
    expect(r.leaflet, contains('规格：100mg*30片'));
    expect(r.leaflet, contains('批准文号：国药准字H12345678'));
    expect(r.leaflet, contains('用法用量：一次1片'));
    expect(r.category, '药品');
  });

  test('fromRow 空字段不产生多余冒号', () {
    final r = LocalCatalog.fromRow({'name': '某药'});
    expect(r.name, '某药');
    expect(r.ingredient, '');
    expect(r.leaflet, '');
  });

  test('按条码精确命中', () async {
    final outcome = await LocalCatalog.queryByCode(db, '6900388311184');
    expect(outcome.ok, true);
    expect(outcome.result!.name, '阿司匹林肠溶片');
    expect(outcome.result!.leaflet, contains('注意事项：饭后服用'));
  });

  test('按条码查不到时给出原因与替代方案', () async {
    final outcome = await LocalCatalog.queryByCode(db, '0000000000000');
    expect(outcome.status, LookupStatus.notFound);
    expect(outcome.message, contains('本地药品库'));
    expect(outcome.hint, contains('手动填写'));
  });

  test('按药名模糊匹配能补全成分和说明书', () async {
    final outcome = await LocalCatalog.queryByName(db, '布洛芬');
    expect(outcome.ok, true);
    expect(outcome.result!.ingredient, '布洛芬');
    expect(outcome.result!.leaflet, contains('适应症'));
  });

  test('多个匹配时优先返回最短（最接近通用名）的药名', () async {
    await db.insert(LocalCatalog.table, {
      'barcode': '6900000000001',
      'name': '阿司匹林',
      'component': '乙酰水杨酸',
    });
    final outcome = await LocalCatalog.queryByName(db, '阿司匹林');
    expect(outcome.result!.name, '阿司匹林');
  });

  test('药名里的 % 和 _ 被转义，不会命中全部', () async {
    final all = await LocalCatalog.queryByName(db, '%');
    expect(all.status, LookupStatus.notFound);
    final underscore = await LocalCatalog.queryByName(db, '_');
    expect(underscore.status, LookupStatus.notFound);
  });

  test('查不到药名时带出关键词和怎么办', () async {
    final outcome = await LocalCatalog.queryByName(db, '不存在的药名XYZ');
    expect(outcome.status, LookupStatus.notFound);
    expect(outcome.message, contains('不存在的药名XYZ'));
    expect(outcome.hint, contains('通用名'));
  });

  test('非法条码在 lookup 入口就被拦下，不会去解压 asset', () async {
    final outcome = await LocalCatalog.lookup('ABC');
    expect(outcome.status, LookupStatus.invalidCode);
  });

  test('空药名在按药名查询入口被拦下', () async {
    final outcome = await LocalCatalog.lookupByName('   ');
    expect(outcome.status, LookupStatus.invalidCode);
  });

  test('补充库是合法 JSON，包含用户反馈的蒙脱石散条码', () {
    final file = File(LocalCatalog.supplementAsset);
    expect(file.existsSync(), true, reason: '补充库需作为 asset 打包');
    final decoded = jsonDecode(file.readAsStringSync());
    expect(decoded, isA<List>());
    final entries = (decoded as List).cast<Map>();
    final hit = entries.where((e) => e['barcode'] == '6920729170096');
    expect(hit.length, 1);
    expect(hit.first['name'], contains('蒙脱石散'));
    expect(hit.first['approval'], '国药准字H20093375');
    expect(hit.first['leaflet'], contains('蒙脱石3g'));
  });

  test('补充记录能转成带来源说明的查询结果', () {
    final outcome = LocalCatalog.outcomeFromSupplement({
      'barcode': '6920729170096',
      'name': '蒙脱石散 (泻利停)',
      'component': '本品每袋含蒙脱石3g',
      'leaflet': '用法用量：口服',
      'category': '药品',
    });
    expect(outcome.ok, true);
    expect(outcome.result!.name, '蒙脱石散 (泻利停)');
    expect(outcome.result!.ingredient, '本品每袋含蒙脱石3g');
    expect(outcome.message, contains('补充资料'));
    expect(outcome.hint, contains('核对'));
  });

  test('补充记录缺药名时不返回成功', () {
    final outcome = LocalCatalog.outcomeFromSupplement({'barcode': '123'});
    expect(outcome.status, LookupStatus.notFound);
    expect(outcome.result, isNull);
  });

  test('纯查询函数 queryByCode 不受补充库影响，仍只查主库', () async {
    final outcome = await LocalCatalog.queryByCode(db, '6920729170096');
    expect(outcome.status, LookupStatus.notFound);
  });
}
