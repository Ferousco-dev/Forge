Full session context — Forge / SQUAD hackathon
Project
App: Forge — Flutter mobile app for Nigerian informal workers (loaders, drivers, unloaders, welders, general labor)
Repo: ~/Desktop/HACKATHON/SQUAD
Hackathon: SQUAD Hackathon 3.0 — Challenge 02 (intelligent economic system, Squad APIs as financial backbone, AI-powered matching/credit/invoicing)
Stack: Flutter 3.38, Riverpod, GoRouter, OpenStreetMap (flutter_map), flutter_secure_storage, mock providers in lib/core/mock/ to be swapped for backend later
Backend: TBD — separate dev. Contract lives in endpoint_resources/
What this session shipped

1. GPT prompts (for content seeding)
   Full job-seed prompt matching the Job.fromJson schema in lib/core/mock/models.dart:118-208 — generates 30 jobs with NGN pay, Nigerian addresses, employer shapes
   Minimal job-titles-only prompt — generates 50 grounded titles like "Offload 40ft container at Apapa warehouse"
2. Color scheme reference (already in code)
   Hybrid system in lib/app/theme/app_colors.dart: aubergine #3D2566 brand surface for splash/auth, teal #0E695F + amber #E89108 content palette for the app interior
   Brand cream #F5EDD8, light surface #FCFCFA, dark #0B1014
3. Push notifications — the major work
   Endpoint specs (for backend dev):

endpoint_resources/24_push_notifications.md — full FCM transport contract: 4 triggers (application accepted, application rejected, new nearby job, wallet credited), Android channels with custom opay_credit sound, FCM HTTP v1 payload shape, send-pipeline rules
endpoint_resources/18_settings.md — beefed up POST /me/devices, added DELETE /me/devices/:device_id
endpoint_resources/00_README.md — index updated, removed "out of scope" line for push
Mobile FCM wiring (all done):

pubspec.yaml — added firebase*core ^3.6.0, firebase_messaging ^15.1.3, flutter_local_notifications ^17.2.3
lib/core/notifications/notification_channels.dart — three channels: forge_payments (custom opay_credit sound), forge_jobs, forge_default
lib/core/notifications/device_repository.dart — POST / DELETE /me/devices
lib/core/notifications/push_background_handler.dart — top-level @pragma('vm:entry-point') handler (FCM contract)
lib/core/notifications/notifications_service.dart — permission, token register, foreground display, deeplink stream
lib/main.dart — Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform) + background handler before runApp
lib/app.dart — boots service post-frame, parses forge://... deeplinks, pushes via GoRouter, refreshes in-app feed on foreground push
lib/features/auth/state/auth_state.dart — added deviceRepositoryProvider + notificationsServiceProvider
lib/features/auth/presentation/permissions/notification_permission_screen.dart — "Enable Notifications" actually requests OS permission + registers device
lib/features/profile/presentation/profile_screen.dart:712 — logout calls unregister() before clearing tokens
lib/core/storage/session_storage.dart — added persistent device_id (UUID, prefixed dvc*) + last-registered-token cache
Native config (all done):

android/app/src/main/AndroidManifest.xml — FCM default icon, color, channel meta
android/app/src/main/res/values/colors.xml — forge_primary (#0E695F)
ios/Runner/Info.plist — UIBackgroundModes: [remote-notification, fetch] + FirebaseMessagingAutoInitEnabled 4. Firebase project setup (done)
Installed: FlutterFire CLI (dart pub global activate flutterfire_cli), Firebase CLI (brew install firebase-cli), xcodeproj gem (sudo gem install xcodeproj)
Logged in as feranmioresajo@gmail.com
Created Firebase project: forge-squad-hackathon
Android package id: com.squadcode.noname (note: still default — change before Play Store launch)
iOS bundle id: com.squadcode.noname
Generated config files (committed-ready):
lib/firebase_options.dart
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
Gradle plugin auto-wired in android/settings.gradle.kts + android/app/build.gradle.kts 5. Misc
Confirmed lib/features/earnings/data/wallet_repository.dart is correct — Squad handles withdrawals server-side, mobile only sends amount
Provided 16 feature ideas categorized by AI / Squad / trust / network / accessibility — top picks: demand heatmap, PDF invoices, squad/crew mode
Where to pick up
Immediately (to get push working end-to-end)
Run the app — pick a target device, then flutter run. Recommend Android emulator with Google Play Services for FCM testing (iOS Simulator can't receive pushes).
Drop the opay_credit sound asset:
android/app/src/main/res/raw/opay_credit.mp3 (lowercase, no spaces)
ios/Runner/opay_credit.caf (add to Xcode → Runner target → Build Phases → Copy Bundle Resources)
Drop the ic_stat_forge notification icon at android/app/src/main/res/drawable\*/ic_stat_forge.png (white-on-transparent, 24dp). Until then Android falls back to ic_launcher and renders as a white square.
iOS only: upload an APNs auth key (.p8 from Apple Developer → Keys) to Firebase Console → Project Settings → Cloud Messaging. Required for iOS push.
Backend dev handoff
Send: endpoint_resources/24_push_notifications.md, endpoint_resources/18_settings.md, endpoint_resources/00_README.md, endpoint_resources/19_notifications.md
Generate service account JSON: https://console.firebase.google.com/project/forge-squad-hackathon/settings/serviceaccounts/adminsdk → "Generate new private key" → DM via 1Password / Bitwarden (NEVER Slack/email/git)
Tell him plainly: project id forge-squad-hackathon, FCM endpoint https://fcm.googleapis.com/v1/projects/forge-squad-hackathon/messages:send, package/bundle com.squadcode.noname
He builds: POST /me/devices, DELETE /me/devices/:device_id, the FCM send job, wires the 4 triggers
Optional next features (from ideas list — top 3 for demo punch)
Demand heatmap — map overlay of open jobs per area; plays to AI + visual demo
AI-generated PDF invoices — proves "financial visibility" thesis directly
Squad / crew mode — multi-worker job applications, Squad splits payout
Known to-dos before production (not hackathon-blocking)
Change package/bundle id from com.squadcode.noname to a real one
Add the APNs .p8 to Firebase Console
Replace MockConfig.forceOffline toggle once backend is live
Save this as memory.md if you want it persisted
This whole context is a self-contained handoff — paste it into a new session and you (or another Claude) can pick up exactly here.
