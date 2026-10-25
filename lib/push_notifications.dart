import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _localNotifications = FlutterLocalNotificationsPlugin();
const _messageChannel = AndroidNotificationChannel(
  'securechat_messages',
  'Securechat mesajları',
  description: 'Yeni mesaj ve arama bildirimleri',
  importance: Importance.max,
  playSound: true,
);

class SecurechatPushNotifications {
  SecurechatPushNotifications._();
  static final SecurechatPushNotifications instance = SecurechatPushNotifications._();
  static final ValueNotifier<Map<String, String>?> openedNotification = ValueNotifier(null);

  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;

  Future<void> initialize(SupabaseClient client) async {
    if (_initialized || client.auth.currentUser == null) return;
    final apiKey = const String.fromEnvironment('FIREBASE_API_KEY');
    final projectId = const String.fromEnvironment('FIREBASE_PROJECT_ID');
    final senderId = const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    final androidAppId = const String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    final iosAppId = const String.fromEnvironment('FIREBASE_IOS_APP_ID');
    final appId = defaultTargetPlatform == TargetPlatform.iOS ? iosAppId : androidAppId;
    // Push is deliberately disabled, rather than crashing the messenger, until
    // the Firebase Messaging transport settings are supplied to the build.
    if ([apiKey, projectId, senderId, appId].any((v) => v.trim().isEmpty)) {
      debugPrint('Securechat push disabled: Firebase Messaging build settings are missing.');
      return;
    }
    try {
      await Firebase.initializeApp(options: FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: senderId,
        projectId: projectId,
      ));
      const initialization = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _localNotifications.initialize(
        initialization,
        onDidReceiveNotificationResponse: (response) => _publishOpenPayload(response.payload),
      );
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_messageChannel);
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true, provisional: false);
      final token = await messaging.getToken();
      if (token != null) await _saveToken(client, token);
      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen((value) => _saveToken(client, value));
      await _foregroundSubscription?.cancel();
      await _openedSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) => _publishOpenData(message.data));
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) _publishOpenData(initialMessage.data);
      _initialized = true;
      debugPrint('Securechat push initialized.');
    } catch (e, stack) {
      debugPrint('Securechat push initialization failed: $e');
      debugPrintStack(stackTrace: stack);
    }
  }

  Future<void> _saveToken(SupabaseClient client, String token) async {
    final userId = client.auth.currentUser?.id;
    if (userId == null || token.isEmpty) return;
    try {
      await client.from('push_tokens').upsert({
        'user_id': userId,
        'token': token,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (e) {
      debugPrint('Securechat push token registration failed: $e');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString() ?? 'Securechat';
    final body = notification?.body ?? message.data['body']?.toString() ?? 'Yeni bildirimin var.';
    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'securechat_messages',
          'Securechat mesajları',
          channelDescription: 'Yeni mesaj ve arama bildirimleri',
          importance: Importance.max,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      ),
      payload: '${message.data['kind'] ?? 'message'}|${message.data['conversation_id'] ?? ''}',
    );
  }

  void _publishOpenData(Map<String, dynamic> data) {
    final conversationId = data['conversation_id']?.toString() ?? '';
    if (conversationId.isEmpty) return;
    openedNotification.value = {
      'kind': data['kind']?.toString() ?? 'message',
      'conversation_id': conversationId,
    };
  }

  void _publishOpenPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    if (parts.length < 2 || parts[1].isEmpty) return;
    _publishOpenData({'kind': parts[0], 'conversation_id': parts[1]});
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    _tokenSubscription = null;
    _foregroundSubscription = null;
    _openedSubscription = null;
    _initialized = false;
  }
}
