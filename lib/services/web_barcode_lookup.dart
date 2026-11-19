import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'barcode_utils.dart';
import 'medicine_lookup.dart';

/// 选项2：参照 CSDN 文章「通过条形码图片获取对应商品信息」实现的 HTTP 数据源。
///
/// 原文（https://adg.csdn.net/695258045b9f5f31781ba113.html）的做法：
///   GET https://68api.com/barcode/{条码}
///   BeautifulSoup 解析：
///     div.bar-1-right > strong   → 药名
///     div.bar-1-list             → 规格/成分等字段
///     div.bar-2-2-2-1           → 公司名
///
/// 【2026-11 实测】68api 现已加上滑块验证，且部分响应是加密文本，
/// 直接照抄爬虫拿不到药名。因此这里做成一个**可配置的通用适配器**：
///   - 接口地址可在二级页面改（占位符 {code} / {key}）；
///   - 可选 AppKey（模板里用 {key}，或自动附加 appKey 查询参数）；
///   - 同时支持 HTML 页面（按原文的 class 解析）和标准 JSON 接口；
///   - 遇到验证页 / 加密响应会明确告知原因，不再静默返回「查不到」。
/// 这样用户既能按原文接入 68api 的镜像/自建代理，也能换任意药品 JSON API。
class WebBarcodeLookup implements MedicineLookup {
  /// 站点实际详情路径是 /barcode/{code}.html（原文写的是无 .html 的路径）。
  static const String defaultEndpoint =
      'https://68api.com/barcode/{code}.html';

  static const String apiName = '自定义网页 / 接口查询';
  static const String demoCode = '6900388311184';
  static const Duration timeout = Duration(seconds: 12);

  final String endpointTemplate;
  final String appKey;
  final http.Client _client;

