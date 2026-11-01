# PDF Sign Verify

A **real** cryptographic PDF digital signature verification Android application built with Flutter and native Kotlin.

## What It Does

PDF Sign Verify allows users to select any PDF document and verify whether it contains genuine cryptographic digital signatures, without requiring login, registration, or subscriptions.

### Flow
```
Open App → Select PDF → Verify Digital Signature → View Results → Export Report
```

## Real Cryptographic Verification

This app performs **actual cryptographic verification** using:

- **iText 7** - PDF signature structure parsing (ByteRange, /Sig dictionaries)
- **BouncyCastle** - CMS/PKCS#7 signature verification, certificate chain validation

### What Gets Verified

| Check | Description |
|-------|-------------|
| ✓ Signature Integrity | CMS/PKCS#7 cryptographic verification |
| ✓ Document Integrity | ByteRange and hash verification |
| ✓ Certificate Validity | Expiry, not-yet-valid checks |
| ✓ Certificate Trust | Chain verification against system trust store |
| ✓ Revocation Status | OCSP and CRL checking |
| ✓ Timestamp | RFC 3161 timestamp verification |
| ✓ Multiple Signatures | All signatures and PDF revisions |

### What It NEVER Does

- ❌ Never fakes a VALID result
- ❌ Never modifies the original PDF
- ❌ Never uses OCR, QR codes, or image recognition
- ❌ Never trusts based on issuer name alone
- ❌ Never adds watermarks or visual indicators to the PDF

## Technology Stack

- **UI**: Flutter 3.x with Material 3
- **Crypto Engine**: Native Kotlin/Android
- **Libraries**: BouncyCastle (crypto), iText 7 (PDF signatures)
- **Bridge**: MethodChannel

## Building

```bash
flutter pub get
flutter build apk --release
```

## Security

- PDFs are treated as untrusted input
- PDF JavaScript is not executed
- Processing is done locally
- No PDF content is logged
- No API keys or secrets in source code

## License

This project is licensed under the GNU Affero General Public License v3.0 (GNU AGPLv3) - see the [LICENSE](LICENSE) file for details.
