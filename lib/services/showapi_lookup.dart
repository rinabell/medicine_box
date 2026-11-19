import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'barcode_utils.dart';
import 'medicine_lookup.dart';
import 'showapi_gateway.dart';

/// 适配器 A：万维易源 showapi「66-24 药品条码查询」（付费，需先订购资源包）。
///
/// 官方调用方式（已核对 2026-11 文档 / OpenAPI 页）：
///   POST https://route.showapi.com/66-24?appKey=YOUR_APPKEY
///   content-type: application/x-www-form-urlencoded
///   body: code=6906618188014
/// 只需要控制台里的 **AppKey**，不需要 appId / 签名。
///
/// 【重要前提】这是「条码查询接口」，页面标价「专用资源包 0/40/300/1500/6000 元，
/// 自购买起 12 个月有效」。**注册后拿到 AppKey 并不等于能调用**：必须到接口页
/// 购买/订购一次资源包（0 元档也要点购买），否则网关返回 -1006 / -1007
/// 「此应用无权调用本接口」。这也是 V1.1 用户实际遇到的报错。
///
/// 因此本 App 另配了免费的 1468 药品库（见 showapi_drug_lookup.dart）作为兜底：
/// 条码查不到时，用户手填药名即可自动补全成分与说明书。
class ShowapiLookup implements MedicineLookup {
  static const String endpoint = 'https://route.showapi.com/66-24';

  /// 官方文档里的示例条码，用于设置页「测试条码接口」。
  static const String demoCode = '6906618188014';

  static const String apiName = '66-24 药品条码查询';

  static const Duration timeout = Duration(seconds: 12);

  final String appKey;
  final http.Client _client;

  ShowapiLookup({required this.appKey, http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<LookupOutcome> lookup(String code) async {
    final key = appKey.trim();
    if (key.isEmpty) {
      return const LookupOutcome(
        LookupStatus.noKey,
        message: '还没有填写药品查询 AppKey',
      );
    }

    final normalized = BarcodeUtils.normalize(code);
    if (!BarcodeUtils.looksLikeBarcode(normalized)) {
      return LookupOutcome(
        LookupStatus.invalidCode,
        message: '“$code” 不像商品条码（应为 8~20 位数字）',
      );
    }

    final uri = Uri.parse(endpoint).replace(queryParameters: {'appKey': key});
    try {
      final response = await _client
          .post(
            uri,
            headers: const {'content-type': 'application/x-www-form-urlencoded'},
            body: {'code': normalized},
          )
          .timeout(timeout);

      final rawBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode != 200) {
        final gateway =
            ShowapiGateway.tryParseErrorBody(rawBody, apiName: apiName);
        if (gateway != null) return gateway;
        return LookupOutcome(
          LookupStatus.badResponse,
          message: '接口返回 HTTP ${response.statusCode}，可能被网络或代理拦截',
        );
      }
      return parseResponse(rawBody);
    } on TimeoutException {
      return LookupOutcome(
        LookupStatus.timeout,
        message: '联网查询超时（${timeout.inSeconds} 秒），请检查网络后点「重新联网查询」',
      );
    } on SocketException catch (e) {
      return LookupOutcome(
        LookupStatus.network,
        message: '网络不通：${e.message}',
      );
    } on http.ClientException catch (e) {
      return LookupOutcome(
        LookupStatus.network,
        message: '网络请求失败：${e.message}',
      );
    } catch (e) {
      return LookupOutcome(LookupStatus.unknown, message: '查询出错：$e');
    }
  }

  /// 纯解析函数，便于单元测试直接喂 JSON，不需要真的发请求。
  static LookupOutcome parseResponse(String rawBody) {
    dynamic decoded;
    try {
      decoded = jsonDecode(rawBody);
    } catch (_) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '接口返回的不是 JSON，可能被网关拦截了',
      );
    }
    if (decoded is! Map) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '接口返回结构异常',
      );
    }

    // 网关层错误：按 showapi_res_code 精确分类（不再靠文案猜）。
    final gateway =
        ShowapiGateway.envelopeError(decoded, apiName: apiName);
    if (gateway != null) return gateway;

    // 业务数据有时会被序列化成字符串，兼容一下
    dynamic body = decoded['showapi_res_body'];
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {
        // 保持原样，交给下面判断
      }
    }
    if (body is! Map) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '接口没有返回业务数据',
      );
    }

    final retCode = body['ret_code'];
    final remark = (body['remark'] ?? '').toString().trim();
    if (retCode != null && retCode.toString() != '0') {
      return LookupOutcome(
        LookupStatus.notFound,
        message: remark.isEmpty ? '该条码未收录' : remark,
      );
    }

    String field(String key) => (body[key] ?? '').toString().trim();

    final name = field('name');
    if (name.isEmpty) {
      return LookupOutcome(
        LookupStatus.notFound,
        message: remark.isEmpty ? '该条码未收录（接口没有返回药名）' : remark,
      );
    }

    // 把接口返回的结构化字段拼成说明书全文，供需求④全文搜索使用
    final parts = <String>[];
    void add(String label, String key) {
      final value = field(key);
      if (value.isEmpty || value == 'null') return;
      parts.add('$label：$value');
    }

    add('商品名/商标', 'trademark');
    add('规格', 'spec');
    add('性状', 'character');
    add('功能主治', 'purpose');
    add('用法用量', 'dosage');
    add('不良反应', 'other');
    add('禁忌', 'taboo');
    add('注意事项', 'consideration');
    add('贮藏', 'storage');
    add('有效期', 'validity');
    add('生产厂家', 'manuName');
    add('生产地址', 'manuAddress');
    add('批准文号', 'approval');
    add('补充说明', 'note');

    return LookupOutcome.success(LookupResult(
      name: name,
      ingredient: field('basis'),
      leaflet: parts.join('\n'),
      category: field('type'),
    ));
  }
}
