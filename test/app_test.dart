import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_sign_verify/theme/app_theme.dart';
import 'package:pdf_sign_verify/services/verification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppTheme Tests', () {
    test('Brand and status colors are defined', () {
      expect(AppTheme.primaryColor, isNotNull);
      expect(AppTheme.validColor, isNotNull);
      expect(AppTheme.invalidColor, isNotNull);
      expect(AppTheme.warningColor, isNotNull);
      expect(AppTheme.unknownColor, isNotNull);
      expect(AppTheme.darkBackground, isNotNull);
      expect(AppTheme.darkSurface, isNotNull);
    });
  });

  group('VerificationService Tests', () {
    test('VerificationService exposes channel methods', () {
      expect(VerificationService.verifyPdf, isNotNull);
      expect(VerificationService.getAppVersion, isNotNull);
    });
  });
}
