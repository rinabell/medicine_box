import 'dart:convert';

import 'medicine_lookup.dart';

/// showapi 网关层错误码 → App 内能看懂的状态 + 可操作指引。
///
/// 官方错误码表（公共返回参数，2026-11 核对）：
///   0 成功 / -1 系统调用错误 / -2 可调用次数或金额为 0 / -3 读取超时
///   -4 返回数据解析错误 / -5 DNS 解析错误 / -6 服务不存在或未上线
///   -7 网关资源不足 / -1000 系统维护 / -1004 appKey 验证有误
///   -1006 app 无权限调用接口 / -1007 没有订购套餐
///   -1008 服务商关闭对您的调用权限 / -1009 调用频率受限
///   -1010 找不到您的应用 / -1011 子授权 id 无效 / -1012 子授权过期
///   -1013 子授权 IP 受限 / -1014 token 权限无效
///
/// 【为什么单独抽这一层】旧版本只拿 `showapi_res_error` 的文案做关键词猜测，
/// 「此应用无权调用本接口」因为含「权限」被误判成「Key 无效」，
/// 用户于是一直换 Key，却永远修不好——真正要做的是去订购接口。
class ShowapiGateway {
  ShowapiGateway._();

  static const Map<int, String> descriptions = {
    -1: '系统调用错误',
    -2: '可调用次数或金额为 0',
    -3: '读取超时',
    -4: '服务端返回数据解析错误',
    -5: '后端服务器 DNS 解析错误',
    -6: '服务不存在或未上线',
    -7: 'API 创建者的网关资源不足',
    -1000: '系统维护中',
    -1004: 'AppKey 验证有误',
    -1006: '此应用无权调用本接口',
    -1007: '没有订购套餐',
    -1008: '服务商关闭了对您应用的调用权限',
    -1009: '调用频率受限',
    -1010: '找不到您的应用',
    -1011: '子授权 app_child_id 无效',
    -1012: '子授权已过期或失效',
    -1013: '子授权 IP 受限',
    -1014: 'token 权限无效',
  };

  static const Map<int, LookupStatus> statuses = {
    -2: LookupStatus.quota,
    -1004: LookupStatus.invalidKey,
    -1006: LookupStatus.notSubscribed,
    -1007: LookupStatus.notSubscribed,
    -1008: LookupStatus.notSubscribed,
    -1009: LookupStatus.quota,
    -1010: LookupStatus.invalidKey,
    -1011: LookupStatus.invalidKey,
    -1012: LookupStatus.invalidKey,
    -1013: LookupStatus.invalidKey,
    -1014: LookupStatus.invalidKey,
    -6: LookupStatus.unknown,
    -1000: LookupStatus.unknown,
  };

  /// 返回 null 表示 `showapi_res_code` 为 0（网关放行，可以继续解析业务体）。
  static LookupOutcome? envelopeError(
    Map<dynamic, dynamic> decoded, {
    String apiName = '该接口',
  }) {
    final raw = decoded['showapi_res_code'];
    if (raw == null) return null;
    final code = raw is int ? raw : int.tryParse(raw.toString());
    if (code == null || code == 0) return null;

    final rawError = (decoded['showapi_res_error'] ?? '').toString().trim();
    final serverText =
        rawError.isEmpty ? (descriptions[code] ?? '网关错误码 $code') : rawError;
    final status = statuses[code] ?? _fromText(serverText);

    return LookupOutcome(
      status,
      message: '[$code] $serverText',
      hint: hintFor(status, apiName),
    );
  }

  /// HTTP 状态码非 200 时，响应体里往往仍是一份带错误码的 JSON；
  /// 先尝试解析它，别把真实原因吞成一句「可能被代理拦截」。
  static LookupOutcome? tryParseErrorBody(
    String rawBody, {
    String apiName = '该接口',
  }) {
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) return envelopeError(decoded, apiName: apiName);
    } catch (_) {
      // 不是 JSON，交给调用方按 HTTP 状态处理
    }
    return null;
  }

  static String hintFor(LookupStatus status, String apiName) {
    switch (status) {
      case LookupStatus.notSubscribed:
        return '这不是 AppKey 填错了：网关已认出这个 Key，只是该应用还没开通 $apiName。'
            '请登录 showapi.com → 打开该接口详情页 → 订购/购买资源包'
            '（0 元档也要点一次购买），再到「控制台 → 我的应用」确认该应用已被授权；'
            '完成后回来重测。也可以先用免费的 1468 药品库按药名补全说明书。';
      case LookupStatus.invalidKey:
        return '请确认填的是 showapi 控制台「我的应用」页里的 AppKey（通常 32 位），'
            '不是 AppId / SecretKey / AppCode；复制时别带空格或花括号。';
      case LookupStatus.quota:
        return '到 showapi 控制台查看剩余次数与余额；若是调用频率超限，稍等几分钟再试。';
      default:
        return '';
    }
  }

  /// 未知错误码时按文案兜底，保持与旧版测试用例兼容。
  static LookupStatus _fromText(String text) {
    final t = text.toLowerCase();
    const quotaWords = ['余额', '次数', '频率', '上限', '超限', 'quota', 'limit'];
    const keyWords = ['密钥', 'key', '无效', '权限', '未开通', '认证', '失效', '无权'];
    if (quotaWords.any(t.contains)) return LookupStatus.quota;
    if (keyWords.any(t.contains)) return LookupStatus.invalidKey;
    return LookupStatus.invalidKey;
  }
}
