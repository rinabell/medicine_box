import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:medicine_box/services/data_source.dart';
import 'package:medicine_box/services/lookup_service.dart';
import 'package:medicine_box/services/medicine_lookup.dart';
import 'package:medicine_box/services/web_barcode_lookup.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 三套数据源的统一路由：页面只调 tryLookup / lookupByDrugName。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认数据源是本地库', () async {
    expect(await LookupService.currentSource(), DataSource.local);
  });

  test('选项1 没填 AppKey 时明确提示，并引导改用本地库', () async {
    final outcome = await LookupService.tryLookup('6900388311184',
        source: DataSource.showapi);
    expect(outcome.status, LookupStatus.noKey);
    expect(outcome.hint, contains('选项3'));
  });

  test('选项1 按药名查询没 Key 时同样给出原因', () async {
    final outcome = await LookupService.lookupByDrugName('阿司匹林',
        source: DataSource.showapi);
    expect(outcome.status, LookupStatus.noKey);
  });

  test('选项2 会把请求发到自定义接口并解析 JSON', () async {
    SharedPreferences.setMockInitialValues({
      'medicine_web_endpoint': 'https://example.com/drug/{code}',
      'medicine_web_appkey': 'k123',
    });
    late Uri requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(
        '{"data":{"goods_name":"布洛芬软胶囊","component":"布洛芬"}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final outcome = await LookupService.tryLookup(
      '6900251001013',
      source: DataSource.web,
      client: client,
    );

    expect(outcome.ok, true);
    expect(outcome.result!.name, '布洛芬软胶囊');
    expect(requested.path, '/drug/6900251001013');
    expect(requested.queryParameters['appKey'], 'k123');
  });

  test('选项2 只支持条码，按药名查询会给出替代方案', () async {
    final outcome = await LookupService.lookupByDrugName('阿司匹林',
        source: DataSource.web);
    expect(outcome.status, LookupStatus.notFound);
    expect(outcome.hint, contains('本地药品条码库'));
  });

  test('选项3 非法条码在路由层就被拦下，不会解压数据库', () async {
    final outcome =
        await LookupService.tryLookup('not-a-code', source: DataSource.local);
    expect(outcome.status, LookupStatus.invalidCode);
  });

  test('选项2 的接口地址与 Key 分开保存在本机', () async {
    await LookupService.saveWebEndpoint('https://example.com/{code}');
    await LookupService.saveWebKey('token-001');

    expect(await LookupService.readWebEndpoint(), 'https://example.com/{code}');
    expect(await LookupService.readWebKey(), 'token-001');

    // 留空时恢复默认地址
    await LookupService.saveWebEndpoint('');
    expect(await LookupService.readWebEndpoint(),
        WebBarcodeLookup.defaultEndpoint);
  });

  test('选项1 的 AppKey 读写与清空', () async {
    await LookupService.saveKey('  showapi-key  ');
    expect(await LookupService.readKey(), 'showapi-key');
    await LookupService.saveKey('');
    expect(await LookupService.readKey(), '');
  });

  test('选项4 没填 AppKey 时明确提示去设置页', () async {
    final outcome = await LookupService.tryLookup(
      '6900388311184',
      source: DataSource.jisu,
    );
    expect(outcome.status, LookupStatus.noKey);
    expect(outcome.hint, contains('选项4'));
  });

  test('选项4 按条码路由到 /medicine/detail', () async {
    SharedPreferences.setMockInitialValues({
      'medicine_jisu_appkey': 'jisu-key',
    });
    late Uri requested;
    final client = MockClient((request) async {
      requested = request.url;
      return http.Response(
        '{"status":0,"result":{"name":"蒙脱石散","ingredients":"蒙脱石"}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final outcome = await LookupService.tryLookup(
      '6920729170096',
      source: DataSource.jisu,
      client: client,
    );
    expect(outcome.ok, true);
    expect(outcome.result!.name, '蒙脱石散');
    expect(requested.path, '/medicine/detail');
    expect(requested.queryParameters['appkey'], 'jisu-key');
  });

  test('选项4 的 AppKey 读写与清空', () async {
    await LookupService.saveJisuKey('  jisu-key  ');
    expect(await LookupService.readJisuKey(), 'jisu-key');
    await LookupService.saveJisuKey('');
    expect(await LookupService.readJisuKey(), '');
  });

  test('选项1 的条码接口测试没 Key 时不发请求', () async {
    final outcome = await LookupService.testBarcodeLookup();
    expect(outcome.status, LookupStatus.noKey);
    expect(outcome.hint, contains('控制台'));
  });

  test('testSource 会按传入的数据源分派', () async {
    final showapi =
        await LookupService.testSource(DataSource.showapi);
    expect(showapi.status, LookupStatus.noKey);

    SharedPreferences.setMockInitialValues({
      'medicine_web_endpoint': 'https://example.com/{code}',
    });
    final web = await LookupService.testSource(
      DataSource.web,
      client: MockClient((_) async => http.Response(
            '{"data":{"goods_name":"测试药品"}}',
            200,
            headers: {'content-type': 'application/json'},
          )),
    );
    expect(web.ok, true);
    expect(web.result!.name, '测试药品');
  });
}
