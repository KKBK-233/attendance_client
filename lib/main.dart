import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  runApp(const AttendanceApp());
}

// ======================== 数据模型 ========================

class AppConfig {
  AppConfig({
    this.cookie = '',
    this.studentId = '230100859',
    this.planWid = 'd11fdc3bb4614ccf9a3093497f8049ce',
    this.area = '广东省, 佛山市, 南海区',
    this.address = '广东省佛山市南海区桂城街道桂澜中路23号金域国际花园一期1座2幢706房',
    this.remark = '忘记打卡',
    String? month,
    String? endMonth,
    this.workPattern = 'five',
    this.delayMs = 1500,
  }) : month = month ?? monthOf(DateTime.now()),
       endMonth = endMonth ?? month ?? monthOf(DateTime.now());

  String cookie;
  String studentId;
  String planWid;
  String area;
  String address;
  String remark;
  String month;
  String endMonth;
  String workPattern;
  int delayMs;

  static AppConfig fromJson(Map<String, dynamic> json) {
    String nonEmpty(String key, String fallback) {
      final value = json[key]?.toString().trim() ?? '';
      return value.isEmpty ? fallback : value;
    }

    return AppConfig(
      cookie: json['cookie']?.toString() ?? '',
      studentId: nonEmpty('studentId', '230100859'),
      planWid: nonEmpty('planWid', 'd11fdc3bb4614ccf9a3093497f8049ce'),
      area: nonEmpty('area', '广东省, 佛山市, 南海区'),
      address: nonEmpty('address', '广东省佛山市南海区桂城街道桂澜中路23号金域国际花园一期1座2幢706房'),
      remark: nonEmpty('remark', '忘记打卡'),
      month: nonEmpty('month', monthOf(DateTime.now())),
      endMonth: nonEmpty(
        'endMonth',
        json['month']?.toString() ?? monthOf(DateTime.now()),
      ),
      workPattern: nonEmpty('workPattern', 'five'),
      delayMs: int.tryParse(json['delayMs']?.toString() ?? '') ?? 1500,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'cookie': cookie,
      'studentId': studentId,
      'planWid': planWid,
      'area': area,
      'address': address,
      'remark': remark,
      'month': month,
      'endMonth': endMonth,
      'workPattern': workPattern,
      'delayMs': delayMs,
    };
  }
}

class AttendanceDay {
  AttendanceDay({
    required this.date,
    required this.weekday,
    this.selected = true,
    this.signed = false,
    this.future = false,
    this.holiday = false,
    this.weekend = false,
    this.adjustedWorkday = false,
    this.disabled = false,
  });

  final String date;
  final String weekday;
  bool selected;
  bool signed;
  bool future;
  bool holiday;
  bool weekend;
  bool adjustedWorkday;
  bool disabled;
  SubmitResult? result;
}

class SubmitResult {
  SubmitResult({
    required this.success,
    required this.message,
    this.statusCode = 0,
  });

  final bool success;
  final String message;
  final int statusCode;
}

class InternshipPlan {
  InternshipPlan({
    required this.wid,
    required this.name,
    required this.schoolYear,
  });

  final String wid;
  final String name;
  final String schoolYear;
}

class HolidayData {
  HolidayData({
    required this.holidays,
    required this.adjustedWorkdays,
    required this.source,
  });

  final Set<String> holidays;
  final Set<String> adjustedWorkdays;
  final String source;
}

// ======================== 本地配置 ========================

class ConfigStore {
  static Future<File> _configFile() async {
    final base =
        Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        (Platform.isAndroid ? Directory.systemTemp.path : null) ??
        Directory.current.path;
    final dir = Directory('$base\\SzpuAttendanceClient');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}\\config.json');
  }

  static Future<AppConfig> load() async {
    final file = await _configFile();
    if (!await file.exists()) {
      return AppConfig();
    }
    final raw = await file.readAsString();
    return AppConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<String> save(AppConfig config) async {
    final file = await _configFile();
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
    return file.path;
  }
}

