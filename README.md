# MovieBox TV - Android TV App

A Flutter-based Android TV application that provides access to MovieBox streaming content through a WebView interface.

## Features

- **Android TV Optimized**: Designed specifically for TV interfaces with remote control navigation
- **WebView Integration**: Seamless access to moviebox.ph content
- **Network Connectivity**: Smart connectivity monitoring and error handling  
- **TV Remote Support**: Full D-pad navigation support for Android TV remotes
- **Landscape Mode**: Optimized for TV viewing with forced landscape orientation
- **Splash Screen**: Professional loading screen with app branding

## Installation

### Prerequisites
- Flutter SDK (3.9.2 or higher)
- Android SDK with TV support
- Android TV device or emulator

### Building for Android TV

1. Clone the repository:
```bash
git clone <your-repo-url>
cd movieboxtv
```

2. Install dependencies:
```bash
flutter pub get
```

3. Build for Android TV:
```bash
flutter build apk --release
```

4. Install on Android TV device:
```bash
flutter install
```

## TV Navigation

The app supports standard Android TV remote controls:

- **D-pad Left/Right**: Navigate back/forward in web content
- **D-pad Center/Enter**: Interact with web elements
- **Back Button**: Navigate back in web history

## Configuration

The app is configured to:
- Load moviebox.ph by default
- Use landscape orientation only
- Support Android TV leanback launcher
- Handle network connectivity changes
- Provide TV-optimized user agent string

## Android TV Manifest Features

The app includes the following Android TV specific configurations:

- Leanback support for TV interfaces
- TV banner icon for the leanback launcher
- Touchscreen not required (TV compatible)
- Landscape orientation lock
- Network permissions for web content

## Development

To modify the default URL, update the WebViewController initialization in `lib/main.dart`:

```dart
..loadRequest(Uri.parse('https://your-url-here.com'));
```

To customize the app theme or TV-specific behavior, modify the relevant sections in `lib/main.dart`.

## License

This project is for educational purposes. Please respect the terms of service of any streaming platforms accessed through this application.
