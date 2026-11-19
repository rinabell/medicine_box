import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

import 'barcode_utils.dart';
import 'medicine_lookup.dart';

/// 适配器 D：极速数据（jisuapi）药品库——免费会员 100 次/天。
///
/// 官方文档（2026-11 核对）：
///   详情（本 App 主用，条码直查且带说明书）：
///     GET https://api.jisuapi.com/medicine/detail?appkey=KEY&barcode=69xxx
///     也可用 medicine_id / approval_num 三选一。
///   搜索（编辑页「按药名查说明书」用）：
///     GET https://api.jisuapi.com/medicine/query?appkey=KEY&name=阿司匹林
///
/// 返回：顶层 status=0 成功，业务数据在 result（对象或数组）。
/// 免费会员单接口 100 次/天；注册 14 天内可免费调试，之后需实名认证。
///
/// 【省钱设计】查到的结果进内存缓存：同一次 App 运行里，同一条码 /
/// 同一药名只发一次请求；再加上建档后扫码页的 findByCode 天然命中，
/// 基本做到「一个药只消耗一次免费额度」。
class JisuLookup implements MedicineLookup {
  static const String detailEndpoint = 'https://api.jisuapi.com/medicine/detail';
  static const String queryEndpoint = 'https://api.jisuapi.com/medicine/query';

  /// 官方搜索示例药名，用于设置页「测试连接」（一定有数据，最可靠）。
  static const String demoName = '阿司匹林';

  /// 本地库里已验证过的真实条码，用于「测试条码查询」。
  static const String demoCode = '6900388311184';

  static const String apiName = '极速数据药品库';

  static const Duration timeout = Duration(seconds: 12);

  final String appKey;
  final http.Client _client;

  /// 成功结果缓存：key = 'code:xxx' 或 'name:xxx'。
  static final Map<String, LookupOutcome> _cache = {};

  /// 测试专用：清空缓存。
  @visibleForTesting
  static void clearCache() => _cache.clear();

