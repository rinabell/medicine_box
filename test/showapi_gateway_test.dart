import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/services/medicine_lookup.dart';
import 'package:medicine_box/services/showapi_gateway.dart';

Map<String, dynamic> envelope(int code, String error) => {
      'showapi_res_code': code,
      'showapi_res_error': error,
      'showapi_res_body': {},
    };

void main() {
  group('showapi 网关错误码', () {
    test('res_code 为 0 → 放行（返回 null）', () {
      expect(ShowapiGateway.envelopeError(envelope(0, '')), isNull);
    });

    test('缺少 res_code 字段 → 放行', () {
      expect(ShowapiGateway.envelopeError({'showapi_res_body': {}}), isNull);
    });

    test('-1006「此应用无权调用本接口」→ notSubscribed，不是 Key 无效', () {
      final o = ShowapiGateway.envelopeError(
          envelope(-1006, '此应用无权调用本接口'),
          apiName: '66-24 药品条码查询')!;
      expect(o.status, LookupStatus.notSubscribed);
      expect(o.message, contains('[-1006]'));
      expect(o.message, contains('此应用无权调用本接口'));
      expect(o.hint, contains('订购'));
      expect(o.hint, contains('66-24 药品条码查询'));
      expect(o.displayMessage, contains('订购'));
    });

    test('-1007 没有订购套餐 → notSubscribed', () {
      final o = ShowapiGateway.envelopeError(envelope(-1007, '没有订购套餐'))!;
      expect(o.status, LookupStatus.notSubscribed);
      expect(o.message, contains('没有订购套餐'));
    });

    test('-1008 服务商关闭权限 → notSubscribed', () {
      final o = ShowapiGateway.envelopeError(envelope(-1008, ''))!;
      expect(o.status, LookupStatus.notSubscribed);
      expect(o.message, contains('服务商关闭了对您应用的调用权限'));
    });

    test('-1004 appKey err → invalidKey，并给出核对指引', () {
      final o = ShowapiGateway.envelopeError(envelope(-1004, 'appKey err'))!;
      expect(o.status, LookupStatus.invalidKey);
      expect(o.hint, contains('我的应用'));
      expect(o.hint, contains('AppId'));
    });

    test('-1010 找不到应用 → invalidKey', () {
      expect(
        ShowapiGateway.envelopeError(envelope(-1010, ''))!.status,
        LookupStatus.invalidKey,
      );
    });

    test('-1014 token 无效 → invalidKey', () {
      expect(
        ShowapiGateway.envelopeError(envelope(-1014, ''))!.status,
        LookupStatus.invalidKey,
      );
    });

    test('-2 余额/次数为 0 → quota', () {
      final o = ShowapiGateway.envelopeError(envelope(-2, ''))!;
      expect(o.status, LookupStatus.quota);
      expect(o.hint, contains('余额'));
    });

    test('-1009 频率受限 → quota', () {
      expect(
        ShowapiGateway.envelopeError(envelope(-1009, ''))!.status,
        LookupStatus.quota,
      );
    });

    test('-6 服务未上线 → unknown', () {
      expect(
        ShowapiGateway.envelopeError(envelope(-6, ''))!.status,
        LookupStatus.unknown,
      );
    });

    test('-1000 系统维护 → unknown', () {
      expect(
        ShowapiGateway.envelopeError(envelope(-1000, ''))!.status,
        LookupStatus.unknown,
      );
    });

    test('未知错误码按文案兜底：Key 类 → invalidKey', () {
      final o = ShowapiGateway.envelopeError(envelope(401, 'appKey 无效'))!;
      expect(o.status, LookupStatus.invalidKey);
    });

    test('未知错误码按文案兜底：次数类 → quota', () {
      final o =
          ShowapiGateway.envelopeError(envelope(400, '调用次数已用完'))!;
      expect(o.status, LookupStatus.quota);
    });

    test('错误文案为空时用官方描述兜底', () {
      final o = ShowapiGateway.envelopeError(envelope(-3, ''))!;
      expect(o.message, contains('读取超时'));
    });

    test('res_code 是字符串数字也能识别', () {
      final o = ShowapiGateway.envelopeError({
        'showapi_res_code': '-1007',
        'showapi_res_error': '',
      })!;
      expect(o.status, LookupStatus.notSubscribed);
    });
  });

  group('官方错误码表完整性', () {
    test('18 个官方错误码都有中文描述', () {
      expect(ShowapiGateway.descriptions.length, 18);
      for (final code in const [
        -1, -2, -3, -4, -5, -6, -7, -1000, -1004, -1006, -1007, -1008,
        -1009, -1010, -1011, -1012, -1013, -1014
      ]) {
        expect(ShowapiGateway.descriptions[code], isNotNull,
            reason: '缺少错误码 $code 的描述');
      }
    });
  });

  group('HTTP 非 200 时的响应体解析', () {
    test('响应体是带错误码的 JSON → 精确分类', () {
      final o = ShowapiGateway.tryParseErrorBody(
        jsonEncode(envelope(-1007, '没有订购套餐')),
        apiName: '1468 药品信息查询',
      )!;
      expect(o.status, LookupStatus.notSubscribed);
      expect(o.hint, contains('1468'));
    });

    test('响应体是 HTML → 返回 null，交给调用方按 HTTP 状态处理', () {
      expect(
        ShowapiGateway.tryParseErrorBody('<html>502 Bad Gateway</html>'),
        isNull,
      );
    });
  });

  group('LookupOutcome.displayMessage', () {
    test('有 hint 时拼接原因与指引', () {
      const o = LookupOutcome(
        LookupStatus.notSubscribed,
        message: '[-1006] 此应用无权调用本接口',
        hint: '请去订购接口',
      );
      expect(o.displayMessage, '[-1006] 此应用无权调用本接口\n请去订购接口');
    });

    test('无 hint 时只显示原因', () {
      const o = LookupOutcome(LookupStatus.notFound, message: '未收录');
      expect(o.displayMessage, '未收录');
    });
  });
}
