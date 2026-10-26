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
  description: 'Yeni mesaj bildirimleri',
  importance: Importance.max,
  playSound: true,
);
const _callChannel = AndroidNotificationChannel(
  'securechat_calls',
  'Gelen aramalar',
  description: 'Ekran kapalıyken gelen sesli ve görüntülü aramalar',
  importance: Importance.max,
  playSound: true,
);

void registerSecurechatPushBackgroundHandler() {
  // Register before runApp so cold-start/background FCM messages are routed
  // even when the authenticated inbox has not been created yet.
  if (defaultTargetPlatform == TargetPlatform.android) {
    FirebaseMessaging.onBackgroundMessage(securechatFirebaseMessagingBackgroundHandler);
  }
}

FirebaseOptions? _firebaseOptions() {
  final apiKey = const String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
  final projectId = const String.fromEnvironment('FIREBASE_PROJECT_ID');
  final senderId = const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  final appId = const String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  if ([apiKey, projectId, senderId, appId].any((v) => v.trim().isEmpty)) return null;
  return FirebaseOptions(apiKey: apiKey, appId: appId, messagingSenderId: senderId, projectId: projectId);
}

@pragma('vm:entry-point')
Future<void> securechatFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Android receives data-only high-priority pushes so the app can create a
  // dedicated full-screen incoming-call notification even while backgrounded.
  final options = _firebaseOptions();
  if (options == null) {
    debugPrint('Securechat background push ignored: Firebase build settings are missing.');
    return;
  }
  if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
  const initialization = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await _localNotifications.initialize(initialization);
  final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(_messageChannel);
  await androidPlugin?.createNotificationChannel(_callChannel);
  await _showNotification(message, fullScreenCall: message.data['kind'] == 'call');
}

Future<void> _showNotification(RemoteMessage message, {required bool fullScreenCall}) async {
  final title = message.notification?.title ?? message.data['title']?.toString() ?? 'Securechat';
  final body = message.notification?.body ?? message.data['body']?.toString() ?? 'Yeni bildirimin var.';
  final isCall = fullScreenCall || message.data['kind'] == 'call';
  await _localNotifications.show(
    message.messageId?.hashCode ?? message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        isCall ? 'securechat_calls' : 'securechat_messages',
        isCall ? 'Gelen aramalar' : 'Securechat mesajları',
        channelDescription: isCall ? 'Ekran kapalıyken gelen aramalar' : 'Yeni mesaj bildirimleri',
        importance: Importance.max,
        priority: Priority.max,
        category: isCall ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,
        fullScreenIntent: isCall,
        visibility: NotificationVisibility.public,
        playSound: true,
        ticker: isCall ? 'Gelen arama' : 'Yeni mesaj',
        autoCancel: true,
        timeoutAfter: isCall ? 45000 : null,
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
    ),
    payload: '${message.data['kind'] ?? 'message'}|${message.data['conversation_id'] ?? ''}',
  );
}

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
    final androidApiKey = const String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
    final iosApiKey = const String.fromEnvironment('FIREBASE_IOS_API_KEY');
    final apiKey = defaultTargetPlatform == TargetPlatform.iOS ? iosApiKey : androidApiKey;
    final projectId = const String.fromEnvironment('FIREBASE_PROJECT_ID');
    final senderId = const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    final androidAppId = const String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    final iosAppId = const String.fromEnvironment('FIREBASE_IOS_APP_ID');
    final appId = defaultTargetPlatform == TargetPlatform.iOS ? iosAppId : androidAppId;
    if ([apiKey, projectId, senderId, appId].any((v) => v.trim().isEmpty)) {
      debugPrint('Securechat push disabled: Firebase Messaging build settings are missing.');
      return;
    }
    try {
      final options = FirebaseOptions(apiKey: apiKey, appId: appId, messagingSenderId: senderId, projectId: projectId);
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: options);
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
      await androidPlugin?.createNotificationChannel(_callChannel);
      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        _publishOpenPayload(launchDetails?.notificationResponse?.payload);
      }
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true, provisional: false);
      final token = await messaging.getToken();
      if (token != null) await _saveToken(client, token);
      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen((value) => _saveToken(client, value));
      await _foregroundSubscription?.cancel();
      await _openedSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) => _showNotification(message, fullScreenCall: message.data['kind'] == 'call'));
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
      debugPrint('Securechat push token registered.');
    } catch (e) {
      debugPrint('Securechat push token registration failed: $e');
    }
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
