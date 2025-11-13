import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:io';
import 'splash_screen.dart';

const platform = MethodChannel('com.movieboxtv/webview');

void main() {
  // Set preferred orientations for TV
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    if(Platform.isIOS)
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  
  runApp(const MovieBoxTVApp());
}

class MovieBoxTVApp extends StatelessWidget {
  const MovieBoxTVApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MovieBox TV',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.red,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const MainScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool showSplash = true;

  @override
  Widget build(BuildContext context) {
    if (showSplash) {
      return SplashScreen(
        onComplete: () {
          setState(() {
            showSplash = false;
          });
        },
      );
    }
    
    return const WebViewScreen();
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController controller;
  bool isLoading = true;
  bool hasError = false;
  bool isConnected = true;
  bool canGoBack = false;
  bool canGoForward = false;
  bool showNavButtons = true;
  Timer? hideButtonsTimer;
  StreamSubscription<ConnectivityResult>? connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _checkConnectivity();
    _enableFullscreen();
  }

  Future<void> _enableFullscreen() async {
    try {
      await platform.invokeMethod('enableFullscreen');
    } catch (e) {
      print('Error enabling fullscreen: $e');
    }
  }

  void _initializeWebView() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..enableZoom(true);
    
    // Configure Android-specific WebView settings for X96Q compatibility
    if (Platform.isAndroid) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setMediaPlaybackRequiresUserGesture(false);
    }
    
    controller
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading progress if needed
          },
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
              hasError = false;
            });
          },
          onPageFinished: (String url) async {
            setState(() {
              isLoading = false;
            });
            
            // Update navigation state
            _updateNavigationState();
            
            // Wait a bit for page to fully render
            await Future.delayed(const Duration(milliseconds: 500));
            
            // Inject CSS and JavaScript to ensure video players are visible and working
            // This is specifically for X96Q and similar cheap Android TV boxes
            await controller.runJavaScript('''
              (function() {
                console.log('MovieBox TV: Injecting video fixes for X96Q');
                
                // Remove any overlays that might hide video
                var style = document.createElement('style');
                style.innerHTML = `
                  * {
                    -webkit-transform: translateZ(0);
                    transform: translateZ(0);
                  }
                  
                  /* Half screen video when not in fullscreen */
                  video:not(:fullscreen), 
                  iframe:not(:fullscreen), 
                  embed:not(:fullscreen), 
                  object:not(:fullscreen) {
                    display: block !important;
                    visibility: visible !important;
                    opacity: 1 !important;
                    position: relative !important;
                    z-index: 2147483647 !important;
                    width: 100% !important;
                    height: 50vh !important;
                    max-height: 50vh !important;
                    min-height: 400px !important;
                    background: black !important;
                    object-fit: contain !important;
                  }
                  
                  /* Fullscreen video takes full screen */
                  video:fullscreen,
                  iframe:fullscreen,
                  embed:fullscreen,
                  object:fullscreen {
                    width: 100vw !important;
                    height: 100vh !important;
                    max-height: 100vh !important;
                  }
                  
                  .video-container:not(:fullscreen), 
                  .player-container:not(:fullscreen), 
                  .video-wrapper:not(:fullscreen), 
                  [class*="video"]:not(:fullscreen), 
                  [class*="player"]:not(:fullscreen), 
                  [id*="video"]:not(:fullscreen), 
                  [id*="player"]:not(:fullscreen) {
                    display: block !important;
                    visibility: visible !important;
                    opacity: 1 !important;
                    overflow: visible !important;
                    height: 50vh !important;
                    max-height: 50vh !important;
                    min-height: 400px !important;
                  }
                  
                  .video-js:not(:fullscreen), 
                  .vjs-tech:not(:fullscreen) {
                    display: block !important;
                    visibility: visible !important;
                    height: 50vh !important;
                    max-height: 50vh !important;
                  }
                  
                  /* Hide video controls after inactivity in fullscreen */
                  video::-webkit-media-controls-panel {
                    transition: opacity 0.3s ease-in-out;
                  }
                  video.hide-controls::-webkit-media-controls-panel {
                    opacity: 0;
                    pointer-events: none;
                  }
                  /* Auto-hide all player control overlays */
                  .vjs-control-bar, .controls, [class*="control"], 
                  .player-controls, [class*="Control"] {
                    transition: opacity 0.5s ease-in-out !important;
                  }
                  body.hide-controls .vjs-control-bar,
                  body.hide-controls .controls,
                  body.hide-controls [class*="control"]:not(video),
                  body.hide-controls .player-controls {
                    opacity: 0 !important;
                    pointer-events: none !important;
                  }
                `;
                document.head.appendChild(style);
                
                // Auto-hide controls functionality
                var hideControlsTimeout;
                var isFullscreen = false;
                
                function hideControls() {
                  clearTimeout(hideControlsTimeout);
                  hideControlsTimeout = setTimeout(function() {
                    if (isFullscreen) {
                      document.body.classList.add('hide-controls');
                      var videos = document.querySelectorAll('video');
                      videos.forEach(function(v) {
                        v.classList.add('hide-controls');
                      });
                    }
                  }, 3000); // Hide after 3 seconds of inactivity
                }
                
                function showControls() {
                  document.body.classList.remove('hide-controls');
                  var videos = document.querySelectorAll('video');
                  videos.forEach(function(v) {
                    v.classList.remove('hide-controls');
                  });
                  hideControls();
                }
                
                // Detect fullscreen changes
                document.addEventListener('fullscreenchange', function() {
                  isFullscreen = !!document.fullscreenElement;
                  if (isFullscreen) {
                    hideControls();
                  } else {
                    showControls();
                    clearTimeout(hideControlsTimeout);
                    // Re-apply half screen sizing when exiting fullscreen
                    setTimeout(fixVideos, 100);
                  }
                });
                
                document.addEventListener('webkitfullscreenchange', function() {
                  isFullscreen = !!document.webkitFullscreenElement;
                  if (isFullscreen) {
                    hideControls();
                  } else {
                    showControls();
                    clearTimeout(hideControlsTimeout);
                    // Re-apply half screen sizing when exiting fullscreen
                    setTimeout(fixVideos, 100);
                  }
                });
                
                // Show controls on any user interaction
                document.addEventListener('mousemove', showControls);
                document.addEventListener('touchstart', showControls);
                document.addEventListener('click', showControls);
                document.addEventListener('keydown', showControls);
                
                // Force video elements to be visible and playable
                function fixVideos() {
                  var videos = document.querySelectorAll('video, iframe[src*="player"], iframe[src*="embed"]');
                  console.log('Found ' + videos.length + ' video elements');
                  
                  videos.forEach(function(video, index) {
                    video.style.display = 'block';
                    video.style.visibility = 'visible';
                    video.style.opacity = '1';
                    video.style.position = 'relative';
                    video.style.zIndex = '2147483647';
                    
                    // Force half screen height when not in fullscreen
                    if (!document.fullscreenElement && !document.webkitFullscreenElement) {
                      video.style.height = '50vh';
                      video.style.maxHeight = '50vh';
                      video.style.minHeight = '400px';
                      video.style.width = '100%';
                      video.style.objectFit = 'contain';
                      
                      // Also resize parent containers
                      if (video.parentElement) {
                        video.parentElement.style.height = '50vh';
                        video.parentElement.style.maxHeight = '50vh';
                        video.parentElement.style.minHeight = '400px';
                      }
                    }
                    
                    if (video.tagName === 'VIDEO') {
                      video.setAttribute('playsinline', 'true');
                      video.setAttribute('webkit-playsinline', 'true');
                      video.setAttribute('controls', 'true');
                      video.removeAttribute('hidden');
                      
                      // Add event listeners to each video
                      video.addEventListener('play', hideControls);
                      video.addEventListener('pause', showControls);
                      
                      console.log('Fixed video element ' + index + ' with half-screen height');
                    }
                  });
                }
                
                // Run immediately
                fixVideos();
                
                // Run again after a delay to catch dynamically loaded videos
                setTimeout(fixVideos, 1000);
                setTimeout(fixVideos, 2000);
                setTimeout(fixVideos, 3000);
                
                // Watch for new videos being added
                var observer = new MutationObserver(function(mutations) {
                  fixVideos();
                });
                
                observer.observe(document.body, {
                  childList: true,
                  subtree: true
                });
                
                console.log('MovieBox TV: Video fixes applied with auto-hide controls');
              })();
            ''');
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              isLoading = false;
              hasError = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse('https://moviebox.ph'));
  }

  void _checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    setState(() {
      isConnected = connectivityResult != ConnectivityResult.none;
    });

    connectivitySubscription = Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      setState(() {
        isConnected = result != ConnectivityResult.none;
      });
      
      if (isConnected && hasError) {
        _reload();
      }
    });
  }

  @override
  void dispose() {
    connectivitySubscription?.cancel();
    hideButtonsTimer?.cancel();
    super.dispose();
  }

  void _updateNavigationState() async {
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
    setState(() {
      canGoBack = back;
      canGoForward = forward;
    });
  }

  void _showNavButtons() {
    setState(() {
      showNavButtons = true;
    });
    
    // Hide buttons after 3 seconds
    hideButtonsTimer?.cancel();
    hideButtonsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          showNavButtons = false;
        });
      }
    });
  }

  void _reload() {
    setState(() {
      hasError = false;
      isLoading = true;
    });
    controller.reload();
    _updateNavigationState();
  }

  void _goBack() async {
    if (await controller.canGoBack()) {
      controller.goBack();
      _updateNavigationState();
    }
  }

  void _goForward() async {
    if (await controller.canGoForward()) {
      controller.goForward();
      _updateNavigationState();
    }
  }
  
  void _goHome() {
    controller.loadRequest(Uri.parse('https://moviebox.ph'));
    _updateNavigationState();
  }
  
  void _testConnection() {
    // Test with Google to verify WebView works
    setState(() {
      hasError = false;
      isLoading = true;
    });
    controller.loadRequest(Uri.parse('https://www.google.com'));
    _updateNavigationState();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        // Handle Android back button
        if (await controller.canGoBack()) {
          controller.goBack();
          _updateNavigationState();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: KeyboardListener(
              focusNode: FocusNode(),
              autofocus: true,
              onKeyEvent: (KeyEvent event) {
                if (event is KeyDownEvent) {
                  _showNavButtons();
                  // Handle TV remote navigation
                  switch (event.logicalKey) {
                    case LogicalKeyboardKey.arrowLeft:
                      _goBack();
                      break;
                    case LogicalKeyboardKey.arrowRight:
                      _goForward();
                      break;
                    case LogicalKeyboardKey.select:
                    case LogicalKeyboardKey.enter:
                      // Handle select/enter if needed
                      break;
                    case LogicalKeyboardKey.goBack:
                      _goBack();
                      break;
                  }
                }
              },
              child: GestureDetector(
                onTap: _showNavButtons,
                child: Stack(
                  children: [
                    if (!hasError)
                      WebViewWidget(controller: controller)
                    else
                      _buildErrorScreen(),
                    
                    if (isLoading)
                      const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: Colors.red,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Loading MovieBox...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    // Floating Navigation Buttons
                    if (showNavButtons && !isLoading && !hasError)
                      _buildNavigationButtons(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isConnected ? Icons.error_outline : Icons.wifi_off,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  isConnected ? 'Failed to load MovieBox' : 'No Internet Connection',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isConnected 
                    ? 'Unable to connect to moviebox.ph\nThe website might be down or blocking connections'
                    : 'Check your network connection',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: isConnected ? _reload : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey,
                        disabledForegroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        isConnected ? 'Retry' : 'Waiting for connection...',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    if (isConnected) ...[
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _testConnection,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Test Google',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!isConnected)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: CircularProgressIndicator(
                      color: Colors.red,
                    ),
                  ),
              ],
            ),
            Positioned(child: IconButton(onPressed: (){
              setState(() {
                hasError = false;
              });
            }, icon: Icon(Icons.close, color: Colors.white)))
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Positioned(
      bottom: Platform.isIOS ? 20 : null,
      top: Platform.isIOS ? null : 20,
      right: Platform.isIOS ? 40.0 : 20,
      left: Platform.isIOS ? 40.0 : null,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Back Button
            _buildNavButton(
              icon: Icons.arrow_back,
              onPressed: canGoBack ? _goBack : null,
              tooltip: 'Back',
            ),
            const SizedBox(width: 8),
            // Forward Button
            _buildNavButton(
              icon: Icons.arrow_forward,
              onPressed: canGoForward ? _goForward : null,
              tooltip: 'Forward',
            ),
            const SizedBox(width: 8),
            // Home Button
            _buildNavButton(
              icon: Icons.home,
              onPressed: _goHome,
              tooltip: 'Home',
            ),
            const SizedBox(width: 8),
            // Reload Button
            _buildNavButton(
              icon: Icons.refresh,
              onPressed: _reload,
              tooltip: 'Reload',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: onPressed != null 
                  ? Colors.red.withValues(alpha: 0.8)
                  : Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: onPressed != null ? Colors.white : Colors.grey,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
