import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Google Maps API key. Restrict in the Google Cloud Console to
    // this iOS bundle id before shipping. The OSM fallback in
    // lib/features/jobs/widgets/map_view.dart kicks in if this key
    // is revoked.
    GMSServices.provideAPIKey("AIzaSyCu7b1kbut4req__M06W49Depsxfx5x6XQ")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
