import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' show MockClient;
import 'package:medicine_box/services/medicine_lookup.dart';
import 'package:medicine_box/services/web_barcode_lookup.dart';

/// 选项2：参照 CSDN 文章的 68api HTML 结构 + 通用 JSON 接口。
void main() {
  group('buildUri - 模板渲染', () {
    test('默认模板把 {code} 替换成条码', () {
      final uri = WebBarcodeLookup().buildUri('6900388311184');
      expect(uri.toString(),
          'https://68api.com/barcode/6900388311184.html');
    });

    test('条码里的空格会被清理', () {
      final uri = WebBarcodeLookup().buildUri(' 6900 3883 11184 ');
      expect(uri.path, '/barcode/6900388311184.html');
    });

    test('自定义模板里的 {code} / {key} 都会替换', () {
      final lookup = WebBarcodeLookup(
        endpointTemplate: 'https://example.com/api?code={code}&key={key}',
        appKey: 'my key/001',
      );
      final uri = lookup.buildUri('6900388311184');
      expect(uri.queryParameters['code'], '6900388311184');
      expect(uri.queryParameters['key'], 'my key/001');
      // 模板里已指定 {key}，不应再自动附加 appKey
      expect(uri.queryParameters.containsKey('appKey'), false);
    });

    test('填了 Key 但模板没写 {key} → 自动附加 appKey 参数', () {
      final lookup = WebBarcodeLookup(
        endpointTemplate: 'https://example.com/barcode/{code}',
        appKey: 'abc123',
      );
      final uri = lookup.buildUri('6900388311184');
      expect(uri.queryParameters['appKey'], 'abc123');
    });

    test('留空 Key 不附加任何鉴权参数', () {
      final uri = WebBarcodeLookup().buildUri('6900388311184');
      expect(uri.queryParameters.isEmpty, true);
    });

    test('保留模板已有的查询参数', () {
      final lookup = WebBarcodeLookup(
        endpointTemplate: 'https://example.com/api?code={code}&from=app',
        appKey: 'k',
      );
      final uri = lookup.buildUri('6900388311184');
      expect(uri.queryParameters['from'], 'app');
      expect(uri.queryParameters['appKey'], 'k');
    });

    test('空模板回退到默认地址', () {
      final uri = WebBarcodeLookup(endpointTemplate: '  ').buildUri('6900388311184');
      expect(uri.host, '68api.com');
    });
  });

  group('parseResponse - JSON 接口', () {
    test('标准字段能解析出药名、成分和说明书', () {
      const body = '''
      {"code":1,"msg":"操作成功","data":{
        "barcode":"6921830106820",
        "goods_name":"布洛芬缓释胶囊",
        "component":"布洛芬",
        "spec":"0.3g*20粒",
        "company":"某某制药有限公司",
        "remark":"用于缓解轻至中度疼痛"
      }}''';
      final outcome = WebBarcodeLookup.parseResponse(body);
      expect(outcome.ok, true);
      expect(outcome.result!.name, '布洛芬缓释胶囊');
      expect(outcome.result!.ingredient, '布洛芬');
      expect(outcome.result!.leaflet, contains('规格：0.3g*20粒'));
      expect(outcome.result!.leaflet, contains('生产企业：某某制药有限公司'));
    });

    test('兼容 data 为数组、字段名用 trade_name / drugName', () {
      final outcome = WebBarcodeLookup.parseResponse(
          '{"data":[{"trade_name":"阿司匹林肠溶片","zycf":"乙酰水杨酸"}]}');
      expect(outcome.ok, true);
      expect(outcome.result!.name, '阿司匹林肠溶片');
      expect(outcome.result!.ingredient, '乙酰水杨酸');
    });

    test('顶层就是药品对象也能解析', () {
      final outcome = WebBarcodeLookup.parseResponse(
          '{"name":"维生素C片","ingredient":"维生素C","spec":"100mg"}');
      expect(outcome.ok, true);
      expect(outcome.result!.name, '维生素C片');
    });

    test('没有药名时把服务端 msg 带出来', () {
      final outcome = WebBarcodeLookup.parseResponse(
          '{"code":0,"msg":"条形码药品未收录","data":{}}');
      expect(outcome.status, LookupStatus.notFound);
      expect(outcome.message, contains('条形码药品未收录'));
      expect(outcome.ok, false);
    });

    test('showapi 风格网关错误码不被当成成功', () {
      final outcome = WebBarcodeLookup.parseResponse(
          '{"showapi_res_code":-1006,"showapi_res_error":"此应用无权调用本接口"}');
      expect(outcome.status, LookupStatus.badResponse);
      expect(outcome.message, contains('-1006'));
      expect(outcome.message, contains('此应用无权调用本接口'));
    });

    test('非法 JSON 给出明确原因', () {
      final outcome = WebBarcodeLookup.parseResponse('{oops');
      expect(outcome.status, LookupStatus.badResponse);
      expect(outcome.message, contains('不是合法 JSON'));
    });

    test('data 为 null 时不崩', () {
      final outcome = WebBarcodeLookup.parseResponse('{"data":null}');
      expect(outcome.status, LookupStatus.badResponse);
    });
  });

  group('parseResponse - HTML（CSDN 文章的 class 规则）', () {
    const csdnHtml = '''
    <html><head><title>阿司匹林肠溶片 - 68API</title></head><body>
      <div class="bar-1-right"><strong>阿司匹林肠溶片</strong></div>
      <div class="bar-1-list">
        规格：100mg*30片<br>
        批准文号：国药准字H12345678<br>
      </div>
      <div class="bar-2-2-2-1">拜耳医药保健有限公司</div>
    </body></html>''';

    test('从 bar-1-right > strong 取药名', () {
      final result = WebBarcodeLookup.parseHtml(csdnHtml);
      expect(result, isNotNull);
      expect(result!.name, '阿司匹林肠溶片');
    });

    test('bar-1-list 与 bar-2-2-2-1 内容进入说明书', () {
      final outcome = WebBarcodeLookup.parseResponse(csdnHtml);
      expect(outcome.ok, true);
      expect(outcome.result!.leaflet, contains('规格：100mg*30片'));
      expect(outcome.result!.leaflet, contains('拜耳医药保健有限公司'));
    });

    test('解析不到药名时给出可操作提示', () {
      final outcome = WebBarcodeLookup.parseResponse('<html><body><p>无数据</p></body></html>');
      expect(outcome.status, LookupStatus.notFound);
      expect(outcome.hint, contains('本地药品条码库'));
    });

    test('只有 title 时也能兜底取药名', () {
      final result = WebBarcodeLookup.parseHtml(
          '<html><head><title>布洛芬软胶囊 - 商品信息</title></head><body></body></html>');
      expect(result, isNotNull);
      expect(result!.name, contains('布洛芬软胶囊'));
    });
  });

  group('反爬 / 异常响应', () {
    test('滑块验证页会被识别并给出替代方案', () {
      const captcha = '<html><title>访问验证</title><body>您访问的频率过高，'
          '请拖动滑块验证后继续浏览。captcha68Api.init</body></html>';
      expect(WebBarcodeLookup.isCaptchaPage(captcha), true);
      final outcome = WebBarcodeLookup.parseResponse(captcha);
      expect(outcome.status, LookupStatus.badResponse);
      expect(outcome.message, contains('滑块验证'));
      expect(outcome.hint, contains('选项3'));
    });

    test('加密文本（既非 HTML 也非 JSON）不会被当成成功', () {
      final outcome = WebBarcodeLookup.parseResponse('a9f3kD8q...加密内容...');
      expect(outcome.status, LookupStatus.badResponse);
      expect(outcome.message, contains('加密'));
    });

    test('空响应', () {
      final outcome = WebBarcodeLookup.parseResponse('   ');
      expect(outcome.status, LookupStatus.badResponse);
      expect(outcome.message, contains('空内容'));
    });
  });

  group('lookup - 请求与错误分类', () {
    test('非法条码本地拦下，不发请求', () async {
      var called = false;
      final lookup = WebBarcodeLookup(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );
      final outcome = await lookup.lookup('ABC-不是条码');
      expect(outcome.status, LookupStatus.invalidCode);
      expect(called, false);
    });

    test('HTTP 200 + JSON 能走通完整链路', () async {
      final lookup = WebBarcodeLookup(
        client: MockClient((request) async {
          expect(request.url.path, contains('6900388311184'));
          return http.Response(
            '{"data":{"goods_name":"阿司匹林肠溶片","component":"乙酰水杨酸"}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final outcome = await lookup.lookup('6900388311184');
      expect(outcome.ok, true);
      expect(outcome.result!.name, '阿司匹林肠溶片');
    });

    test('HTTP 403 给出状态提示', () async {
      final lookup = WebBarcodeLookup(
        client: MockClient((_) async => http.Response('forbidden', 403)),
      );
      final outcome = await lookup.lookup('6900388311184');
      expect(outcome.status, LookupStatus.badResponse);
      expect(outcome.message, contains('403'));
    });

    test('接口地址不是完整 URL 时不会崩', () async {
      final lookup = WebBarcodeLookup(endpointTemplate: 'not-a-url');
      final outcome = await lookup.lookup('6900388311184');
      expect(outcome.status, LookupStatus.badResponse);
    });
  });
}
