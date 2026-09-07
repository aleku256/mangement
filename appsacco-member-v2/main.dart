import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const _appGreen = Color(0xFF087B3B);
const _appDarkGreen = Color(0xFF04582A);
const _portalUrl = 'https://ellnoo.com/member-app';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: _appDarkGreen,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const AppSaccoApp());
}

class AppSaccoApp extends StatelessWidget {
  const AppSaccoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'APP SACCO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _appGreen,
          primary: _appGreen,
          secondary: _appDarkGreen,
          surface: const Color(0xFFF7FBF8),
        ),
        scaffoldBackgroundColor: const Color(0xFFF7FBF8),
        fontFamily: 'Roboto',
      ),
      home: const MemberPortalScreen(),
    );
  }
}

class MemberPortalScreen extends StatefulWidget {
  const MemberPortalScreen({super.key});

  @override
  State<MemberPortalScreen> createState() => _MemberPortalScreenState();
}

class _MemberPortalScreenState extends State<MemberPortalScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _initialPageFinished = false;
  bool _mainFrameError = false;
  String _errorText = '';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF7FBF8))
      ..enableZoom(false)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (!mounted) return;
            setState(() => _progress = progress);
          },
          onPageStarted: (String url) {
            if (!mounted) return;
            setState(() {
              _mainFrameError = false;
              _errorText = '';
            });
          },
          onPageFinished: (String url) async {
            if (!mounted) return;
            setState(() {
              _initialPageFinished = true;
              _progress = 100;
            });
            await _injectMobilePolish();
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() {
                _mainFrameError = true;
                _errorText = error.description;
                _initialPageFinished = true;
              });
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              if (uri.host == 'ellnoo.com' || uri.host.endsWith('.ellnoo.com')) {
                return NavigationDecision.navigate;
              }
              await _openExternal(uri);
              return NavigationDecision.prevent;
            }

            if (<String>{'tel', 'mailto', 'sms', 'whatsapp', 'intent'}.contains(uri.scheme)) {
              await _openExternal(uri);
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(_portalUrl));

    if (Platform.isAndroid && _controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;
      AndroidWebViewController.enableDebugging(false);
      androidController.setMediaPlaybackRequiresUserGesture(false);
      androidController.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (GeolocationPermissionsRequestParams request) async {
          return const GeolocationPermissionsResponse(
            allow: true,
            retain: true,
          );
        },
      );
    }
  }

  Future<void> _injectMobilePolish() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          var viewport = document.querySelector('meta[name="viewport"]');
          if (!viewport) {
            viewport = document.createElement('meta');
            viewport.name = 'viewport';
            document.head.appendChild(viewport);
          }
          viewport.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
          document.documentElement.style.webkitTextSizeAdjust = '100%';
          document.body.style.overscrollBehaviorY = 'contain';
        })();
      ''');
    } catch (_) {
      // Portal functionality must never depend on the cosmetic injection.
    }
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // If Android has no handler, leave the portal open rather than crashing.
    }
  }

  Future<void> _reload() async {
    setState(() {
      _mainFrameError = false;
      _progress = 0;
    });
    await _controller.reload();
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        body: SafeArea(
          top: false,
          child: Stack(
            children: <Widget>[
              Positioned.fill(child: WebViewWidget(controller: _controller)),
              if (_mainFrameError)
                Positioned.fill(
                  child: _OfflineView(
                    details: _errorText,
                    onRetry: _reload,
                  ),
                ),
              if (!_initialPageFinished)
                Positioned.fill(
                  child: _LaunchOverlay(progress: _progress),
                ),
              if (_initialPageFinished && !_mainFrameError && _progress < 100)
                Positioned(
                  top: MediaQuery.paddingOf(context).top,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress / 100,
                    minHeight: 2.5,
                    color: _appGreen,
                    backgroundColor: const Color(0xFFE4F3E9),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchOverlay extends StatelessWidget {
  const _LaunchOverlay({required this.progress});

  final int progress;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF4FBF6),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 128,
                  height: 128,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withOpacity(.10),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/app_sacco_logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'APP SACCO',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: _appDarkGreen,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  'Save Together, Grow Together',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _appDarkGreen.withOpacity(.72),
                  ),
                ),
                const SizedBox(height: 34),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress == 0 ? null : progress / 100,
                    minHeight: 6,
                    color: _appGreen,
                    backgroundColor: const Color(0xFFDDEFE3),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Connecting securely to your SACCO…',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF67816E)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineView extends StatelessWidget {
  const _OfflineView({required this.details, required this.onRetry});

  final String details;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF4FBF6),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Image.asset('assets/app_sacco_logo.png', width: 96, height: 96),
                const SizedBox(height: 22),
                const Text(
                  'Unable to open APP SACCO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: _appDarkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Check your internet connection and try again. Your account remains safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14.5, height: 1.4, color: Color(0xFF5D7163)),
                ),
                if (details.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    details,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: _appGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
