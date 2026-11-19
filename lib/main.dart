import 'package:flutter/material.dart';

import 'db/database_helper.dart';
import 'pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 提前打开本地 SQLite，避免首页第一帧卡顿；整个过程不需要联网。
  // 打开失败时给出可读的提示，而不是白屏。
  Object? startupError;
  try {
    await DatabaseHelper.instance.database;
  } catch (e) {
    startupError = e;
  }

  runApp(
    startupError == null
        ? const MedicineBoxApp()
        : _StartupErrorApp(message: '$startupError'),
  );
}

class MedicineBoxApp extends StatelessWidget {
  const MedicineBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '药箱小管家',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1D9E75),
        scaffoldBackgroundColor: const Color(0xFFF7FAF9),
      ),
      home: const HomePage(),
    );
  }
}

class _StartupErrorApp extends StatelessWidget {
  final String message;

  const _StartupErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '药箱小管家',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('启动失败')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('本地数据库打不开，药箱暂时无法使用。'),
              const SizedBox(height: 12),
              const Text('可以尝试重启 App；若仍然失败，请卸载重装（会清空已有记录）。'),
              const SizedBox(height: 16),
              SelectableText(
                message,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
