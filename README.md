# 药箱小管家（medicine_box）

一个用 Flutter 开发的安卓家庭药箱工具：扫码录药、同码计件、自定义备注，并可按药名 / 成分 / 说明书搜索。默认数据全部保存在手机本地，无需登录账号。

当前版本：`1.5.0+7`

## 功能

- 调用相机扫描二维码或 EAN-13 商品条码，快速建档；相机不可用时可手动输入编码或药名
- 同一条码重复扫描自动累加件数
- 每种药可写自定义文字备注
- 药名、成分、说明书、备注、条码均支持模糊 / 精准搜索
- 线上查不到时自动退回手动填写，不影响计件和后续搜索
- **保质期管理**：扫码后弹窗录入年月日（可跳过），同一药可累加多个日期；首页数量旁只显示最接近今天的一条。过期显示红色加粗，过期药优先排列，且过期越久越靠前
- **字体大小可调**：设置页四档（1 / 2 / 3 / 4）切换，默认 3 档（比旧版大一两号）

## 四种药品资料来源

在「设置」页切换，选中结果只保存在本机。选项 1 / 2 / 4 的 AppKey 和测试按钮都收在二级配置页里。

| 选项 | 来源 | 特点 |
| --- | --- | --- |
| 1 | showapi 66-24 / 1468 | 字段最全（成分、说明书、禁忌等）；66-24 需先在官网点一次 **0 元订购**，否则会报「无权调用」 |
| 2 | 自定义网页 / JSON 接口 | 参照 68api 方案，可自定义接口地址和参数，适合自行接入其他服务 |
| 3 | 内置本地条码库（默认） | 47,722 条药品资料，离线、免费、秒查；首次使用需解压约 87 MB 数据 |
| 4 | 极速数据 jisuapi | `/medicine/detail` 支持条码直查完整说明书，免费 100 次/天，需注册获取 AppKey |

查过的条码 / 药名会缓存在本地 SQLite，同一条不会重复消耗在线额度。

## 快速开始

需要 Flutter 3.x、Dart 3.x、JDK 17 和 Android SDK。

```bash
flutter pub get
flutter analyze
flutter test
flutter run
flutter build apk --release
```

产物位于 `build/app/outputs/flutter-apk/app-release.apk`。

## 数据说明

- 内置库整理自 Gitee 开源项目 [`yzhh/barcode`](https://gitee.com/yzhh/barcode)，以分片形式放在 `assets/catalog/`，运行时拼接到 App 私有目录。开源库覆盖不全，也可能混入保健食品、药妆等非药品条目。
- `assets/catalog/medicine_supplement.json` 是人工核实的补充条目，可继续扩充。
- 药品信息仅供参考，实际用药请以药品实物说明书和医生 / 药师建议为准。

## 目录结构

```text
lib/db/         药箱 SQLite、搜索 SQL、同码计件、保质期迁移
lib/services/   数据源配置、本地库与三种在线查询适配器、字体档位、保质期算法
lib/widgets/    保质期录入弹窗
lib/pages/      首页、扫码、编辑、设置、二级配置页
assets/catalog/ 本地药品库分片与补充条目
test/           单元测试与 Widget 测试（281 个用例）
```

## 隐私与打包注意

- 无账号体系；AppKey 只存在本机 `shared_preferences`，药品档案存在本机 SQLite。
- 只有选择了在线数据源，扫码时才会把条码或药名发给对应服务商。
- 请勿提交 `android/key.properties` 和 `*.jks` 等签名文件；示例配置见 `android/key.properties.example`。
