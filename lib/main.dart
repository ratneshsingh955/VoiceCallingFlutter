import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:mysa_flutter/firebase_options.dart';
import 'screens/sign_in_screen.dart';
import 'screens/welcome_screen.dart';
import 'utils/logger_util.dart';
import 'services/call_cleanup_worker.dart';
import 'services/notification_service.dart';
import 'services/fcm_background_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.info('🚀 Starting Voice Calling App initialization');
  
  try {
    AppLogger.debug('Initializing Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    AppLogger.info('✅ Firebase initialized successfully');
    
    AppLogger.debug('Initializing NotificationService...');
    await NotificationService.initialize();
    AppLogger.info('✅ NotificationService initialized successfully');
    
    AppLogger.debug('Setting up FCM background handler...');
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    AppLogger.info('✅ FCM background handler registered');
    
    AppLogger.debug('Initializing CallCleanupWorker...');
    await CallCleanupWorker.initialize();
    AppLogger.info('✅ CallCleanupWorker initialized successfully');
    
    AppLogger.info('Running MyApp');
    runApp(const MyApp());
  } catch (e, stackTrace) {
    AppLogger.fatal('❌ Failed to initialize app', e, stackTrace);
    rethrow;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    AppLogger.debug('Building MyApp widget');
    
    return MaterialApp(
      title: 'Voice Calling App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          AppLogger.trace('Auth state changed: ${snapshot.connectionState}');
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            AppLogger.debug('Auth state: Waiting for authentication status');
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
          }
          
          if (snapshot.hasData && snapshot.data != null) {
            final user = snapshot.data!;
            AppLogger.info('✅ User authenticated: ${user.email} (UID: ${user.uid})');
            return const WelcomeScreen();
          }
          
          AppLogger.debug('No authenticated user, showing sign-in screen');
          return const SignInScreen();
        },
      ),
    );
  }
}
