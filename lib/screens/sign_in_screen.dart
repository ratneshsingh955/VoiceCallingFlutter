import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'welcome_screen.dart';
import '../utils/logger_util.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isSignUp = false;

  @override
  void initState() {
    super.initState();
    AppLogger.debug('SignInScreen initialized');
  }

  @override
  void dispose() {
    AppLogger.debug('SignInScreen disposed');
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    AppLogger.info('🔐 Sign-in attempt initiated for email: $email');
    
    if (_formKey.currentState!.validate()) {
      AppLogger.debug('Form validation passed for sign-in');
      setState(() {
        _isLoading = true;
      });

      try {
        AppLogger.debug('Attempting to sign in with Firebase Auth...');
        final userCredential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: _passwordController.text,
        );

        if (userCredential.user != null && mounted) {
          AppLogger.info('✅ Sign-in successful for user: ${userCredential.user!.email} (UID: ${userCredential.user!.uid})');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          );
        }
      } on FirebaseAuthException catch (e) {
        String message = 'An error occurred';
        AppLogger.warning('⚠️ Firebase Auth error during sign-in', e);
        
        if (e.code == 'user-not-found') {
          message = 'No user found for that email.';
          AppLogger.warning('User not found for email: $email');
        } else if (e.code == 'wrong-password') {
          message = 'Wrong password provided.';
          AppLogger.warning('Wrong password provided for email: $email');
        } else if (e.code == 'invalid-email') {
          message = 'The email address is invalid.';
          AppLogger.warning('Invalid email format: $email');
        } else if (e.code == 'user-disabled') {
          message = 'This user account has been disabled.';
          AppLogger.warning('User account disabled for email: $email');
        } else if (e.code == 'too-many-requests') {
          message = 'Too many requests. Please try again later.';
          AppLogger.warning('Too many sign-in requests for email: $email');
        } else {
          AppLogger.error('Unknown Firebase Auth error code: ${e.code}', e);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      } catch (e, stackTrace) {
        AppLogger.error('❌ Unexpected error during sign-in', e, stackTrace);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          AppLogger.debug('Sign-in attempt completed, loading state reset');
        }
      }
    } else {
      AppLogger.debug('Form validation failed for sign-in');
    }
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    AppLogger.info('📝 Sign-up attempt initiated for email: $email');
    
    if (_formKey.currentState!.validate()) {
      AppLogger.debug('Form validation passed for sign-up');
      setState(() {
        _isLoading = true;
      });

      try {
        AppLogger.debug('Attempting to create user with Firebase Auth...');
        final userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: _passwordController.text,
        );

        if (userCredential.user != null && mounted) {
          AppLogger.info('✅ Sign-up successful for user: ${userCredential.user!.email} (UID: ${userCredential.user!.uid})');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          );
        }
      } on FirebaseAuthException catch (e) {
        String message = 'An error occurred';
        AppLogger.warning('⚠️ Firebase Auth error during sign-up', e);
        
        if (e.code == 'weak-password') {
          message = 'The password provided is too weak.';
          AppLogger.warning('Weak password provided for email: $email');
        } else if (e.code == 'email-already-in-use') {
          message = 'An account already exists for that email.';
          AppLogger.warning('Email already in use: $email');
        } else if (e.code == 'invalid-email') {
          message = 'The email address is invalid.';
          AppLogger.warning('Invalid email format: $email');
        } else if (e.code == 'operation-not-allowed') {
          message = 'Email/password accounts are not enabled.';
          AppLogger.error('Email/password authentication not enabled in Firebase');
        } else {
          AppLogger.error('Unknown Firebase Auth error code: ${e.code}', e);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      } catch (e, stackTrace) {
        AppLogger.error('❌ Unexpected error during sign-up', e, stackTrace);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          AppLogger.debug('Sign-up attempt completed, loading state reset');
        }
      }
    } else {
      AppLogger.debug('Form validation failed for sign-up');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.phone,
                    size: 60,
                    color: Colors.deepPurple,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _isSignUp ? 'Sign Up' : 'Sign In',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'Enter your email',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : (_isSignUp ? _signUp : _signIn),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            _isSignUp ? 'Sign Up' : 'Sign In',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignUp
                            ? 'Already have an account?'
                            : "Don't have an account?",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                final newMode = !_isSignUp;
                                AppLogger.debug('Switching to ${newMode ? "Sign Up" : "Sign In"} mode');
                                setState(() {
                                  _isSignUp = newMode;
                                  _formKey.currentState?.reset();
                                });
                              },
                        child: Text(
                          _isSignUp ? 'Sign In' : 'Sign Up',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