class BrowserCookieCapture {
  BrowserCookieCapture._();

  static const loginUrl =
      'https://authserver-443.vpn5.szpu.edu.cn/authserver/login?type=dynamicLogin&service=https%3A%2F%2Fjwxt-443.vpn5.szpu.edu.cn%2Fjwapp%2Fsys%2FxsdgsxbmMobile%2F*default%2Findex.do%23%2Fckqdxx';

  static Future<File?> findScript() async {
    final starts = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];

    for (final start in starts) {
      var dir = start;
      for (var i = 0; i < 8; i++) {
        final direct = File('${dir.path}\\capture_auth_cookies.js');
        final parent = File('${dir.path}\\..\\capture_auth_cookies.js');
        if (await direct.exists()) return direct;
        if (await parent.exists()) return parent;
        final next = dir.parent;
        if (next.path == dir.path) break;
        dir = next;
      }
    }
    return null;
  }

  static Future<Directory> outputDir() async {
    final base =
        Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
    final dir = Directory('$base\\SzpuAttendanceClient\\browser_cookies');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String> readJwCookie(Directory outDir) async {
    final file = File('${outDir.path}\\jwxt-cookie-header.txt');
    if (!await file.exists()) {
      throw StateError('未找到教务 Cookie 文件：${file.path}');
    }
    final cookie = (await file.readAsString()).trim();
    if (cookie.isEmpty) {
      throw StateError('教务 Cookie 为空，请确认浏览器已跳转到教务系统页面');
    }
    return cookie;
  }
}

class LocationService {
  LocationService._();

  static Future<Map<String, String>> fetchByIp() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(
        Uri.parse('http://ip-api.com/json/?lang=zh-CN'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final text = await response.transform(utf8.decoder).join();
      final json = jsonDecode(text) as Map<String, dynamic>;
      if (json['status'] != 'success') {
        throw StateError(json['message']?.toString() ?? '定位接口返回失败');
      }

      final province = json['regionName']?.toString() ?? '';
      final city = json['city']?.toString() ?? '';
      final country = json['country']?.toString() ?? '';
      final isp = json['isp']?.toString() ?? '';
      final areaParts = [
        if (country == '中国' && province.isNotEmpty) province else country,
        if (city.isNotEmpty) city,
      ].where((part) => part.isNotEmpty).toList();

      return {
        'area': areaParts.join(', '),
        'address': areaParts.join('') + (isp.isEmpty ? '' : ' $isp'),
      };
    } finally {
      client.close(force: true);
    }
  }
}

// ======================== 教务接口 ========================

class AttendanceApi {
  AttendanceApi(this.config);

  final AppConfig config;

  static const _host = 'jwxt-443.vpn5.szpu.edu.cn';
  static const _base = 'https://$_host/jwapp/sys/xsdgsxbmMobile/modules';
  static const _holidayBase = 'https://timor.tech/api/holiday/year';