  WebBarcodeLookup({
    this.endpointTemplate = defaultEndpoint,
    this.appKey = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// 纯函数：把模板渲染成最终 URL，便于单元测试。
  Uri buildUri(String code) {
    final template = endpointTemplate.trim().isEmpty
        ? defaultEndpoint
        : endpointTemplate.trim();
    final normalized = BarcodeUtils.normalize(code);
    final key = appKey.trim();
    final rendered = template
        .replaceAll('{code}', Uri.encodeComponent(normalized))
        .replaceAll('{key}', Uri.encodeComponent(key));

    final uri = Uri.parse(rendered);
    if (key.isEmpty || template.contains('{key}')) return uri;

    // 没在模板里指定位置：按常见约定附加 appKey 查询参数。
    final params = Map<String, String>.from(uri.queryParameters);
    params['appKey'] = key;
    return uri.replace(queryParameters: params);
  }

  @override
  Future<LookupOutcome> lookup(String code) async {
    final normalized = BarcodeUtils.normalize(code);
    if (!BarcodeUtils.looksLikeBarcode(normalized)) {
      return LookupOutcome(
        LookupStatus.invalidCode,
        message: '“$code” 不像商品条码（应为 8~20 位数字）',
      );
    }

    late final Uri uri;
    try {
      uri = buildUri(normalized);
    } catch (e) {
      return LookupOutcome(
        LookupStatus.badResponse,
        message: '接口地址格式不对：$e',
        hint: '到「设置 → 选项2」检查接口地址，需以 http:// 或 https:// 开头。',
      );
    }
    if (!uri.hasScheme || !uri.hasAuthority) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '接口地址不是完整 URL',
        hint: '例如 https://68api.com/barcode/{code}.html',
      );
    }

    try {
      final response = await _client.get(uri, headers: _headers).timeout(timeout);
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (response.statusCode != 200) {
        return LookupOutcome(
          LookupStatus.badResponse,
          message: '接口返回 HTTP ${response.statusCode}',
          hint: '检查接口地址、AppKey 和网络；也可能被目标站点限流。',
        );
      }
      return parseResponse(body, contentType: response.headers['content-type'] ?? '');
    } on TimeoutException {
      return LookupOutcome(
        LookupStatus.timeout,
        message: '查询超时（${timeout.inSeconds} 秒）',
        hint: '稍后重试，或改用一个响应更快的接口地址。',
      );
    } on SocketException catch (e) {
      return LookupOutcome(
        LookupStatus.network,
        message: '网络不通：${e.message}',
        hint: '该数据源需要联网；断网时可在设置里切到「本地药品条码库」。',
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

  Map<String, String> get _headers => const {
        'user-agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        'accept': 'text/html,application/json;q=0.9,*/*;q=0.8',
        'accept-language': 'zh-CN,zh;q=0.9',
      };

  /// 纯解析函数：自动识别 验证页 / JSON / HTML。
  static LookupOutcome parseResponse(String body, {String contentType = ''}) {
    final trimmed = body.trimLeft();
    if (trimmed.isEmpty) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '接口返回了空内容',
      );
    }

    if (isCaptchaPage(body)) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '目标网站要求滑块验证，App 无法自动通过',
        hint: '68api 现在对频繁访问会弹验证。可以在「设置 → 选项2」换成'
            '自己的接口地址或自建代理；或者直接切到「选项3 本地药品条码库」，'
            '离线也能查 4.7 万条药品条码。',
      );
    }

    if (contentType.toLowerCase().contains('json') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[')) {
      return _parseJson(trimmed);
    }

    if (!body.contains('<')) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '返回的既不是 HTML 也不是 JSON（可能被站点加密或反爬）',
        hint: '68api 有些响应是加密文本。建议换 JSON 接口地址，'
            '或改用「选项3 本地药品条码库」。',
      );
    }

    final result = parseHtml(body);
    if (result == null || result.name.isEmpty) {
      return const LookupOutcome(
        LookupStatus.notFound,
        message: '页面里没解析出药名',
        hint: '页面结构可能变了；可在「设置 → 选项2」换成返回 JSON 的接口，'
            '或改用「选项3 本地药品条码库」。',
      );
    }
    return LookupOutcome.success(result);
  }

  static bool isCaptchaPage(String body) {
    const markers = [
      '访问验证',
      '请完成验证',
      '拖动滑块',
      '您访问的频率过高',
      'captcha68Api',
    ];
    return markers.any(body.contains);
  }

  /// 按 CSDN 原文的 class 规则解析 HTML；解析不到时退回 title/h1/og:title。
  static LookupResult? parseHtml(String htmlBody) {
    final name = _firstNonEmpty([
      _blockText(htmlBody, 'bar-1-right', tag: 'strong'),
      _metaContent(htmlBody, 'og:title'),
      _tagText(htmlBody, 'h1'),
      _tagText(htmlBody, 'title'),
    ]);
    if (name.isEmpty) return null;

    final parts = <String>[];
    void add(String label, String value) {
      final v = _clean(value);
      if (v.isNotEmpty && v != 'null') parts.add('$label：$v');
    }

    // div.bar-1-list 里的「字段名 / 值」列表
    final listBlock = _blockText(htmlBody, 'bar-1-list');
    if (listBlock.isNotEmpty) {
      for (final line in _clean(listBlock).split('\n')) {
        final text = line.trim();
        if (text.isEmpty || text == name) continue;
        parts.add(text);
      }
    }

    add('生产企业', _blockText(htmlBody, 'bar-2-2-2-1'));

    // 通用字段兜底：有些站点用 <dt>/<th> 标字段名
    for (final label in ['主要成份', '成分', '规格', '适应症', '用法用量', '批准文号']) {
      final value = _labeledValue(htmlBody, label);
      if (value.isNotEmpty) add(label, value);
    }

    return LookupResult(
      name: _clean(name),
      ingredient: _labeledValue(htmlBody, '主要成份').isEmpty
          ? _labeledValue(htmlBody, '成分')
          : _labeledValue(htmlBody, '主要成份'),
      leaflet: parts.join('\n'),
    );
  }

  static LookupOutcome _parseJson(String raw) {
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '接口返回的不是合法 JSON',
      );
    }
    if (decoded is! Map) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '接口返回结构异常',
      );
    }

    final gatewayCode = decoded['showapi_res_code'];
    if (gatewayCode != null && gatewayCode.toString() != '0') {
      return LookupOutcome(
        LookupStatus.badResponse,
        message: '接口网关返回错误码 $gatewayCode：'
            '${decoded['showapi_res_error'] ?? ''}',
      );
    }

    // 显式返回 data:null 视为「没有数据」，别把整个响应壳当药品对象。
    if (decoded.containsKey('data') && decoded['data'] == null) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '接口没有返回药品数据',
      );
    }

    dynamic payload = decoded['data'] ?? decoded['result'] ?? decoded;
    if (payload is List) {
      payload = payload.isEmpty ? null : payload.first;
    }
    if (payload is! Map) {
      return const LookupOutcome(
        LookupStatus.badResponse,
        message: '接口没有返回药品数据',
      );
    }
    final Map<dynamic, dynamic> data = payload;

    String field(String key) => (data[key] ?? '').toString().trim();
    String first(List<String> keys) {
      for (final key in keys) {
        final value = field(key);
        if (value.isNotEmpty && value != 'null') return value;
      }
      return '';
    }

    final name = first([
      'name',
      'goods_name',
      'trade_name',
      'productName',
      'drugName',
      'spmc',
      'tymc',
      'title',
    ]);
    if (name.isEmpty) {
      // 失败信息常在响应顶层（{"code":0,"msg":"未收录","data":{}}），
      // data 里取不到就回顶层找，别一律显示「没有返回药名」。
      final msg = first(['msg', 'message', 'remark']);
      final topMsg = ['msg', 'message', 'showapi_res_error']
          .map((key) => (decoded[key] ?? '').toString().trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      final text = msg.isNotEmpty ? msg : topMsg;
      return LookupOutcome(
        LookupStatus.notFound,
        message: text.isEmpty ? '接口没有返回药名' : text,
        hint: '确认条码正确、接口已授权；也可以切到「选项3 本地药品条码库」。',
      );
    }

    final parts = <String>[];
    void add(String label, String value) {
      if (value.isNotEmpty && value != 'null') parts.add('$label：$value');
    }

    add('品牌', first(['brand', 'pp']));
    add('规格', first(['spec', 'gg']));
    add('分类', first(['category_name', 'goods_type', 'category', 'fl']));
    add('生产企业', first(['company', 'manufacturer', 'manuName', 'manu']));
    add('批准文号', first(['approval', 'pzwh']));
    add('产地', field('origin_country'));
    add('适应症', first(['indication', 'purpose', 'syz']));
    add('用法用量', first(['dosage', 'yfyl']));
    add('备注', first(['remark', 'desc', 'description', 'instruction']));

    return LookupOutcome.success(LookupResult(
      name: name,
      ingredient: first(['component', 'ingredient', 'basis', 'zycf']),
      leaflet: parts.join('\n'),
      category: first(['type', 'class', 'category']),
    ));
  }

  // ---------- 极简 HTML 工具（不引入额外依赖） ----------

  static String _tagText(String source, String tag) {
    final match = RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>',
            caseSensitive: false)
        .firstMatch(source);
    return match == null ? '' : _clean(_stripTags(match.group(1)!));
  }

  static String _blockText(String source, String className, {String? tag}) {
    final match = RegExp(
            '<div[^>]*class="[^"]*$className[^"]*"[^>]*>([\\s\\S]*?)</div>',
            caseSensitive: false)
        .firstMatch(source);
    if (match == null) return '';
    var content = match.group(1)!;
    if (tag != null) {
      final inner = RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>',
              caseSensitive: false)
          .firstMatch(content);
      if (inner != null) content = inner.group(1)!;
    }
    return _clean(_stripTagsPreserveBreaks(content));
  }

  static String _metaContent(String source, String property) {
    final match = RegExp(
            '<meta[^>]*property="$property"[^>]*content="([^"]*)"[^>]*>',
            caseSensitive: false)
        .firstMatch(source);
    return match == null ? '' : _clean(match.group(1)!);
  }

  static String _labeledValue(String source, String label) {
    final match = RegExp(
            '$label[ \\t]*[:：]?[ \\t]*\\n?([^\\n]{1,200})',
            caseSensitive: false)
        .firstMatch(_stripTagsPreserveBreaks(source));
    return match == null ? '' : _clean(match.group(1)!);
  }

  static String _stripTags(String source) =>
      _clean(_stripTagsPreserveBreaks(source).replaceAll('\n', ' '));

  static String _stripTagsPreserveBreaks(String source) {
    return source
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(p|div|li|tr|td|h\d)>', caseSensitive: false),
            '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
  }

  static String _clean(String value) {
    final entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&lsquo;': '‘',
      '&rsquo;': '’',
    };
    var text = value;
    entities.forEach((key, replacement) {
      text = text.replaceAll(key, replacement);
    });
    text = text.replaceAll('\u00a0', ' ');
    return text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'\s{2,}'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
  }

  static String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final cleaned = _clean(value);
      if (cleaned.isNotEmpty && cleaned != 'null') return cleaned;
    }
    return '';
  }
}
