import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'barcode_utils.dart';
import 'data_source.dart';
import 'jisu_lookup.dart';
import 'local_catalog.dart';
import 'medicine_lookup.dart';
import 'showapi_drug_lookup.dart';
import 'showapi_lookup.dart';
import 'web_barcode_lookup.dart';

/// 业务逻辑层：三套数据源的统一入口。
///
/// 【V1.4】数据源在设置页四选一，只存本机：
///   选项1 showapi → 条码直查 66-24（付费）+ 药名补全 1468（免费）
///   选项2 web     → 自定义网页 / JSON 接口（参照 CSDN 的 68api 方案）
///   选项3 local   → 内置 4.7 万条药品条码库，完全离线（默认）
///   选项4 jisu    → 极速数据药品库，100 次/天免费，条码直查带说明书
///
/// 页面只认识两个方法：tryLookup(条码)、lookupByDrugName(药名)，
/// 换数据源不需要改任何页面或数据库代码。失败一律返回带原因的 outcome，
/// 绝不阻断建档。
class LookupService {
  LookupService._();

  /// 选项1 的 AppKey（V1.2 沿用，保持兼容）。
  static const String _storageKey = 'medicine_lookup_appkey';

  /// 选项2 的 AppKey / 接口地址。
  static const String _webKeyStorage = 'medicine_web_appkey';
  static const String _webEndpointStorage = 'medicine_web_endpoint';

  /// 选项4 极速数据的 AppKey。
  static const String _jisuKeyStorage = 'medicine_jisu_appkey';

  static Future<String> readKey() async => _read(_storageKey);

  static Future<void> saveKey(String value) async => _save(_storageKey, value);

  static Future<String> readWebKey() async => _read(_webKeyStorage);

  static Future<void> saveWebKey(String value) async =>
      _save(_webKeyStorage, value);

  static Future<String> readWebEndpoint() async {
    final value = await _read(_webEndpointStorage);
    return value.isEmpty ? WebBarcodeLookup.defaultEndpoint : value;
  }

  static Future<void> saveWebEndpoint(String value) async {
    await _save(_webEndpointStorage, value);
  }

  static Future<String> readJisuKey() async => _read(_jisuKeyStorage);

  static Future<void> saveJisuKey(String value) async =>
      _save(_jisuKeyStorage, value);