  JisuLookup({required this.appKey, http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<LookupOutcome> lookup(String code) async {
    final key = appKey.trim();
    if (key.isEmpty) {
      return const LookupOutcome(
        LookupStatus.noKey,
        message: '还没有填写极速数据的 AppKey',
        hint: '到 jisuapi.com 注册 → 个人中心复制 AppKey，填到「设置 → 选项4」。',
      );
    }

    final normalized = BarcodeUtils.normalize(code);
    if (!BarcodeUtils.looksLikeBarcode(normalized)) {
      return LookupOutcome(
        LookupStatus.invalidCode,
        message: '“$code” 不像商品条码（应为 8~20 位数字）',
      );
    }

    final cacheKey = 'code:$normalized';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final outcome = await _get(
      detailEndpoint,
      {'appkey': key, 'barcode': normalized},
    );
    if (outcome.ok) _cache[cacheKey] = outcome;
    return outcome;
  }

  /// 编辑页按药名补全：先搜索拿到 medicine_id，再查详情取说明书。
  /// 两步各消耗一次；结果同样进缓存。
  Future<LookupOutcome> lookupByName(String drugName) async {
    final key = appKey.trim();
    final keyword = drugName.trim();
    if (key.isEmpty) {
      return const LookupOutcome(
        LookupStatus.noKey,
        message: '还没有填写极速数据的 AppKey',
      );
    }
    if (keyword.isEmpty) {
      return const LookupOutcome(
        LookupStatus.invalidCode,
        message: '请先填写药名，再点「按药名查说明书」',
      );
    }

    final cacheKey = 'name:$keyword';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    // 第一步：搜索候选
    final searchOutcome = await _get(
      queryEndpoint,
      {'appkey': key, 'name': keyword},
      parseAsSearch: true,
    );
    if (!searchOutcome.ok) return searchOutcome;

    final medicineId = searchOutcome.result?.category;
    if (medicineId == null || medicineId.isEmpty) {
      return LookupOutcome(
        LookupStatus.notFound,
        message: '极速数据里没有匹配的药名：$keyword',
        hint: '换个通用名试试（去掉品牌、括号里的内容），或直接手填。',
      );
    }

    // 第二步：按 ID 查详情（说明书在这里）
    final outcome = await _get(
      detailEndpoint,
      {'appkey': key, 'medicine_id': medicineId},
    );
    if (outcome.ok) _cache[cacheKey] = outcome;
    return outcome;
  }

  /// 底层 GET 请求 + 统一错误分类。
  Future<LookupOutcome> _get(
    String endpoint,
    Map<String, String> params, {
    bool parseAsSearch = false,
  }) async {
    final uri = Uri.parse(endpoint).replace(queryParameters: params);
    try {
      final response = await _client.get(uri).timeout(timeout);
      final rawBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode != 200) {
        return LookupOutcome(
          LookupStatus.badResponse,
          message: '接口返回 HTTP ${response.statusCode}，可能被网络或代理拦截',
        );
      }
      return parseResponse(
        rawBody,
        apiName: apiName,
        parseAsSearch: parseAsSearch,
      );
    } on TimeoutException {
      return LookupOutcome(
        LookupStatus.timeout,
        message: '联网查询超时（${timeout.inSeconds} 秒），请检查网络后重试',
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

  /// 纯解析函数，便于单元测试直接喂 JSON。
  ///
  /// [parseAsSearch] 为 true 时结果放进 SearchResult：药名在 result.name，
  /// 第一个 medicine_id 借放在 category 字段供第二步使用。
  static LookupOutcome parseResponse(
    String rawBody, {
    String apiName = '极速数据药品库',
    bool parseAsSearch = false,
  }) {
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

    // 顶层错误码分类
    final error = classifyError(decoded, apiName: apiName);
    if (error != null) return error;

    dynamic result = decoded['result'];
    // result 有时是数组（同一个码多条），取第一条
    if (result is List) {
      if (result.isEmpty) {
        return const LookupOutcome(
          LookupStatus.notFound,
          message: '药品库里没有这条记录',
        );
      }
      result = result.first;
    }
    if (result is! Map) {
      return const LookupOutcome(
        LookupStatus.notFound,
        message: '药品库里没有这条记录（接口没有返回数据）',
      );
    }

    if (parseAsSearch) {
      final medicineId = _firstField(result, ['medicine_id', 'id', 'medicineId']);
      final name = _firstField(result, ['name', 'drug_name', 'generic_name']);
      if (name.isEmpty) {
        return const LookupOutcome(
          LookupStatus.notFound,
          message: '药品库里没有匹配的药名',
        );
      }
      return LookupOutcome.success(LookupResult(
        name: name,
        manufacturer: _firstField(result, ['manufacturer', 'company', 'factory']),
        category: medicineId,
      ));
    }

    final name = _firstField(result, [
      'name',
      'drug_name',
      'generic_name',
      'productName',
    ]);
    if (name.isEmpty) {
      return const LookupOutcome(
        LookupStatus.notFound,
        message: '药品库里没有这条记录（接口没有返回药名）',
      );
    }

    // 说明书全文：结构化字段 + 原始说明书，全部进搜索范围（需求④）
    final parts = <String>[];
    void add(String label, List<String> keys) {
      final value = _firstField(result as Map, keys);
      if (value.isEmpty || value == 'null') return;
      parts.add('$label：$value');
    }

    add('规格', ['spec', 'specification', 'package', 'pkg_spec']);
    add('剂型', ['type', 'dosage_form', 'drug_form', 'form']);
    add('适应症', ['indication', 'indications', 'disease', 'adaptation']);
    add('主要疾病', ['disease']);
    add('用法用量', ['usage', 'usage_dosage', 'dosage', 'usageAndDosage']);
    add('不良反应', ['adverse_reaction', 'adverseReaction', 'adverse']);
    add('禁忌', ['taboo', 'contraindication', 'contraindications']);
    add('注意事项', ['attention', 'note', 'notice', 'caution']);
    add('贮藏', ['storage', 'store']);
    add('有效期', ['validity_period', 'validity', 'expiry']);
    add('生产企业', ['manufacturer', 'company', 'factory', 'manuName']);
    add('批准文号', ['approval_num', 'approval', 'approvalNumber']);
    add('药品本位码', ['reference_code', 'referenceCode']);

    // 原始说明书字段（不同版本 key 不一样，都试一遍）
    final leafletRaw = _firstField(result, [
      'instruction',
      'instructions',
      'manual',
      'leaflet',
      'description',
      'drug_instruction',
      '说明书',
    ]);
    if (leafletRaw.isNotEmpty) parts.add(leafletRaw);

    final ingredient = _firstField(result, [
      'ingredients',
      'ingredient',
      'composition',
      'compositionAndContent',
      '主要成分',
    ]);

    final prescription = _firstField(result, ['prescription']);
    final category = prescription == '1'
        ? '处方药'
        : prescription == '2'
            ? 'OTC'
            : '';

    return LookupOutcome.success(LookupResult(
      name: name,
      ingredient: ingredient,
      leaflet: parts.join('\n'),
      category: category,
    ));
  }

  /// 按 jisuapi 官方错误码分类，返回 null 表示没有错误。
  static LookupOutcome? classifyError(Map decoded, {String apiName = '极速数据'}) {
    final status = decoded['status'];
    final msg = (decoded['msg'] ?? '').toString().trim();

    // status 可能是数字 0 或字符串 "0"
    if (status == null || status.toString() == '0') return null;

    final code = status.toString();
    final detail = msg.isEmpty ? '$apiName返回错误码 $code' : msg;

    switch (code) {
      case '101': // APPKEY为空或不存在
      case '102': // APPKEY已过期
        return LookupOutcome(
          LookupStatus.invalidKey,
          message: 'AppKey 无效或已过期：$detail',
          hint: '到 jisuapi.com 个人中心重新复制 AppKey，'
              '填到「设置 → 选项4」后点「测试连接」。',
        );
      case '103': // 无请求此数据权限
        return LookupOutcome(
          LookupStatus.notSubscribed,
          message: 'AppKey 没有这个接口的权限：$detail',
          hint: '到 jisuapi.com 确认已申请「药品信息」数据；'
              '新账号注册 14 天内可免费调试，之后需完成实名认证。',
        );
      case '104': // 请求超过次数限制
      case '106': // IP请求超过限制
        return LookupOutcome(
          LookupStatus.quota,
          message: '今日免费次数已用完：$detail',
          hint: '免费会员 100 次/天，每天 0 点重置；'
              '查过的药会缓存在本机，不会重复消耗。',
        );
      case '105': // IP被禁止
        return LookupOutcome(
          LookupStatus.network,
          message: '请求 IP 被限制：$detail',
          hint: '稍后再试，或检查是否用了代理 / VPN。',
        );
      case '107': // 接口维护中
      case '108': // 接口已停用
        return LookupOutcome(
          LookupStatus.unknown,
          message: '$apiName暂时不可用：$detail',
          hint: '接口维护中，可临时切回「选项3 本地药品库」。',
        );
      case '201': // 参数错误
      case '202': // 详情ID为空
        return const LookupOutcome(
          LookupStatus.badResponse,
          message: '请求参数有误，未发送有效查询',
        );
      case '203': // 没有信息
        return LookupOutcome(
          LookupStatus.notFound,
          message: msg.isEmpty ? '药品库里没有这条记录' : msg,
          hint: '可直接手动填写一次，之后扫码计件照常可用。',
        );
      default:
        // 其它非零：先看是不是「没有信息」类文案，否则当通用失败
        if (msg.contains('没有') || msg.contains('未收录') || msg.contains('无数据')) {
          return LookupOutcome(LookupStatus.notFound, message: detail);
        }
        return LookupOutcome(
          LookupStatus.badResponse,
          message: detail,
        );
    }
  }

  /// 从 Map 里按顺序取第一个非空字符串字段（兼容不同版本字段名）。
  static String _firstField(Map map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty && text != 'null') return text;
    }
    return '';
  }
}
