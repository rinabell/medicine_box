import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/db/database_helper.dart';
import 'package:medicine_box/models/medicine.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 用桌面 VM 上的真实 SQLite 跑存储层测试：
/// 建表、计件、模糊/精准搜索、转义、删除。
void main() {
  sqfliteFfiInit();

  late DatabaseHelper db;
  late String dbPath;

  setUp(() async {
    final name = 'test_${DateTime.now().microsecondsSinceEpoch}.db';
    db = DatabaseHelper.forTesting(databaseFactoryFfi, dbName: name);
    dbPath = p.join(await databaseFactoryFfi.getDatabasesPath(), name);
  });

  tearDown(() async {
    await db.closeForTest();
    final file = File(dbPath);
    if (await file.exists()) await file.delete();
  });

  Medicine sample({
    String code = '6901',
    String name = '布洛芬缓释胶囊',
    String ingredient = '布洛芬',
    String leaflet = '',
    String note = '',
    int count = 1,
    List<String> expiryDates = const [],
  }) =>
      Medicine(
        code: code,
        name: name,
        ingredient: ingredient,
        leaflet: leaflet,
        note: note,
        count: count,
        expiryDates: expiryDates,
        createdAt: 1,
        updatedAt: 1,
      );

  test('插入后能按编码查到', () async {
    await db.insert(sample());
    final found = await db.findByCode('6901');
    expect(found, isNotNull);
    expect(found!.name, '布洛芬缓释胶囊');
    expect(found.count, 1);
  });

  test('查不到的编码返回 null', () async {
    expect(await db.findByCode('0000'), isNull);
  });

  test('同一编码再次入库只加件数，不新增记录', () async {
    await db.insert(sample());
    final affected = await db.increment('6901');
    expect(affected, 1);

    final found = await db.findByCode('6901');
    expect(found!.count, 2);
    expect((await db.all()).length, 1);
  });

  test('重复插入同一编码会覆盖而不是报错', () async {
    await db.insert(sample(name: '旧名字'));
    await db.insert(sample(name: '新名字'));
    expect((await db.all()).length, 1);
    expect((await db.findByCode('6901'))!.name, '新名字');
  });

  test('updateCount 支持加减，负数归零', () async {
    await db.insert(sample(count: 2));
    await db.updateCount('6901', 5);
    expect((await db.findByCode('6901'))!.count, 5);

    await db.updateCount('6901', -3);
    expect((await db.findByCode('6901'))!.count, 0);
  });

  test('模糊搜索命中药名', () async {
    await db.insert(sample(name: '布洛芬缓释胶囊'));
    await db.insert(sample(code: '6902', name: '阿莫西林', ingredient: '阿莫西林'));
    final result = await db.search('布洛芬', exact: false);
    expect(result.length, 1);
    expect(result.first.name, '布洛芬缓释胶囊');
  });

  test('模糊搜索命中说明书内容', () async {
    await db.insert(sample(leaflet: '功能主治：用于缓解轻至中度疼痛'));
    final result = await db.search('轻至中度', exact: false);
    expect(result.length, 1);
  });

  test('模糊搜索命中备注', () async {
    await db.insert(sample(note: '放在客厅抽屉第二层'));
    expect((await db.search('客厅抽屉', exact: false)).length, 1);
  });

  test('模糊搜索命中编码', () async {
    await db.insert(sample(code: '6906618188014'));
    expect((await db.search('69066', exact: false)).length, 1);
  });

  test('英文搜索不区分大小写', () async {
    await db.insert(sample(name: 'Ibuprofen'));
    expect((await db.search('ibuprofen', exact: false)).length, 1);
  });

  test('精准模式药名不做包含匹配', () async {
    // 成分留空，确保只有药名参与比较
    await db.insert(sample(name: '布洛芬缓释胶囊', ingredient: ''));
    expect((await db.search('布洛芬', exact: true)).length, 0);
    expect((await db.search('布洛芬缓释胶囊', exact: true)).length, 1);
  });

  test('精准模式成分完全一致时命中', () async {
    await db.insert(sample(name: '布洛芬缓释胶囊', ingredient: '布洛芬'));
    final result = await db.search('布洛芬', exact: true);
    expect(result.length, 1);
    expect(result.first.name, '布洛芬缓释胶囊');
  });

  test('精准模式按精确短语匹配说明书', () async {
    await db.insert(sample(leaflet: '功能主治：用于缓解轻至中度疼痛'));
    expect((await db.search('缓解轻至中度', exact: true)).length, 1);
    expect((await db.search('缓解中度', exact: true)).length, 0);
  });

  test('精准模式支持按备注完全一致搜索', () async {
    await db.insert(sample(note: '饭后吃'));
    expect((await db.search('饭后吃', exact: true)).length, 1);
    expect((await db.search('饭后', exact: true)).length, 0);
  });

  test('关键词里的 % 被当成普通字符，不会匹配所有记录', () async {
    await db.insert(sample(name: '布洛芬'));
    await db.insert(sample(code: '6902', name: '阿莫西林'));
    expect((await db.search('%', exact: false)).length, 0);
  });

  test('关键词里的 _ 被当成普通字符', () async {
    await db.insert(sample(name: 'abc'));
    expect((await db.search('a_c', exact: false)).length, 0);
  });

  test('空关键词返回全部记录', () async {
    await db.insert(sample(name: 'A'));
    await db.insert(sample(code: '6902', name: 'B'));
    expect((await db.search('   ', exact: false)).length, 2);
  });

  test('结果按最近更新倒序', () async {
    await db.insert(const Medicine(
      code: 'a',
      name: 'A',
      createdAt: 1,
      updatedAt: 100,
    ));
    await db.insert(const Medicine(
      code: 'b',
      name: 'B',
      createdAt: 1,
      updatedAt: 200,
    ));
    final all = await db.all();
    expect(all.first.code, 'b');
  });

  test('删除后查不到，也不在列表里', () async {
    await db.insert(sample());
    await db.delete('6901');
    expect(await db.findByCode('6901'), isNull);
    expect(await db.all(), isEmpty);
  });

  test('update 能改药名、备注和件数', () async {
    await db.insert(sample());
    final updated = sample(name: '新药名', note: '新备注', count: 9);
    await db.update(updated);

    final found = await db.findByCode('6901');
    expect(found!.name, '新药名');
    expect(found.note, '新备注');
    expect(found.count, 9);
  });

  test('保质期随档案存取，往返不丢失', () async {
    await db.insert(sample(
      expiryDates: const ['2026-12-01', '2027-06-15'],
    ));
    final found = await db.findByCode('6901');
    expect(found!.expiryDates, ['2026-12-01', '2027-06-15']);
  });

  test('同码再扫计件时保质期不被清空', () async {
    await db.insert(sample(expiryDates: const ['2027-01-01']));
    await db.increment('6901');
    final found = await db.findByCode('6901');
    expect(found!.count, 2);
    expect(found.expiryDates, ['2027-01-01']);
  });
}
