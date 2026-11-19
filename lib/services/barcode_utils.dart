/// 条码相关的纯函数工具。
///
/// 抽成独立文件的原因有两个：
/// 1. 扫码页、查询服务都要用同一套判断，避免两处规则不一致；
/// 2. 纯函数可以在 `flutter test` 里直接单测，不需要相机、不需要网络。
class BarcodeUtils {
  BarcodeUtils._();

  /// 去掉空格、换行等所有空白（部分扫码枪会在末尾补回车）。
  static String normalize(String raw) => raw.replaceAll(RegExp(r'\s+'), '').trim();

  /// 是否是「可能是商品条码」的字符串：8~20 位纯数字。
  ///
  /// 这里刻意放宽：EAN-8(8)、UPC-A(12)、EAN-13(13)、GTIN-14(14)、
  /// 20 位药品追溯码都允许进入查询流程，交给服务端判断有没有收录。
  /// 旧版本只认 `69` 开头 13 位，导致 069 开头 14 位、进口药条码、
  /// 追溯码在本地就被拦掉，用户只看到「查不到」却不知道原因。
  static bool looksLikeBarcode(String code) =>
      RegExp(r'^\d{8,20}$').hasMatch(normalize(code));

  /// 国内商品条码（66-24 接口命中率最高的那一类）：
  /// 69 开头 13 位，或 069 开头 14 位（官方文档明确支持这两种）。
  static bool isChinaCommodityBarcode(String code) {
    final c = normalize(code);
    return RegExp(r'^(?:69\d{11}|069\d{11})$').hasMatch(c);
  }

  /// 20 位数字通常是药品追溯码，第三方接口基本查不到说明书。
  static bool isTraceabilityCode(String code) => normalize(code).length == 20;

  /// 给用户看的提示；null 表示没什么要提醒的。
  static String? tipFor(String code) {
    final c = normalize(code);
    if (c.isEmpty) return '编码为空';
    if (!looksLikeBarcode(c)) return '这串编码不像商品条码（应为 8~20 位数字），可能查不到资料';
    if (isTraceabilityCode(c)) {
      return '这是 20 位药品追溯码，第三方接口通常查不到说明书，请手动填一次';
    }
    if (!isChinaCommodityBarcode(c)) {
      return '非 69 开头的国内商品条码，接口可能未收录，查不到时请手动填写';
    }
    return null;
  }
}
