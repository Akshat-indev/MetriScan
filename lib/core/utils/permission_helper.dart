import 'package:permission_handler/permission_handler.dart';

/// Helper to request and check camera and storage permissions.
class PermissionHelper {
  static Future<bool> requestCamera() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  static Future<bool> requestStorage() async {
    // On Android 13+, READ_MEDIA_IMAGES covers gallery access.
    final status = await Permission.photos.request();
    return status.isGranted || status.isLimited;
  }

  static Future<bool> hasCameraPermission() async {
    return await Permission.camera.isGranted;
  }

  static Future<void> openSettingsIfDenied(Permission p) async {
    final status = await p.status;
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }
}