  static Future<String> _read(String key) async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getString(key) ?? '').trim();
  }

  static Future<void> _save(String key, String value) async {
    final sp = await SharedPreferences.getInstance();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await sp.remove(key);
    } else {
      await sp.setString(key, trimmed);
    }
  }

  static Future<DataSource> currentSource() => DataSourceSettings.current();

  /// 扫码拿到新编码时调用。查不到会带上「为什么」和「怎么办」。
  static Future<LookupOutcome> tryLookup(
    String code, {
    http.Client? client,
    DataSource? source,
  }) async {
    final selected = source ?? await currentSource();
    switch (selected) {
      case DataSource.showapi:
        return _showapiByCode(code, client);
      case DataSource.web:
        return _webByCode(code, client);
      case DataSource.local:
        return LocalCatalog.lookup(code);
      case DataSource.jisu:
        return _jisuByCode(code, client);
    }
  }

  /// 编辑页「按药名查说明书」。选项2 只支持条码，给出明确说明。
  static Future<LookupOutcome> lookupByDrugName(
    String drugName, {
    http.Client? client,
    DataSource? source,
  }) async {
    final selected = source ?? await currentSource();
    switch (selected) {
      case DataSource.showapi:
        return _showapiByName(drugName, client);
      case DataSource.web:
        return const LookupOutcome(
          LookupStatus.notFound,
          message: '自定义网页 / 接口数据源只支持按条码查询',
          hint: '请手动填写成分和说明书；或到设置里切到「本地药品条码库」'
              '按药名补全。',
        );
      case DataSource.local:
        return LocalCatalog.lookupByName(drugName);
      case DataSource.jisu:
        return _jisuByName(drugName, client);
    }
  }

  /// 设置页「测试」按钮：默认测当前选中的数据源。
  static Future<LookupOutcome> testConnection({
    http.Client? client,
    DataSource? source,
  }) async =>
      testSource(source ?? await currentSource(), client: client);

  /// 测指定数据源，供二级配置页复用。
  static Future<LookupOutcome> testSource(
    DataSource source, {
    http.Client? client,
  }) async {
    switch (source) {
      case DataSource.showapi:
        // 默认测免费的 1468，不消耗付费条码接口次数。
        return _showapiByName(ShowapiDrugLookup.demoName, client);
      case DataSource.web:
        return _webByCode(WebBarcodeLookup.demoCode, client);
      case DataSource.local:
        return LocalCatalog.lookup(LocalCatalog.demoCode);
      case DataSource.jisu:
        return _jisuByName(JisuLookup.demoName, client);
    }
  }

  /// 选项1 二级页专用：测需要订购的 66-24 条码接口。
  static Future<LookupOutcome> testBarcodeLookup({http.Client? client}) async {
    final key = await readKey();
    if (key.isEmpty) {
      return const LookupOutcome(
        LookupStatus.noKey,
        message: '还没有填写 AppKey',
        hint: '登录 showapi.com → 控制台 → 我的应用 → 复制 AppKey。',
      );
    }
    return _withClient(client,
        (cli) => ShowapiLookup(appKey: key, client: cli).lookup(ShowapiLookup.demoCode));
  }

  /// 选项2 二级页专用：测自定义接口。
  static Future<LookupOutcome> testWebLookup({http.Client? client}) =>
      _webByCode(WebBarcodeLookup.demoCode, client);

  /// 选项3 设置页专用：测本地库。
  static Future<LookupOutcome> testLocalLookup() =>
      LocalCatalog.lookup(LocalCatalog.demoCode);

  /// 选项4 二级页专用：测极速数据条码接口。
  static Future<LookupOutcome> testJisuBarcodeLookup({http.Client? client}) =>
      _jisuByCode(JisuLookup.demoCode, client);

  // ---------------- 具体实现 ----------------

  static Future<LookupOutcome> _jisuByCode(
    String code,
    http.Client? client,
  ) async {
    final key = await readJisuKey();
    return _withClient(
      client,
      (cli) => JisuLookup(appKey: key, client: cli).lookup(code),
    );
  }

  static Future<LookupOutcome> _jisuByName(
    String drugName,
    http.Client? client,
  ) async {
    final key = await readJisuKey();
    return _withClient(
      client,
      (cli) => JisuLookup(appKey: key, client: cli).lookupByName(drugName),
    );
  }

  static Future<LookupOutcome> _showapiByCode(
    String code,
    http.Client? client,
  ) async {
    final key = await readKey();
    if (key.isEmpty) {
      return const LookupOutcome(
        LookupStatus.noKey,
        message: '未填写 AppKey，已跳过联网查询，请手动填写一次资料',
        hint: '到「设置 → 选项1」填 AppKey；或切到「选项3 本地药品条码库」，'
            '不用 Key 也能查。',
      );
    }
    final normalized = BarcodeUtils.normalize(code);
    if (!BarcodeUtils.looksLikeBarcode(normalized)) {
      return LookupOutcome(
        LookupStatus.invalidCode,
        message: '“$code” 不像商品条码（应为 8~20 位数字），请手动填写',
      );
    }
    return _withClient(client,
        (cli) => ShowapiLookup(appKey: key, client: cli).lookup(normalized));
  }

  static Future<LookupOutcome> _showapiByName(
    String drugName,
    http.Client? client,
  ) async {
    final key = await readKey();
    if (key.isEmpty) {
      return const LookupOutcome(
        LookupStatus.noKey,
        message: '未填写 AppKey，无法使用联网药品库',
        hint: '可留空继续手填；也可以切到「选项3 本地药品条码库」离线补全。',
      );
    }
    return _withClient(client,
        (cli) => ShowapiDrugLookup(appKey: key, client: cli).lookupByName(drugName));
  }

  static Future<LookupOutcome> _webByCode(
    String code,
    http.Client? client,
  ) async {
    final endpoint = await readWebEndpoint();
    final key = await readWebKey();
    return _withClient(
      client,
      (cli) => WebBarcodeLookup(
        endpointTemplate: endpoint,
        appKey: key,
        client: cli,
      ).lookup(code),
    );
  }

  static Future<LookupOutcome> _withClient(
    http.Client? client,
    Future<LookupOutcome> Function(http.Client) action,
  ) async {
    final ownClient = client == null;
    final cli = client ?? http.Client();
    try {
      return await action(cli);
    } finally {
      if (ownClient) cli.close();
    }
  }
}
