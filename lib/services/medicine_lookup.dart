/// 联网查询返回的结构化药品资料。
/// 只用来「预填」新建表单，用户仍可任意修改、补充或删掉。
class LookupResult {
  final String name;
  final String ingredient;
  final String leaflet;

  /// 接口给的分类原文，例如「OTC」「非药品」「中成药」。
  /// 66-24 的库里混着药妆健字产品，界面需要提示用户核对。
  final String category;

  /// 生产企业（部分数据源如极速数据的搜索结果会给出）。
  final String manufacturer;

  const LookupResult({
    required this.name,
    this.ingredient = '',
    this.leaflet = '',
    this.category = '',
    this.manufacturer = '',
  });

  bool get isNonMedicine => category.contains('非药品');
}

/// 查询结果的状态。区分状态是为了能告诉用户「到底为什么查不到」，
/// 而不是像旧版本那样一律 `return null`，让用户以为是自己填错了 Key。
enum LookupStatus {
  /// 成功。
  success,

  /// 还没填 Key，属于正常降级，不是错误。
  noKey,

  /// 编码格式不像条码，本地就拦下了。
  invalidCode,

  /// 接口正常返回，但库里没有这条数据。
  notFound,

  /// AppKey 无效、找不到应用、token 无效。
  invalidKey,

  /// 应用没有订购 / 没有被授权调用该接口（showapi -1006 / -1007 / -1008）。
  /// 注意：这不代表 Key 错了！Key 是对的，只是没开通这个接口。
  notSubscribed,

  /// 请求次数 / 余额 / 频率超限。
  quota,

  /// 网络不通（DNS、断网、代理）。
  network,

  /// 超时。
  timeout,

  /// 返回内容不是预期的 JSON 结构。
  badResponse,

  /// 其它未分类异常。
  unknown,
}

/// 查询的完整结果：要么带数据，要么带一句人话解释 + 一句「怎么办」。
class LookupOutcome {
  final LookupStatus status;
  final LookupResult? result;
  final String message;

  /// 可操作的下一步指引。旧版本没有这个字段，导致用户看到
  /// 「此应用无权调用本接口」却不知道要去订购接口。
  final String hint;

  const LookupOutcome(
    this.status, {
    this.result,
    this.message = '',
    this.hint = '',
  });

  factory LookupOutcome.success(LookupResult result) => LookupOutcome(
        LookupStatus.success,
        result: result,
        message: '查到：${result.name}',
      );

  bool get ok => status == LookupStatus.success && result != null;

  /// 界面统一用这个：原因 + 换行 + 怎么办。
  String get displayMessage => hint.isEmpty ? message : '$message\n$hint';
}

/// 查询适配器接口。
///
/// 【可扩展点】以后想换别家药品数据库，只要再写一个 implements 类，
/// 并在 lookup_service.dart 里换一行即可，页面和数据库都不用动。
abstract class MedicineLookup {
  /// 永远返回一个带原因的 outcome，不抛异常。
  /// 调用方据此决定「预填表单」还是「提示原因后手填」。
  Future<LookupOutcome> lookup(String code);
}
