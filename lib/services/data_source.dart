import 'package:shared_preferences/shared_preferences.dart';

/// 药品资料的数据源。设置页四选一，选中的只存在本机。
///
/// 【V1.3】用户反馈 showapi 条码接口是收费的，于是把「用哪套资料库」
/// 变成可选项，并默认切到完全离线、免费的本地药品条码库。
enum DataSource {
  /// 选项1：万维易源 showapi（66-24 条码付费 + 1468 药名免费）。
  showapi,

  /// 选项2：参照 CSDN 文章的 68api 网页查询方式，做成可配置 HTTP 接口。
  web,

  /// 选项3：Gitee 开源 barcode 项目整理的 4.7 万条药品条码本地库。
  local,

  /// 选项4：极速数据（jisuapi）药品库——免费会员 100 次/天，
  /// /medicine/detail 支持条码直查，且带成分、说明书等完整字段。
  jisu,
}

class DataSourceSettings {
  DataSourceSettings._();

  static const String storageKey = 'medicine_lookup_source';

  /// 默认本地库：装好就能扫码查，不用注册、不用填 Key、不用联网。
  static const DataSource defaultSource = DataSource.local;

  static const Map<DataSource, String> ids = {
    DataSource.showapi: 'showapi',
    DataSource.web: 'web',
    DataSource.local: 'local',
    DataSource.jisu: 'jisu',
  };

  static String idOf(DataSource source) => ids[source]!;

  static DataSource fromId(String? value) {
    for (final entry in ids.entries) {
      if (entry.value == value) return entry.key;
    }
    return defaultSource;
  }

  static Future<DataSource> current() async {
    final sp = await SharedPreferences.getInstance();
    return fromId(sp.getString(storageKey));
  }

  static Future<void> save(DataSource source) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(storageKey, idOf(source));
  }

  static String titleOf(DataSource source) {
    switch (source) {
      case DataSource.showapi:
        return '选项 1 · 万维易源 showapi';
      case DataSource.web:
        return '选项 2 · 自定义网页 / 接口查询';
      case DataSource.local:
        return '选项 3 · 本地药品条码库（离线）';
      case DataSource.jisu:
        return '选项 4 · 极速数据药品库（100次/天免费）';
    }
  }

  static String tagOf(DataSource source) {
    switch (source) {
      case DataSource.showapi:
        return '条码接口收费';
      case DataSource.web:
        return '免费但可能被反爬';
      case DataSource.local:
        return '推荐 · 完全免费';
      case DataSource.jisu:
        return '免费100次/天 · 带说明书';
    }
  }

  static String descriptionOf(DataSource source) {
    switch (source) {
      case DataSource.showapi:
        return '沿用 V1.2 的方案：66-24 用条码直查药名（需先购买资源包），'
            '1468 免费按药名补全说明书。需要填 AppKey。';
      case DataSource.web:
        return '参照 CSDN「通过条形码获取商品信息」的做法：请求 '
            'https://68api.com/barcode/{条码}.html 并解析页面里的药名、规格、厂家。'
            '可填自定义接口地址和 AppKey。';
      case DataSource.local:
        return '内置 Gitee 开源项目 barcode 整理的 47,722 条药品条码资料，'
            '含药名、成分、适应症、规格、厂家、批准文号和说明书全文。'
            '不联网、不用 Key、不消耗次数。';
      case DataSource.jisu:
        return '极速数据（jisuapi）药品库：免费会员每天 100 次，近 20 万种药。'
            '用 /medicine/detail 按条码直查，返回药名、成分、适应症、规格、'
            '厂家、批准文号和说明书。需注册填 AppKey；查过一次会缓存，'
            '同一条码不会重复消耗次数。';
    }
  }

  /// 编辑页「按药名补全」按钮的文案，随数据源变化。
  static String nameLookupLabel(DataSource source) {
    switch (source) {
      case DataSource.showapi:
        return '按药名查说明书（免费 1468 药品库）';
      case DataSource.web:
        return '按药名补全说明书';
      case DataSource.local:
        return '按药名查说明书（本地药品库）';
      case DataSource.jisu:
        return '按药名查说明书（极速数据药品库）';
    }
  }
}
