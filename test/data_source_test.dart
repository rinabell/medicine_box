import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_box/services/data_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('默认是本地库：装好就能用，不用 Key、不用联网', () async {
    expect(DataSourceSettings.defaultSource, DataSource.local);
    expect(await DataSourceSettings.current(), DataSource.local);
  });

  test('四种数据源的 id 可以无损往返', () {
    for (final source in DataSource.values) {
      expect(DataSourceSettings.fromId(DataSourceSettings.idOf(source)), source);
    }
    expect(DataSourceSettings.ids.length, 4);
  });

  test('未知或空 id 回退到默认数据源', () {
    expect(DataSourceSettings.fromId('unknown'), DataSource.local);
    expect(DataSourceSettings.fromId(null), DataSource.local);
  });

  test('选中结果会持久化到本机', () async {
    for (final source in DataSource.values) {
      SharedPreferences.setMockInitialValues({});
      await DataSourceSettings.save(source);
      expect(await DataSourceSettings.current(), source);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getString(DataSourceSettings.storageKey),
          DataSourceSettings.idOf(source));
    }
  });

  test('四种数据源都有标题、标签、说明和按钮文案', () {
    for (final source in DataSource.values) {
      expect(DataSourceSettings.titleOf(source).isNotEmpty, true);
      expect(DataSourceSettings.tagOf(source).isNotEmpty, true);
      expect(DataSourceSettings.descriptionOf(source).isNotEmpty, true);
      expect(DataSourceSettings.nameLookupLabel(source).isNotEmpty, true);
    }
  });

  test('标签如实说明收费与免费，避免用户再踩坑', () {
    expect(DataSourceSettings.tagOf(DataSource.showapi), contains('收费'));
    expect(DataSourceSettings.tagOf(DataSource.local), contains('免费'));
    expect(DataSourceSettings.descriptionOf(DataSource.web),
        contains('68api.com'));
    expect(DataSourceSettings.tagOf(DataSource.jisu), contains('100'));
    expect(DataSourceSettings.descriptionOf(DataSource.jisu),
        contains('medicine/detail'));
  });
}
