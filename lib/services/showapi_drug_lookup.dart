import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'medicine_lookup.dart';
import 'showapi_gateway.dart';

/// 适配器 B：万维易源 showapi「1468-4 药名查询药品信息」（官方标注免费服务）。
///
/// 依据用户提供的官方 OpenAPI YAML（https://www.showapi.com/openapi/market/1468.yaml）：
///   POST https://route.showapi.com/1468-4?appKey=YOUR_APPKEY
///   content-type: application/x-www-form-urlencoded
///   body: searchKey=阿司匹林&page=1&maxResult=10
///   showapi_res_body.ret_code == "0" 表示成功，数据在 drugList[0]
///
/// 【与 66-24 的关键差别】1468 的 4 个接入点全部按「药名 / 批准文号 /
/// 分类Id / 药品Id」检索，**不接受商品条码**。所以它不能替代扫码直查，
/// 但可以在用户手填药名后，免费自动补全成分 + 说明书全文——这正是
/// 需求④「搜索说明书内容」最需要的数据来源。
///
/// 1468 其它接入点（本 App 暂未用）：
///   1468-1 药品分类（无参数，返回 class/classify/classifyId）
///   1468-2 按 classifyId 列药品
///   1468-3 按 searchType+searchKey 查详细信息
class ShowapiDrugLookup {
  static const String endpoint = 'https://route.showapi.com/1468-4';

  /// 官方文档示例药名，用于设置页「测试连接」。
  static const String demoName = '阿司匹林';

  static const String apiName = '1468 药品信息查询';

  static const Duration timeout = Duration(seconds: 15);

  /// drugList 字段 → 说明书段落标题。const Map 保持插入顺序，
  /// 拼出来的说明书顺序稳定，便于全文搜索与人工阅读。
  static const Map<String, String> leafletLabels = {
    'xz': '性状',
    'syz': '适应症 / 功能主治',
    'gg': '规格',
    'yfyl': '用法用量',
    'blfy': '不良反应',
    'jj': '禁忌',
    'zysx': '注意事项',
    'yfjbrqfnyy': '孕妇及哺乳期妇女用药',
    'etyy': '儿童用药',
    'lryy': '老人用药',
    'ywxhzy': '药物相互作用',
    'ywgl': '药物过量',
    'yldl': '药理毒理',
    'yddlx': '药代动力学',
    'zc': '贮藏',
    'yxq': '有效期',
    'zxbz': '执行标准',
    'pzwh': '批准文号',
    'manu': '生产企业',
    'jx': '剂型',
    'fl': '药品分类',
    'pp': '品牌',
    'wyy': '是否外用药',
  };

  /// 这些值拼进说明书没有信息量，直接跳过。
  static const Set<String> blankValues = {'', 'null', '-', '尚不明确'};

  final String appKey;
  final http.Client _client;

  ShowapiDrugLookup({required this.appKey, http.Client? client})
      : _client = client ?? http.Client();

  Future<LookupOutcome> lookupByName(String drugName) async {
    final key = appKey.trim();
    if (key.isEmpty) {
      return const LookupOutcome(
        LookupStatus.noKey,
        message: '未填写 AppKey，无法使用联网药品库',
        hint: '可留空继续手填；想自动补全说明书就到 showapi 控制台复制 AppKey。',
      );
    }

    final keyword = drugName.trim();
    if (keyword.isEmpty) {
      return const LookupOutcome(
        LookupStatus.invalidCode,
        message: '请先填写药名，再点「按药名查说明书」',
      );
    }

    final uri = Uri.parse(endpoint).replace(queryParameters: {'appKey': key});
    try {
      final response = await _client
          .post(
            uri,
            headers: const {'content-type': 'application/x-www-form-urlencoded'},
            body: {
              'searchKey': keyword,
              'page': '1',
              'maxResult': '5',
            },
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
        message: '药品库查询超时（${timeout.inSeconds} 秒），请稍后重试',
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

  /// 纯解析函数：直接喂官方返回示例 JSON 即可单测。
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

    final gateway =
        ShowapiGateway.envelopeError(decoded, apiName: apiName);
    if (gateway != null) return gateway;

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

    final msg = (body['msg'] ?? '').toString().trim();
    final retCode = body['ret_code'];
    if (retCode != null && retCode.toString() != '0') {
      return LookupOutcome(
        LookupStatus.notFound,
        message: msg.isEmpty ? '药品库没有查到这个药名' : msg,
      );
    }

    final list = body['drugList'];
    if (list is! List || list.isEmpty) {
      return LookupOutcome(
        LookupStatus.notFound,
        message: msg.isEmpty ? '药品库没有匹配的药品' : msg,
        hint: '换个药名试试（去掉品牌名、用通用名，例如「布洛芬」）。',
      );
    }

    final drug = list.first;
    if (drug is! Map) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '药品库返回的条目格式异常',
      );
    }

    String field(String key) => (drug[key] ?? '').toString().trim();
    String firstNonEmpty(List<String> keys) {
      for (final key in keys) {
        final value = field(key);
        if (value.isNotEmpty && value != 'null') return value;
      }
      return '';
    }

    final name = firstNonEmpty(['drugName', 'tymc', 'spmc']);
    if (name.isEmpty) {
      return const LookupOutcome(
        LookupStatus.notFound,
        message: '药品库返回了条目但没有药名',
      );
    }

    final parts = <String>[];
    for (final entry in leafletLabels.entries) {
      final value = field(entry.key);
      if (blankValues.contains(value)) continue;
      parts.add('${entry.value}：$value');
    }

    return LookupOutcome.success(LookupResult(
      name: name,
      ingredient: field('zycf'),
      leaflet: parts.join('\n'),
      category: field('fl'),
    ));
  }
}
