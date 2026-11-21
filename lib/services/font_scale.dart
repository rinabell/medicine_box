import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 需求1：字体大小四档可调（1 小 / 2 标准 / 3 大 / 4 特大）。
///
/// 设计要点：
/// - 只有 4 档，不做无极调节；档位存本机，不联网、不登录。
/// - 2 档 = 当前字号（scale 1.0），默认 3 档 = 1.15（比现在大一两号）。
/// - 用 TextScaler 统一作用于全 App：所有页面、按钮、对话框一起放大，
///   不需要逐个改 Text 的 fontSize。
/// - 切换档位通过 [fontLevelNotifier] 通知 [FontScaleScope] 即时重建。
class FontScaleSettings {
  FontScaleSettings._();

  static const String storageKey = 'medicine_font_level';
  static const int defaultLevel = 3;
  static const List<int> levels = [1, 2, 3, 4];

  /// 档位 → 缩放系数。2 档保持现状，3 档默认大一号左右。
  static const Map<int, double> _factors = {
    1: 0.9,
    2: 1.0,
    3: 1.15,
    4: 1.3,
  };

  static int normalize(int? level) {
    if (level == null || !levels.contains(level)) return defaultLevel;
    return level;
  }

  static double factorFor(int level) => _factors[normalize(level)]!;

  static String labelOf(int level) {
    switch (normalize(level)) {
      case 1:
        return '1 · 小';
      case 2:
        return '2 · 标准';
      case 3:
        return '3 · 大（默认）';
      case 4:
        return '4 · 特大';
      default:
        return '3 · 大（默认）';
    }
  }

  static Future<int> current() async {
    final sp = await SharedPreferences.getInstance();
    return normalize(sp.getInt(storageKey));
  }

  static Future<void> save(int level) async {
    final value = normalize(level);
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(storageKey, value);
    fontLevelNotifier.value = value;
  }
}

/// 全局档位通知器。启动时 main() 会把读到的档位写进来；
/// 设置页切换时 [FontScaleSettings.save] 也会更新它。
final ValueNotifier<int> fontLevelNotifier =
    ValueNotifier<int>(FontScaleSettings.defaultLevel);

/// 把档位换算成 TextScaler 应用到整棵子树。
/// 放在 MaterialApp.builder 里，对所有路由（含对话框）生效。
class FontScaleScope extends StatelessWidget {
  final Widget child;

  const FontScaleScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: fontLevelNotifier,
      builder: (context, level, _) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(FontScaleSettings.factorFor(level)),
          ),
          child: child,
        );
      },
    );
  }
}