  Future<HolidayData> fetchHolidayData(int year) async {
    try {
      final raw = await _requestText(
        Uri.parse('$_holidayBase/$year?type=Y'),
        method: 'GET',
        includeCookie: false,
      );
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['code'] != 0) {
        throw const FormatException('节假日接口返回异常');
      }

      final holidays = <String>{};
      final adjusted = <String>{};
      final entries = (json['holiday'] as Map?) ?? {};

      for (final entry in entries.entries) {
        final key = entry.key.toString();
        final info = Map<String, dynamic>.from(entry.value as Map);
        final date = '$year-$key';
        final isHoliday = info['holiday'] == true;

        if (isHoliday) {
          holidays.add(date);
        } else {
          final parts = key.split('-').map(int.parse).toList();
          final day = DateTime(year, parts[0], parts[1]).weekday;
          if (day == DateTime.saturday || day == DateTime.sunday) {
            adjusted.add(date);
          }
        }
      }

      return HolidayData(
        holidays: holidays,
        adjustedWorkdays: adjusted,
        source: '在线节假日数据',
      );
    } catch (error) {
      return HolidayData(
        holidays: <String>{},
        adjustedWorkdays: <String>{},
        source: '周末规则，节假日接口不可用：$error',
      );
    }
  }

  Future<Set<String>> fetchSignedDates() async {
    _requireCookie();
    _requirePlanWid();

    final body = _encodeForm({'JHXSWID': config.planWid, '*order': '+QDSJ'});

    final raw = await _requestText(
      Uri.parse('$_base/ckqdxx/cxxsqd.do'),
      method: 'POST',
      body: body,
      referer:
          'https://$_host/jwapp/sys/xsdgsxbmMobile/*default/index.do#/ckqdxx',
    );

    final data = jsonDecode(raw) as Map<String, dynamic>;
    final rows =
        (((data['datas'] as Map?)?['cxxsqd'] as Map?)?['rows'] as List?) ?? [];
    final signed = <String>{};

    for (final row in rows) {
      if (row is! Map) continue;
      final status = row['QDZT']?.toString();
      final time = row['QDSJ']?.toString() ?? '';
      if (time.length < 10) continue;

      if (status == '1' || status == 'bqtg' || status == 'bqsh') {
        signed.add(time.substring(0, 10));
      }
    }

    return signed;
  }

  Future<InternshipPlan?> fetchLatestPlan() async {
    _requireCookie();
    if (config.studentId.trim().isEmpty) {
      throw StateError('请先填写学号');
    }

    final body = _encodeForm({
      'XH': config.studentId.trim(),
      '*order': '-XNXQDM',
    });

    final raw = await _requestText(
      Uri.parse('$_base/ckqdxx/cxxssxxx.do'),
      method: 'POST',
      body: body,
      referer:
          'https://$_host/jwapp/sys/xsdgsxbmMobile/*default/index.do#/ckqdxx',
    );

    final data = jsonDecode(raw) as Map<String, dynamic>;
    final rows =
        (((data['datas'] as Map?)?['cxxssxxx'] as Map?)?['rows'] as List?) ??
        [];
    if (rows.isEmpty || rows.first is! Map) return null;

    final row = rows.first as Map;
    final wid = row['WID']?.toString() ?? '';
    if (wid.isEmpty) return null;

    return InternshipPlan(
      wid: wid,
      name: row['JHMC']?.toString() ?? '未命名计划',
      schoolYear: row['XNDM']?.toString() ?? '',
    );
  }

  Future<SubmitResult> submitRemedy(String date) async {
    _requireCookie();
    _requirePlanWid();

    final form = {
      'QDSZD': config.area,
      'QDXXDZ': config.address,
      'JHXSWID': config.planWid,
      'QDZT': 'bqsh',
      'BY1': config.remark,
      'BY3': nowInChina(),
      'XH': config.studentId,
      'WID': '',
      'QDSJ': '$date 23:00:00',
    };

    final body = _encodeForm({
      'param': jsonEncode([form]),
    });

    final raw = await _requestText(
      Uri.parse('$_base/bqsq/bcxsqdxx.do'),
      method: 'POST',
      body: body,
      referer:
          'https://$_host/jwapp/sys/xsdgsxbmMobile/*default/index.do#/bqsq?JHXSWID=${config.planWid}&BQRQ=$date',
    );

    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final ext =
          (((data['datas'] as Map?)?['bcxsqdxx'] as Map?)?['extParams']
              as Map?) ??
          {};
      final code = ext['code']?.toString();
      final msg = ext['msg']?.toString() ?? raw;
      return SubmitResult(success: code == '1', message: msg);
    } catch (_) {
      return SubmitResult(success: false, message: raw.take(160));
    }
  }

  Future<String> _requestText(
    Uri uri, {
    required String method,
    String? body,
    String? referer,
    bool includeCookie = true,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      final request = method == 'POST'
          ? await client.postUrl(uri)
          : await client.getUrl(uri);
      request.followRedirects = false;

      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/javascript, */*; q=0.01',
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      );
      request.headers.set('X-Requested-With', 'XMLHttpRequest');

      if (includeCookie) {
        request.headers.set(HttpHeaders.cookieHeader, config.cookie.trim());
        request.headers.set('Origin', 'https://$_host');
      }
      if (referer != null) {
        request.headers.set(HttpHeaders.refererHeader, referer);
      }
      if (body != null) {
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded; charset=UTF-8',
        );
        final bytes = utf8.encode(body);
        request.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
        request.add(bytes);
      }

      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      final text = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        final locationText = location == null ? '' : '；Location: $location';
        throw HttpException(
          'HTTP ${response.statusCode}$locationText；${text.take(160)}',
          uri: uri,
        );
      }

      return text;
    } finally {
      client.close(force: true);
    }
  }

  void _requireCookie() {
    if (config.cookie.trim().isEmpty) {
      throw StateError('请先填写教务系统 Cookie');
    }
  }

  void _requirePlanWid() {
    if (config.planWid.trim().isEmpty) {
      throw StateError('请先填写或自动获取实习计划 WID');
    }
  }

  String _encodeForm(Map<String, String> fields) {
    return fields.entries
        .map((entry) {
          final key = Uri.encodeQueryComponent(entry.key);
          final value = Uri.encodeQueryComponent(entry.value);
          return '$key=$value';
        })
        .join('&');
  }
}

// ======================== 应用界面 ========================

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '深职院考勤补签',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff2563eb),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f7f9),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const AttendanceHomePage(),
    );
  }
}

class AttendanceHomePage extends StatefulWidget {
  const AttendanceHomePage({super.key});

  @override
  State<AttendanceHomePage> createState() => _AttendanceHomePageState();
}

class _AttendanceHomePageState extends State<AttendanceHomePage> {
  final _cookieCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  final _planWidCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  final _monthCtrl = TextEditingController();
  final _endMonthCtrl = TextEditingController();
  final _delayCtrl = TextEditingController();

  List<AttendanceDay> _days = [];
  String _status = '正在读取本地配置...';
  String _holidaySource = '';
  String _workPattern = 'five';
  bool _busy = false;
  Process? _captureProcess;
  Directory? _captureOutDir;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _cookieCtrl.dispose();
    _studentIdCtrl.dispose();
    _planWidCtrl.dispose();
    _areaCtrl.dispose();
    _addressCtrl.dispose();
    _remarkCtrl.dispose();
    _monthCtrl.dispose();
    _endMonthCtrl.dispose();
    _delayCtrl.dispose();
    _captureProcess?.kill();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final config = await ConfigStore.load();
    _applyConfig(config);
    setState(() {
      _status = '配置已读取。填写 Cookie 后可以查询缺签日期。';
    });
  }

  void _applyConfig(AppConfig config) {
    _cookieCtrl.text = config.cookie;
    _studentIdCtrl.text = config.studentId;
    _planWidCtrl.text = config.planWid;
    _areaCtrl.text = config.area;
    _addressCtrl.text = config.address;
    _remarkCtrl.text = config.remark;
    _monthCtrl.text = config.month;
    _endMonthCtrl.text = config.endMonth;
    _delayCtrl.text = config.delayMs.toString();
    _workPattern = config.workPattern;
  }

  AppConfig _readConfig() {
    return AppConfig(
      cookie: _cookieCtrl.text.trim(),
      studentId: _studentIdCtrl.text.trim(),
      planWid: _planWidCtrl.text.trim(),
      area: _areaCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      remark: _remarkCtrl.text.trim(),
      month: _monthCtrl.text.trim(),
      endMonth: _endMonthCtrl.text.trim(),
      workPattern: _workPattern,
      delayMs: int.tryParse(_delayCtrl.text.trim()) ?? 1500,
    );
  }

  Future<void> _saveConfig() async {
    final config = _readConfig();
    final path = await ConfigStore.save(config);
    setState(() {
      _status = '配置已保存：$path';
    });
  }

  Future<void> _fetchLatestPlan() async {
    final config = _readConfig();
    setState(() {
      _busy = true;
      _status = '正在获取最新实习计划...';
    });

    try {
      final plan = await AttendanceApi(config).fetchLatestPlan();
      if (plan == null) {
        setState(() => _status = '没有查到实习计划，请确认 Cookie 和学号是否正确。');
        return;
      }

      _planWidCtrl.text = plan.wid;
      await _saveConfig();
      setState(() {
        _status = '已获取实习计划：${plan.name} ${plan.schoolYear}';
      });
    } catch (error) {
      setState(() => _status = '获取实习计划失败：$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _queryMissingDays() async {
    final config = _readConfig();
    final startMonth = parseMonth(config.month);
    final endMonth = parseMonth(config.endMonth);
    if (startMonth == null || endMonth == null) {
      setState(() => _status = '月份格式应为 YYYY-MM，例如 2026-05');
      return;
    }
    if (monthIndex(startMonth) > monthIndex(endMonth)) {
      setState(() => _status = '开始月份不能晚于结束月份');
      return;
    }

    setState(() {
      _busy = true;
      _days = [];
      _status = '正在查询签到记录和节假日数据...';
    });

    try {
      await ConfigStore.save(config);
      final api = AttendanceApi(config);
      final holidays = <int, HolidayData>{};
      for (var year = startMonth.year; year <= endMonth.year; year++) {
        holidays[year] = await api.fetchHolidayData(year);
      }
      final signedDates = await api.fetchSignedDates();
      final days = _buildDaysForRange(
        startMonth,
        endMonth,
        holidays,
        signedDates,
        config.workPattern,
      );

      setState(() {
        _days = days;
        _holidaySource = holidays.values
            .map((holiday) => holiday.source)
            .toSet()
            .join('；');
        _status = '查询完成：列出 ${days.length} 个过去日期，可按实际工作日手动勾选。';
      });
    } catch (error) {
      setState(() => _status = '查询失败：$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  List<AttendanceDay> _buildDaysForRange(
    ParsedMonth startMonth,
    ParsedMonth endMonth,
    Map<int, HolidayData> holidays,
    Set<String> signedDates,
    String workPattern,
  ) {
    final result = <AttendanceDay>[];
    final today = dateOnly(DateTime.now());

    for (final month in monthsBetween(startMonth, endMonth)) {
      final holiday =
          holidays[month.year] ??
          HolidayData(holidays: {}, adjustedWorkdays: {}, source: '周末规则');
      final lastDay = DateTime(month.year, month.month + 1, 0).day;

      for (var day = 1; day <= lastDay; day++) {
        final date = DateTime(month.year, month.month, day);
        final dateStr = formatDate(date);
        final isFuture = !date.isBefore(today);
        final isSigned = signedDates.contains(dateStr);
        if (isFuture || isSigned) continue;

        final isHoliday = holiday.holidays.contains(dateStr);
        final isAdjusted = holiday.adjustedWorkdays.contains(dateStr);
        final isWeekend =
            date.weekday == DateTime.saturday ||
            date.weekday == DateTime.sunday;
        final selected = _defaultSelected(
          date,
          isHoliday: isHoliday,
          isAdjusted: isAdjusted,
          workPattern: workPattern,
        );

        result.add(
          AttendanceDay(
            date: dateStr,
            weekday: weekdayLabel(date),
            selected: selected,
            signed: isSigned,
            future: isFuture,
            holiday: isHoliday,
            weekend: isWeekend,
            adjustedWorkday: isAdjusted,
          ),
        );
      }
    }

    return result;
  }

  bool _defaultSelected(
    DateTime date, {
    required bool isHoliday,
    required bool isAdjusted,
    required String workPattern,
  }) {
    if (workPattern == 'all') return true;
    if (isAdjusted) return true;
    if (isHoliday) return false;

    if (workPattern == 'six') {
      return date.weekday >= DateTime.monday &&
          date.weekday <= DateTime.saturday;
    }

    return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
  }

  Future<void> _startBrowserCookieCapture() async {
    if (_captureProcess != null) {
      setState(() => _status = '浏览器登录流程已启动，请完成登录后点击“读取 Cookie”。');
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在启动浏览器登录流程...';
    });

    try {
      final script = await BrowserCookieCapture.findScript();
      if (script == null) {
        throw StateError('未找到 capture_auth_cookies.js');
      }

      final outDir = await BrowserCookieCapture.outputDir();
      _captureOutDir = outDir;

      final process = await Process.start('node', [
        script.path,
        '--out',
        outDir.path,
        '--url',
        BrowserCookieCapture.loginUrl,
      ], workingDirectory: script.parent.path);

      _captureProcess = process;
      process.stdout.transform(utf8.decoder).listen((line) {
        if (mounted && line.trim().isNotEmpty) {
          setState(() => _status = line.trim());
        }
      });
      process.stderr.transform(utf8.decoder).listen((line) {
        if (mounted && line.trim().isNotEmpty) {
          setState(() => _status = line.trim());
        }
      });
      unawaited(
        process.exitCode.then((_) {
          if (mounted) {
            setState(() {
              _captureProcess = null;
              _busy = false;
            });
          }
        }),
      );

      setState(() {
        _busy = false;
        _status = '浏览器已启动。登录并进入教务页面后，点击“读取 Cookie”。';
      });
    } catch (error) {
      setState(() {
        _busy = false;
        _status = '启动浏览器失败：$error';
      });
    }
  }

  Future<void> _finishBrowserCookieCapture() async {
    setState(() {
      _busy = true;
      _status = '正在读取浏览器 Cookie...';
    });

    try {
      final process = _captureProcess;
      if (process != null) {
        process.stdin.writeln();
        await process.exitCode.timeout(const Duration(seconds: 15));
      }

      final outDir = _captureOutDir ?? await BrowserCookieCapture.outputDir();
      final cookie = await BrowserCookieCapture.readJwCookie(outDir);
      _cookieCtrl.text = cookie;
      await _saveConfig();

      setState(() {
        _captureProcess = null;
        _status = '已从浏览器导入教务 Cookie。';
      });
    } catch (error) {
      setState(() => _status = '读取 Cookie 失败：$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _autoLocation() async {
    setState(() {
      _busy = true;
      _status = '正在按网络位置粗略获取地理信息...';
    });

    try {
      final result = await LocationService.fetchByIp();
      _areaCtrl.text = result['area'] ?? _areaCtrl.text;
      _addressCtrl.text = result['address'] ?? _addressCtrl.text;
      await _saveConfig();
      setState(() => _status = '地理信息已填入。IP 定位可能不精确，请手动核对。');
    } catch (error) {
      setState(() => _status = '自动定位失败：$error');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _submitSelected() async {
    final selected = _days.where((day) => day.selected).toList();
    if (selected.isEmpty) {
      setState(() => _status = '请至少勾选一个日期。');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认提交补签'),
        content: Text('将提交 ${selected.length} 个日期。提交后会进入学校系统审核流程。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final config = _readConfig();
    final api = AttendanceApi(config);
    final delay = Duration(milliseconds: config.delayMs.clamp(0, 10000));

    setState(() {
      _busy = true;
      _status = '正在提交 ${selected.length} 个日期...';
    });

    var ok = 0;
    var fail = 0;

    for (var i = 0; i < selected.length; i++) {
      final day = selected[i];
      try {
        final result = await api.submitRemedy(day.date);
        day.result = result;
        if (result.success) {
          ok++;
        } else {
          fail++;
        }
      } catch (error) {
        fail++;
        day.result = SubmitResult(success: false, message: error.toString());
      }

      setState(() {
        _status = '提交进度：${i + 1}/${selected.length}，成功 $ok，失败 $fail';
      });

      if (i < selected.length - 1 && delay.inMilliseconds > 0) {
        await Future<void>.delayed(delay);
      }
    }

    setState(() {
      _busy = false;
      _status = '提交完成：成功 $ok，失败 $fail。';
    });
  }

  void _selectAll(bool selected) {
    setState(() {
      for (final day in _days) {
        day.selected = selected;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _days.where((day) => day.selected).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('深职院考勤补签'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: '保存配置',
            onPressed: _busy ? null : _saveConfig,
            icon: const Icon(Icons.save_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 760) {
            return DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const Material(
                    color: Colors.white,
                    child: TabBar(
                      tabs: [
                        Tab(icon: Icon(Icons.tune), text: '配置'),
                        Tab(icon: Icon(Icons.event_note), text: '日期'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildSettingsPanel(),
                        _buildResultPanel(selectedCount),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          return Row(
            children: [
              SizedBox(width: 420, child: _buildSettingsPanel()),
              const VerticalDivider(width: 1),
              Expanded(child: _buildResultPanel(selectedCount)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('认证配置'),
        _field(
          controller: _cookieCtrl,
          label: 'JW_COOKIE',
          maxLines: 5,
          hint: '从浏览器或现有 .env 复制教务系统 Cookie',
        ),
        const SizedBox(height: 10),
        if (!Platform.isAndroid) ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _startBrowserCookieCapture,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('打开浏览器登录'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _finishBrowserCookieCapture,
                  icon: const Icon(Icons.cookie_outlined),
                  label: const Text('读取 Cookie'),
                ),
              ),
            ],
          ),
        ] else
          Text(
            'APK 版本暂不支持自动读取外部浏览器 Cookie，请手动粘贴。',
            style: TextStyle(color: Colors.grey.shade700, height: 1.35),
          ),
        const SizedBox(height: 12),
        _field(controller: _studentIdCtrl, label: '学号'),
        const SizedBox(height: 12),
        _field(controller: _planWidCtrl, label: '实习计划 WID'),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _fetchLatestPlan,
            icon: const Icon(Icons.badge_outlined),
            label: const Text('自动获取 WID'),
          ),
        ),
        const SizedBox(height: 18),
        _sectionTitle('补签信息'),
        Row(
          children: [
            Expanded(
              child: _field(controller: _monthCtrl, label: '开始月份 YYYY-MM'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(controller: _endMonthCtrl, label: '结束月份 YYYY-MM'),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: _field(controller: _delayCtrl, label: '间隔 ms'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _workPatternSelector(),
        const SizedBox(height: 12),
        _field(controller: _areaCtrl, label: '签到所在地'),
        const SizedBox(height: 12),
        _field(controller: _addressCtrl, label: '详细地址', maxLines: 2),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _autoLocation,
            icon: const Icon(Icons.my_location),
            label: const Text('按 IP 自动填地理信息'),
          ),
        ),
        const SizedBox(height: 12),
        _field(controller: _remarkCtrl, label: '补签备注'),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _queryMissingDays,
                icon: const Icon(Icons.search),
                label: const Text('查询缺签'),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              tooltip: '保存配置',
              onPressed: _busy ? null : _saveConfig,
              icon: const Icon(Icons.save_outlined),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Cookie 会以明文保存到本机配置文件，只适合个人电脑使用。提交前请确认日期、地址和备注真实准确。',
          style: TextStyle(color: Colors.grey.shade700, height: 1.45),
        ),
      ],
    );
  }

  Widget _buildResultPanel(int selectedCount) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _status,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_holidaySource.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '节假日：$_holidaySource',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _busy || _days.isEmpty
                    ? null
                    : () => _selectAll(true),
                icon: const Icon(Icons.done_all),
                label: const Text('全选'),
              ),
              TextButton.icon(
                onPressed: _busy || _days.isEmpty
                    ? null
                    : () => _selectAll(false),
                icon: const Icon(Icons.remove_done),
                label: const Text('清空'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy || selectedCount == 0 ? null : _submitSelected,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text('提交 $selectedCount 项'),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _days.isEmpty ? _buildEmptyState() : _buildDayList()),
      ],
    );
  }

  Widget _buildDayList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _days.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final day = _days[index];
        final result = day.result;
        final color = result == null
            ? Colors.white
            : result.success
            ? const Color(0xffecfdf3)
            : const Color(0xfffff1f2);

        return Material(
          color: color,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _busy
                ? null
                : () {
                    setState(() => day.selected = !day.selected);
                  },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Checkbox(
                    value: day.selected,
                    onChanged: _busy
                        ? null
                        : (value) {
                            setState(() => day.selected = value ?? false);
                          },
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: Text(
                      day.date,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(width: 70, child: Text(day.weekday)),
                  if (day.adjustedWorkday) _chip('调休'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      result?.message ?? '等待提交',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade800),
                    ),
                  ),
                  if (result != null)
                    Icon(
                      result.success ? Icons.check_circle : Icons.error,
                      color: result.success ? Colors.green : Colors.red,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 56,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 12),
          Text(
            '暂无日期',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text('填写配置后点击“查询缺签”。', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _workPatternSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '默认勾选规则',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'five',
              icon: Icon(Icons.calendar_view_week),
              label: Text('一周5天'),
            ),
            ButtonSegment(
              value: 'six',
              icon: Icon(Icons.view_week_outlined),
              label: Text('一周6天'),
            ),
            ButtonSegment(
              value: 'all',
              icon: Icon(Icons.event_repeat),
              label: Text('全部日期'),
            ),
          ],
          selected: {_workPattern},
          onSelectionChanged: _busy
              ? null
              : (value) {
                  setState(() {
                    _workPattern = value.first;
                    for (final day in _days) {
                      day.selected = _defaultSelected(
                        parseDate(day.date),
                        isHoliday: day.holiday,
                        isAdjusted: day.adjustedWorkday,
                        workPattern: _workPattern,
                      );
                    }
                  });
                },
        ),
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xffdbeafe),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: Color(0xff1d4ed8)),
      ),
    );
  }
}

// ======================== 日期工具 ========================

class ParsedMonth {
  ParsedMonth(this.year, this.month);

  final int year;
  final int month;
}

int monthIndex(ParsedMonth month) {
  return month.year * 12 + month.month;
}

List<ParsedMonth> monthsBetween(ParsedMonth start, ParsedMonth end) {
  final result = <ParsedMonth>[];
  for (var index = monthIndex(start); index <= monthIndex(end); index++) {
    final year = (index - 1) ~/ 12;
    final month = ((index - 1) % 12) + 1;
    result.add(ParsedMonth(year, month));
  }
  return result;
}

ParsedMonth? parseMonth(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  if (month < 1 || month > 12) return null;

  return ParsedMonth(year, month);
}

DateTime parseDate(String value) {
  final parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String monthOf(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}';
}

String formatDate(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

DateTime dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String weekdayLabel(DateTime date) {
  return const {
    DateTime.monday: '周一',
    DateTime.tuesday: '周二',
    DateTime.wednesday: '周三',
    DateTime.thursday: '周四',
    DateTime.friday: '周五',
    DateTime.saturday: '周六',
    DateTime.sunday: '周日',
  }[date.weekday]!;
}

String nowInChina() {
  final utc = DateTime.now().toUtc();
  final china = utc.add(const Duration(hours: 8));
  return '${formatDate(china)} '
      '${china.hour.toString().padLeft(2, '0')}:'
      '${china.minute.toString().padLeft(2, '0')}:'
      '${china.second.toString().padLeft(2, '0')}';
}

extension ShortString on String {
  String take(int maxLength) {
    if (length <= maxLength) return this;
    return substring(0, maxLength);
  }
}
