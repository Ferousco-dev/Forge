# Forge - Gig Work Platform

A comprehensive Flutter application that connects workers with gig opportunities, enabling job discovery, work session management, earnings tracking, and financial services.

## 📱 Overview

Forge is a full-featured mobile platform designed for gig workers, built with **Flutter** and **Firebase**. It provides a seamless experience for finding work, managing active sessions, tracking earnings, and accessing financial services like loans and withdrawals.

### Key Features

- **🔐 Authentication & Authorization** - Secure user registration and login with multi-factor authentication
- **💼 Job Discovery** - Browse and apply for gig opportunities with real-time location-based filtering
- **📍 Geolocation** - Map-based job browsing and clock-in verification
- **⏱️ Work Sessions** - Clock in/out with photo proof and live tracking
- **💰 Earnings Management** - Real-time earnings tracking and transaction history
- **🏦 Financial Services** - Loan applications, payouts, and bank account management
- **📊 Profile & History** - Work history, ratings, and performance metrics
- **🔔 Push Notifications** - Real-time updates on job opportunities and payments
- **🌙 Dark Mode** - Full dark theme support with system preference detection
- **🏥 Data Privacy** - GDPR-compliant data export and deletion features

## 🛠️ Tech Stack

| Layer                | Technology                                  |
| -------------------- | ------------------------------------------- |
| **UI Framework**     | Flutter 3.x                                 |
| **State Management** | Riverpod                                    |
| **Routing**          | GoRouter                                    |
| **Backend**          | Firebase (Auth, Firestore, Cloud Messaging) |
| **Maps**             | Google Maps Flutter                         |
| **Camera**           | Camera + Image Picker                       |
| **Storage**          | Secure Storage, SQLite (sqflite)            |
| **Payments**         | Stripe, Bank Transfers                      |
| **PDF Generation**   | Printing                                    |
| **Geolocation**      | Geolocator, Geocoding                       |
| **Analytics**        | Firebase Analytics                          |

## 📦 Project Structure

```
lib/
├── main.dart                 # App entry point
├── app.dart                  # Root widget with routing & theme
├── firebase_options.dart     # Firebase configuration
├── app/
│   ├── router/              # GoRouter configuration & routes
│   └── theme/               # Material theme & colors
├── core/
│   ├── http/                # API client & interceptors
│   ├── notifications/       # Push notifications & FCM handling
│   ├── extensions/          # Dart extensions
│   └── constants/           # App-wide constants
├── features/
│   ├── auth/                # Authentication feature
│   │   ├── data/
│   │   ├── presentation/
│   │   └── state/
│   ├── jobs/                # Job discovery & browsing
│   ├── work/                # Active work sessions
│   ├── earnings/            # Earnings & transactions
│   ├── loans/               # Loan management
│   ├── profile/             # User profile & settings
│   ├── splash/              # Splash screen
│   └── [other features]/
└── shared/
    └── widgets/             # Reusable UI components

endpoint_resources/          # API Documentation
android/                     # Android native configuration
ios/                        # iOS native configuration
```

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK**: 3.x or higher
- **Dart**: 3.x or higher
- **Xcode**: 14.x or higher (for iOS)
- **Android Studio**: Latest version (for Android)
- **CocoaPods**: Latest version (for iOS dependencies)

### Installation

1. **Clone the repository:**

   ```bash
   git clone https://github.com/Ferousco-dev/Forge.git
   cd Forge
   ```

2. **Install dependencies:**

   ```bash
   flutter pub get
   ```

3. **Set up Firebase:**

   ```bash
   flutterfire configure
   ```

   This generates `firebase_options.dart` with your Firebase project credentials for both iOS and Android.

4. **Run on iOS (requires macOS):**

   ```bash
   flutter run -d ios
   ```

5. **Run on Android:**
   ```bash
   flutter run -d android
   ```

### Environment Setup

#### Firebase Configuration

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Enable these services:
   - Authentication (Email, Phone)
   - Firestore Database
   - Cloud Messaging (FCM)
   - Cloud Storage
   - Cloud Functions

3. Download configuration files:
   - **iOS**: `GoogleService-Info.plist` → `ios/Runner/`
   - **Android**: `google-services.json` → `android/app/`

4. Run `flutterfire configure` to auto-generate `firebase_options.dart`

#### API Configuration

1. Update API base URL in `lib/core/http/api_client.dart`
2. Configure backend endpoints as documented in `endpoint_resources/`

## 📚 API Documentation

Comprehensive API endpoint documentation is available in the `endpoint_resources/` directory:

- `01_auth.md` - Authentication endpoints
- `02_jobs_feed.md` - Job listing & discovery
- `03_job_detail.md` - Individual job details
- `04_apply_for_job.md` - Job application
- `05_application_status.md` - Application tracking
- `07_work_session.md` - Work session management
- `08_earnings_home.md` - Earnings dashboard
- `09_transactions.md` - Transaction history
- `12_bank_accounts.md` - Bank account management
- `14_loan_apply.md` - Loan application flow
- `24_push_notifications.md` - Push notification system
- And more...

## 🔧 Development

### Building

**Development Build:**

```bash
flutter build apk --debug      # Android
flutter build ios --debug      # iOS
```

**Release Build:**

```bash
flutter build apk --release    # Android (requires signing)
flutter build ipa --release    # iOS (requires code signing)
```

### Running Tests

```bash
# Unit tests
flutter test

# Integration tests
flutter test integration_test/
```

### Code Analysis

```bash
# Analyze code for issues
flutter analyze

# Format code
dart format lib/

# Fix auto-fixable issues
dart fix --apply
```

### Performance Optimization

Refer to `PERFORMANCE_OPTIMIZATION.md` for:

- Frame rate optimization
- Memory management strategies
- Asset compression techniques
- Network efficiency improvements

See `PERFORMANCE_QUICK_START.md` for quick-win optimizations.

## 🔐 Security Considerations

- **Firebase Auth**: Handles authentication with role-based access control
- **Secure Storage**: Sensitive data (tokens, credentials) stored in encrypted storage
- **HTTPS Only**: All API communication uses HTTPS
- **Data Privacy**: GDPR-compliant data export and deletion
- **Permission Handling**: Granular permission requests for location, camera, photos
- **API Keys**: Firebase keys are embedded; ensure backend API has proper authentication

## 🌍 Localization

The app supports multiple languages through Flutter's localization framework. Language files are located in `lib/shared/localization/`.

Current supported languages:

- English (en)
- [Add more as needed]

## 🐛 Debugging

### Enable Debug Logging

Add to `main.dart` before `runApp()`:

```dart
debugPrintBeginFrameBanner = true;
debugPrintEndFrameBanner = true;
```

### Firebase Emulator (Optional)

Connect to Firebase Emulator Suite for local development:

```bash
firebase emulators:start
# In app, connect to emulator in development build
```

### Common Issues

| Issue                    | Solution                                                                                                 |
| ------------------------ | -------------------------------------------------------------------------------------------------------- |
| Firebase init fails      | Run `flutterfire configure` and ensure `google-services.json` and `GoogleService-Info.plist` are present |
| Maps not showing         | Verify Google Maps API key in `android/app/build.gradle.kts` and `ios/Runner/Info.plist`                 |
| Camera permission denied | Check `ios/Runner/Info.plist` and `android/app/src/main/AndroidManifest.xml` for permission declarations |
| Location always null     | Ensure location permission is granted; test on physical device (simulator location may be unreliable)    |

## 📋 Deployment

### iOS Deployment

1. Update version in `pubspec.yaml`
2. Build IPA:
   ```bash
   flutter build ipa --release
   ```
3. Use Xcode or Transporter to upload to App Store

### Android Deployment

1. Generate signed APK/AAB:
   ```bash
   flutter build appbundle --release
   ```
2. Upload to Google Play Console

See `endpoint_resources/00_system_architecture.md` for deployment architecture details.

## 🤝 Contributing

1. Create a feature branch: `git checkout -b feature/your-feature`
2. Make your changes with descriptive commits
3. Ensure code passes analysis: `flutter analyze`
4. Format code: `dart format lib/`
5. Push and create a pull request

## 📝 Commit Guidelines

Use conventional commit messages:

- `feat:` - New feature
- `fix:` - Bug fix
- `chore:` - Build, dependency, or tooling changes
- `docs:` - Documentation updates
- `refactor:` - Code refactoring without feature/fix changes
- `test:` - Test additions or modifications

Example: `feat: Add job notification badge counter`

## 📄 License

This project is proprietary and confidential.

## 👥 Team

- **Product**: SQUAD Co
- **Development**: Ferousco Dev

## 📞 Support & Documentation

For detailed information on specific features, refer to:

- `endpoint_resources/` - API and feature specifications
- `OPTIMIZATION_SUMMARY.md` - Performance optimization summary
- Inline code comments for complex logic

## 🔗 Links

- [Firebase Documentation](https://firebase.flutter.dev/)
- [Flutter Documentation](https://flutter.dev/docs)
- [Riverpod Guide](https://riverpod.dev/)
- [GoRouter Documentation](https://pub.dev/packages/go_router)

---

**Last Updated**: May 14, 2026
**Version**: 1.0.0
