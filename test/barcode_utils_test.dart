import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/services/barcode_utils.dart';

void main() {
  group('BarcodeUtils.normalize', () {
    test('去掉空格和换行（扫码枪常在末尾补回车）', () {
      expect(BarcodeUtils.normalize(' 6906 6181 8801 4\r\n'), '6906618188014');
    });

    test('空字符串仍为空', () {
      expect(BarcodeUtils.normalize('   '), '');
    });
  });

  group('BarcodeUtils.looksLikeBarcode', () {
    test('8 位 EAN-8 允许', () {
      expect(BarcodeUtils.looksLikeBarcode('12345678'), isTrue);
    });

    test('12 位 UPC-A 允许', () {
      expect(BarcodeUtils.looksLikeBarcode('012345678905'), isTrue);
    });

    test('13 位 EAN-13 允许', () {
      expect(BarcodeUtils.looksLikeBarcode('6906618188014'), isTrue);
    });

    test('14 位 GTIN-14 允许', () {
      expect(BarcodeUtils.looksLikeBarcode('06906618188014'), isTrue);
    });

    test('20 位药品追溯码也放行（交服务端判断）', () {
      expect(BarcodeUtils.looksLikeBarcode('81234567890123456789'), isTrue);
    });

    test('7 位太短', () {
      expect(BarcodeUtils.looksLikeBarcode('1234567'), isFalse);
    });

    test('21 位太长', () {
      expect(BarcodeUtils.looksLikeBarcode('123456789012345678901'), isFalse);
    });

    test('含字母不是条码', () {
      expect(BarcodeUtils.looksLikeBarcode('ABC12345678'), isFalse);
    });

    test('空串不是条码', () {
      expect(BarcodeUtils.looksLikeBarcode(''), isFalse);
    });
  });

  group('BarcodeUtils.isChinaCommodityBarcode', () {
    test('69 开头 13 位', () {
      expect(BarcodeUtils.isChinaCommodityBarcode('6906618188014'), isTrue);
    });

    test('069 开头 14 位（官方文档明确支持）', () {
      expect(BarcodeUtils.isChinaCommodityBarcode('06906618188014'), isTrue);
    });

    test('其它前缀不算国内商品条码', () {
      expect(BarcodeUtils.isChinaCommodityBarcode('4006381333931'), isFalse);
    });

    test('20 位追溯码不算国内商品条码', () {
      expect(BarcodeUtils.isChinaCommodityBarcode('81234567890123456789'),
          isFalse);
    });
  });

  group('BarcodeUtils.tipFor', () {
    test('20 位追溯码会提示需要手填', () {
      final tip = BarcodeUtils.tipFor('81234567890123456789');
      expect(tip, isNotNull);
      expect(tip, contains('追溯'));
    });

    test('非 69 开头条码提示可能未收录', () {
      final tip = BarcodeUtils.tipFor('4006381333931');
      expect(tip, isNotNull);
      expect(tip, contains('69'));
    });

    test('标准国内商品条码没有额外提示', () {
      expect(BarcodeUtils.tipFor('6906618188014'), isNull);
    });

    test('非法输入会提示格式问题', () {
      expect(BarcodeUtils.tipFor('ABC'), contains('8~20'));
    });
  });
}
