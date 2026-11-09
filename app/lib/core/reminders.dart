import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Weekly weigh-in reminders as local notifications (phones/tablets only).
class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> _init() async {
    if (_ready || !supported) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC); // unknown zone: reminders fire in UTC rather than not at all
    }
    await _plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'), iOS: DarwinInitializationSettings(requestAlertPermission: false)));
    _ready = true;
  }

  /// Asks for the notification permission. Returns whether reminders can be shown.
  static Future<bool> requestPermission() async {
    if (!supported) return false;
    await _init();
    if (Platform.isAndroid) {
      return await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission() ?? false;
    }
    return await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  /// Next date at [time] on [weekday] (DateTime.monday..sunday) strictly in the future.
  static tz.TZDateTime nextInstance(int weekday, TimeOfDay time, {tz.TZDateTime? from}) {
    final now = from ?? tz.TZDateTime.now(tz.local);
    var d = tz.TZDateTime(tz.local, now.year, now.month, now.day, time.hour, time.minute);
    while (d.weekday != weekday || !d.isAfter(now)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  static Future<void> schedule(TimeOfDay time, Set<int> weekdays) async {
    await _init();
    await _plugin.cancelAll();
    for (final wd in weekdays) {
      await _plugin.zonedSchedule(
        100 + wd,
        'Time to weigh in',
        'Step on your scale to keep your streak going.',
        nextInstance(wd, time),
        const NotificationDetails(
          android: AndroidNotificationDetails('weigh_in', 'Weigh-in reminders', channelDescription: 'Weekly reminders to weigh yourself', importance: Importance.defaultImportance),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  static Future<void> cancel() async {
    if (!supported) return;
    await _init();
    await _plugin.cancelAll();
  }
}
