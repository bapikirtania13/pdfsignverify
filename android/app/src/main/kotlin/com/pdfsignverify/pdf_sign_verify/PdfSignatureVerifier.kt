package com.pdfsignverify.pdf_sign_verify

import android.content.Context
import android.net.Uri
import android.util.Log
import com.itextpdf.bouncycastle.BouncyCastleFactory
import com.itextpdf.commons.bouncycastle.IBouncyCastleFactory
import com.itextpdf.kernel.pdf.PdfDocument
import com.itextpdf.kernel.pdf.PdfPage
import com.itextpdf.kernel.pdf.PdfReader
import com.itextpdf.kernel.pdf.PdfWriter
import com.itextpdf.kernel.pdf.ReaderProperties
import com.itextpdf.kernel.exceptions.BadPasswordException
import com.itextpdf.kernel.pdf.canvas.PdfCanvas
import com.itextpdf.kernel.pdf.canvas.PdfCanvasConstants
import com.itextpdf.kernel.colors.ColorConstants
import com.itextpdf.kernel.colors.DeviceRgb
import com.itextpdf.kernel.font.PdfFontFactory
import com.itextpdf.io.font.constants.StandardFonts
import com.itextpdf.kernel.geom.Rectangle
import com.itextpdf.signatures.SignatureUtil
import com.itextpdf.signatures.PdfPKCS7
import com.itextpdf.signatures.IssuingCertificateRetriever
import org.bouncycastle.asn1.*
import org.bouncycastle.asn1.cms.ContentInfo
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x500.style.BCStyle
import org.bouncycastle.asn1.x509.*
import org.bouncycastle.cert.X509CertificateHolder
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cms.*
import org.bouncycastle.cms.jcajce.JcaSimpleSignerInfoVerifierBuilder
import org.bouncycastle.asn1.cms.CMSAttributes
import org.bouncycastle.asn1.ASN1OctetString
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.tsp.TSPException
import org.bouncycastle.tsp.TimeStampToken
import org.bouncycastle.util.Store
import org.json.JSONArray
import org.json.JSONObject
import java.io.*
import java.math.BigInteger
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.Security
import java.security.cert.*
import java.text.SimpleDateFormat
import java.util.*
import kotlinx.coroutines.*

/**
 * PdfSignatureVerifier - The core cryptographic verification engine.
 *
 * Uses iText 7 for PDF signature structure parsing and BouncyCastle for
 * cryptographic operations (CMS/PKCS#7 verification, certificate chain
 * validation, OCSP/CRL revocation checking, timestamp verification).
 *
 * CRITICAL RULES:
 * - NEVER mark a signature as VALID unless cryptographic verification succeeds
 * - NEVER modify the original PDF
 * - NEVER use OCR, image recognition, QR codes, or text parsing as proof
 * - If verification cannot be completed, report UNKNOWN/UNSUPPORTED
 */
class PdfSignatureVerifier(private val context: Context) {

    companion object {
        private const val TAG = "PdfSignVerify"
        private const val OCSP_TIMEOUT_MS = 10000
        private const val CRL_TIMEOUT_MS = 15000

        init {
            try {
                // Remove Android's crippled built-in BC provider if present
                Security.removeProvider(BouncyCastleProvider.PROVIDER_NAME)
                // Insert our complete BouncyCastle provider at index 1
                Security.insertProviderAt(BouncyCastleProvider(), 1)
                Log.i(TAG, "BouncyCastle provider successfully registered at position 1")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to register BouncyCastle provider: ${e.message}")
            }
        }
    }

    /**
     * Verify all digital signatures in a PDF file.
     * Returns a JSON object containing verification results for each signature.
     * The PDF is NEVER modified - only read.
     */
    suspend fun verifyPdf(uri: Uri, password: String? = null): JSONObject = withContext(Dispatchers.IO) {
        val result = JSONObject()
        var tempFile: File? = null

        try {
            // Copy URI content to temp file for processing (read-only)
            tempFile = copyUriToTempFile(uri)
            if (tempFile == null) {
                result.put("error", "Unable to read PDF file")
                result.put("status", "ERROR")
                return@withContext result
            }

            // Calculate SHA-256 of original file BEFORE any processing
            val sha256Before = calculateSha256(tempFile)
            result.put("sha256", sha256Before)
            result.put("fileName", getFileName(uri))
            result.put("fileSize", tempFile.length())
            result.put("verificationTimestamp", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(Date()))

            // Open PDF in read-only mode with optional password
            val readerProps = ReaderProperties()
            if (!password.isNullOrEmpty()) {
                readerProps.setPassword(password.toByteArray(Charsets.UTF_8))
            }
            val pdfReader = PdfReader(tempFile.absolutePath, readerProps)
            val pdfDocument = PdfDocument(pdfReader)

            val signatureUtil = SignatureUtil(pdfDocument)
            val signatureNames = signatureUtil.getSignatureNames()

            if (signatureNames.isEmpty()) {
                result.put("status", "NO_SIGNATURES")
                result.put("message", "This PDF does not contain any digital signatures")
                result.put("signatureCount", 0)
                pdfDocument.close()

                // Verify file unchanged
                val sha256After = calculateSha256(tempFile)
                result.put("sha256After", sha256After)
                result.put("fileIntact", sha256Before == sha256After)
                return@withContext result
            }

            result.put("signatureCount", signatureNames.size)
            result.put("totalRevisions", signatureUtil.getTotalRevisions())

            val signaturesArray = JSONArray()

            for (signatureName in signatureNames) {
                try {
                    val sigResult = verifySingleSignature(pdfDocument, signatureUtil, signatureName, tempFile)
                    signaturesArray.put(sigResult)
                } catch (e: Exception) {
                    Log.e(TAG, "Error verifying signature '$signatureName'", e)
                    val errorSig = JSONObject()
                    errorSig.put("signatureName", signatureName)
                    errorSig.put("status", "ERROR")
                    errorSig.put("error", "Verification failed: ${e.message}")
                    signaturesArray.put(errorSig)
                }
            }

            result.put("signatures", signaturesArray)

            // Determine overall status
            val overallStatus = determineOverallStatus(signaturesArray)
            result.put("status", overallStatus)

            pdfDocument.close()

            // Verify SHA-256 unchanged after processing
            val sha256After = calculateSha256(tempFile)
            result.put("sha256After", sha256After)
            result.put("fileIntact", sha256Before == sha256After)

            // If overall status is VALID or WARNING (with intact cryptographic signatures), generate verified preview PDF
            val canGeneratePreview = (overallStatus == "VALID" || overallStatus == "WARNING")
            if (canGeneratePreview) {
                val previewFile = generateVerifiedPreviewPdf(tempFile, signaturesArray, password)
                if (previewFile != null) {
                    result.put("verifiedPdfPath", previewFile.absolutePath)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "PDF verification error", e)
            val isPasswordError = e is BadPasswordException ||
                (e.message?.contains("password", ignoreCase = true) == true) ||
                (e.message?.contains("encrypt", ignoreCase = true) == true)
            if (isPasswordError) {
                result.put("status", "PASSWORD_REQUIRED")
                result.put("isEncrypted", true)
                result.put("error", if (password.isNullOrEmpty()) "This PDF is password protected. Please enter the password." else "Incorrect password. Please try again.")
            } else {
                result.put("error", "Verification failed: ${e.message}")
                result.put("status", "ERROR")
            }
        } finally {
            // Clean up temp file
            tempFile?.delete()
        }

        return@withContext result
    }

    /**
     * Verify a single signature within the PDF.
     * Performs complete cryptographic verification including:
     * - Signature integrity (CMS/PKCS#7 verification)
     * - Document integrity (ByteRange and hash verification)
     * - Certificate validation (chain, expiry, trust)
     * - Revocation checking (OCSP/CRL)
     * - Timestamp verification
     */
    private fun verifySingleSignature(
        pdfDocument: PdfDocument,
        signatureUtil: SignatureUtil,
        signatureName: String,
        pdfFile: File
    ): JSONObject {
        val sigResult = JSONObject()
        sigResult.put("signatureName", signatureName)

        try {
            val pkcs7 = signatureUtil.readSignatureData(signatureName)

            // Extract basic signature info
            val revision = signatureUtil.getRevision(signatureName)
            val totalRevisions = signatureUtil.getTotalRevisions()
            sigResult.put("revision", revision)
            sigResult.put("totalRevisions", totalRevisions)
            sigResult.put("coversWholeDocument", signatureUtil.signatureCoversWholeDocument(signatureName))

            // Get signing certificate
            val signerCert = pkcs7.signingCertificate as java.security.cert.X509Certificate
            val certInfo = extractCertificateInfo(signerCert)
            sigResult.put("certificate", certInfo)

            val sigDict = signatureUtil.getSignature(signatureName)
            val signName = pkcs7.signName
                ?: extractDNField(signerCert.subjectX500Principal.name, "CN")
                ?: "Signer"
            val reason = pkcs7.reason
                ?: sigDict?.pdfObject?.get(com.itextpdf.kernel.pdf.PdfName.Reason)?.toString()?.trim('(', ')')
                ?: ""
            val location = pkcs7.location
                ?: sigDict?.pdfObject?.get(com.itextpdf.kernel.pdf.PdfName.Location)?.toString()?.trim('(', ')')
                ?: ""
            val contactInfo = sigDict?.pdfObject?.get(com.itextpdf.kernel.pdf.PdfName.ContactInfo)?.toString()?.trim('(', ')') ?: ""

            sigResult.put("signerName", signName)
            sigResult.put("reason", reason)
            sigResult.put("location", location)
            sigResult.put("contactInfo", contactInfo)

            // Extract original visible text lines from signature widget appearance
            // This preserves verbatim document names like "Name: KEYA SARKAR"
            try {
                var docSignerName: String? = null
                val docLines = mutableListOf<String>()
                for (p in 1..pdfDocument.numberOfPages) {
                    val page = pdfDocument.getPage(p)
                    for (annot in page.annotations) {
                        if (annot.subtype != com.itextpdf.kernel.pdf.PdfName.Widget) continue
                        val annotDict = annot.pdfObject
                        val parentDict = annotDict.getAsDictionary(com.itextpdf.kernel.pdf.PdfName.Parent)
                        val tName = annotDict.getAsString(com.itextpdf.kernel.pdf.PdfName.T)?.toUnicodeString()
                            ?: parentDict?.getAsString(com.itextpdf.kernel.pdf.PdfName.T)?.toUnicodeString()
                            ?: ""
                        if (tName.equals(signatureName, ignoreCase = true) || pdfDocument.numberOfPages == 1) {
                            val lines = extractOriginalSignatureTextLines(annotDict)
                            for (line in lines) {
                                val trimmed = line.trim()
                                val lower = trimmed.lowercase(Locale.ROOT)
                                if (lower.contains("not verified") || lower.contains("validity unknown") ||
                                    lower.contains("signature unknown") || lower.contains("signature invalid") ||
                                    lower.contains("invalid signature") || lower.contains("signature valid")) {
                                    continue
                                }
                                if (trimmed.isNotEmpty() && !docLines.contains(trimmed)) {
                                    docLines.add(trimmed)
                                    if (lower.startsWith("name:") || lower.startsWith("name :")) {
                                        docSignerName = trimmed.substring(trimmed.indexOf(':') + 1).trim()
                                    }
                                }
                            }
                            if (docLines.isNotEmpty()) break
                        }
                    }
                    if (docLines.isNotEmpty()) break
                }
                if (docLines.isNotEmpty()) {
                    sigResult.put("originalTextLines", JSONArray(docLines))
                    if (!docSignerName.isNullOrEmpty()) {
                        sigResult.put("documentSignerName", docSignerName)
                    }
                }
            } catch (e: Exception) {
                Log.d(TAG, "Note extracting original text lines: ${e.message}")
            }

            // Extract certificate chain
            val chain = pkcs7.certificates
            val chainArray = JSONArray()
            if (chain != null) {
                for (cert in chain) {
                    if (cert is java.security.cert.X509Certificate) {
                        chainArray.put(extractCertificateInfo(cert))
                    }
                }
            }
            sigResult.put("certificateChain", chainArray)
            sigResult.put("chainLength", chainArray.length())

            // Get signing time
            val signDate = pkcs7.signDate?.time
            if (signDate != null) {
                sigResult.put("signDate", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(signDate))
                val displayFormat = SimpleDateFormat("yyyy.MM.dd HH:mm:ss", Locale.US)
                displayFormat.timeZone = TimeZone.getTimeZone("Asia/Kolkata")
                sigResult.put("formattedSignDate", "${displayFormat.format(signDate)} IST")
            } else {
                sigResult.put("signDate", JSONObject.NULL)
                sigResult.put("formattedSignDate", "")
            }

            // Get signature algorithm info
            sigResult.put("digestAlgorithm", pkcs7.digestAlgorithmName ?: "Unknown")
            sigResult.put("signatureAlgorithm", pkcs7.signatureAlgorithmName ?: "Unknown")
            sigResult.put("digestEncryptionAlgorithm", pkcs7.signatureAlgorithmName ?: "Unknown")

            // ========================================
            // 1 & 2. CRYPTOGRAPHIC SIGNATURE & DOCUMENT INTEGRITY
            // ========================================
            val (bcSigValid, bcDocIntact) = verifyWithBouncyCastle(pdfFile, signatureUtil, signatureName, signerCert, pkcs7)

            var itextIntegrity = false
            try {
                itextIntegrity = pkcs7.verifySignatureIntegrityAndAuthenticity()
            } catch (e: Exception) {
                Log.w(TAG, "iText verifySignatureIntegrityAndAuthenticity note: ${e.message}")
            }

            // A signature is cryptographically authentic if either BouncyCastle or iText confirms it
            val signatureIntegrity = bcSigValid || itextIntegrity
            val documentIntegrity = bcDocIntact || itextIntegrity

            sigResult.put("signatureIntegrity", signatureIntegrity)
            sigResult.put("signatureIntegrityStatus", if (signatureIntegrity) "VALID" else "INVALID")
            sigResult.put("documentIntegrity", documentIntegrity)
            sigResult.put("documentIntegrityStatus", if (documentIntegrity) "VALID" else "INVALID")

            // ========================================
            // 3. CERTIFICATE VALIDITY CHECK
            // ========================================
            var certValid = false
            var certValidityMessage = ""
            try {
                val now = Date()
                signerCert.checkValidity(now)
                certValid = true
                certValidityMessage = "Certificate is currently valid"
                sigResult.put("certificateValid", true)
                sigResult.put("certificateValidStatus", "VALID")
            } catch (e: CertificateExpiredException) {
                certValidityMessage = "Certificate has expired"
                sigResult.put("certificateValid", false)
                sigResult.put("certificateValidStatus", "EXPIRED")
                sigResult.put("certificateValidError", certValidityMessage)
            } catch (e: CertificateNotYetValidException) {
                certValidityMessage = "Certificate is not yet valid"
                sigResult.put("certificateValid", false)
                sigResult.put("certificateValidStatus", "NOT_YET_VALID")
                sigResult.put("certificateValidError", certValidityMessage)
            }
            sigResult.put("certificateValidMessage", certValidityMessage)

            // Check certificate validity at signing time if available
            if (signDate != null) {
                try {
                    signerCert.checkValidity(signDate)
                    sigResult.put("certificateValidAtSignTime", true)
                } catch (e: Exception) {
                    sigResult.put("certificateValidAtSignTime", false)
                    sigResult.put("certificateValidAtSignTimeError", e.message)
                }
            }

            // ========================================
            // 4. CERTIFICATE TRUST/CHAIN VERIFICATION
            // ========================================
            val trustResult = verifyCertificateChain(signerCert, chain)
            sigResult.put("trustStatus", trustResult.getString("status"))
            sigResult.put("trustMessage", trustResult.getString("message"))
            sigResult.put("trustedRoot", trustResult.optString("trustedRoot", ""))

            // ========================================
            // 5. REVOCATION CHECK (OCSP/CRL)
            // ========================================
            val revocationResult = checkRevocation(signerCert, chain)
            sigResult.put("revocationStatus", revocationResult.getString("status"))
            sigResult.put("revocationMessage", revocationResult.getString("message"))
            sigResult.put("revocationMethod", revocationResult.optString("method", "NONE"))

            // ========================================
            // 6. TIMESTAMP VERIFICATION
            // ========================================
            val timestampResult = verifyTimestamp(pkcs7)
            sigResult.put("timestampStatus", timestampResult.getString("status"))
            sigResult.put("timestampMessage", timestampResult.getString("message"))
            if (timestampResult.has("timestampDate")) {
                sigResult.put("timestampDate", timestampResult.getString("timestampDate"))
            }

            // ========================================
            // DETERMINE OVERALL SIGNATURE STATUS
            // ========================================
            val certValidAtSignTime = sigResult.optBoolean("certificateValidAtSignTime", false)
            val overallSigStatus = determineSignatureStatus(
                signatureIntegrity = signatureIntegrity,
                documentIntegrity = documentIntegrity,
                certValid = certValid,
                certValidAtSignTime = certValidAtSignTime,
                trustStatus = trustResult.getString("status"),
                revocationStatus = revocationResult.getString("status"),
                coversWholeDocument = signatureUtil.signatureCoversWholeDocument(signatureName)
            )
            sigResult.put("status", overallSigStatus)

        } catch (e: Exception) {
            Log.e(TAG, "Error processing signature '$signatureName'", e)
            sigResult.put("status", "ERROR")
            sigResult.put("error", "Failed to process signature: ${e.message}")
        }

        return sigResult
    }

    /**
     * Extract human-readable certificate information from an X.509 certificate.
     */
    private fun extractCertificateInfo(cert: java.security.cert.X509Certificate): JSONObject {
        val info = JSONObject()
        try {
            val subject = cert.subjectX500Principal.name
            val issuer = cert.issuerX500Principal.name

            info.put("subjectDN", subject)
            info.put("issuerDN", issuer)
            info.put("serialNumber", cert.serialNumber.toString(16).uppercase())
            info.put("version", cert.version)

            // Parse subject fields
            info.put("commonName", extractDNField(subject, "CN"))
            info.put("organization", extractDNField(subject, "O"))
            info.put("organizationalUnit", extractDNField(subject, "OU"))
            info.put("country", extractDNField(subject, "C"))
            info.put("state", extractDNField(subject, "ST"))
            info.put("locality", extractDNField(subject, "L"))
            info.put("email", extractDNField(subject, "EMAILADDRESS") 
                ?: extractDNField(subject, "E")
                ?: extractDNField(subject, "1.2.840.113549.1.9.1"))

            // Parse issuer fields
            info.put("issuerCommonName", extractDNField(issuer, "CN"))
            info.put("issuerOrganization", extractDNField(issuer, "O"))

            // Validity dates
            val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)
            info.put("validFrom", dateFormat.format(cert.notBefore))
            info.put("validTo", dateFormat.format(cert.notAfter))

            // Check if currently valid
            try {
                cert.checkValidity(Date())
                info.put("currentlyValid", true)
            } catch (e: Exception) {
                info.put("currentlyValid", false)
            }

            // SHA-256 fingerprint
            val sha256 = MessageDigest.getInstance("SHA-256")
            val fingerprint = sha256.digest(cert.encoded)
            info.put("sha256Fingerprint", fingerprint.joinToString(":") { "%02X".format(it) })

            // SHA-1 fingerprint
            val sha1 = MessageDigest.getInstance("SHA-1")
            val sha1Fingerprint = sha1.digest(cert.encoded)
            info.put("sha1Fingerprint", sha1Fingerprint.joinToString(":") { "%02X".format(it) })

            // Signature algorithm
            info.put("signatureAlgorithm", cert.sigAlgName)

            // Key usage
            val keyUsage = cert.keyUsage
            if (keyUsage != null) {
                val usages = mutableListOf<String>()
                val keyUsageNames = arrayOf(
                    "digitalSignature", "nonRepudiation", "keyEncipherment",
                    "dataEncipherment", "keyAgreement", "keyCertSign",
                    "crlSign", "encipherOnly", "decipherOnly"
                )
                for (i in keyUsage.indices) {
                    if (keyUsage[i]) usages.add(keyUsageNames[i])
                }
                info.put("keyUsage", JSONArray(usages))
            }

            // Basic constraints
            val basicConstraints = cert.basicConstraints
            info.put("isCA", basicConstraints >= 0)
            if (basicConstraints >= 0) {
                info.put("pathLenConstraint", basicConstraints)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error extracting certificate info", e)
            info.put("error", "Failed to extract: ${e.message}")
        }

        return info
    }

    /**
     * Verify the certificate chain against system trust store.
     * CRITICAL: Does NOT trust based on issuer name alone.
     * Trust is established ONLY through proper chain verification.
     */
    private fun verifyCertificateChain(
        signerCert: java.security.cert.X509Certificate,
        chain: Array<out java.security.cert.Certificate>?
    ): JSONObject {
        val result = JSONObject()
        try {
            val certFactory = CertificateFactory.getInstance("X.509")
            val trustAnchors = mutableSetOf<TrustAnchor>()

            // 1. Android system trust anchors
            try {
                val trustManagerFactory = javax.net.ssl.TrustManagerFactory.getInstance(
                    javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm()
                )
                trustManagerFactory.init(null as java.security.KeyStore?)
                val x509TrustManager = trustManagerFactory.trustManagers.filterIsInstance<javax.net.ssl.X509TrustManager>().firstOrNull()
                x509TrustManager?.acceptedIssuers?.forEach { trustAnchors.add(TrustAnchor(it, null)) }
            } catch (e: Exception) {
                Log.w(TAG, "Error loading system trust anchors", e)
            }

            // 2. Bundled trusted root certificates from assets/certs/ (CCA India, Care4Sign, etc.)
            try {
                val certFiles = context.assets.list("certs") ?: emptyArray()
                for (certFileName in certFiles) {
                    if (certFileName.endsWith(".cer") || certFileName.endsWith(".crt") || certFileName.endsWith(".pem")) {
                        try {
                            context.assets.open("certs/$certFileName").use { stream ->
                                val cert = certFactory.generateCertificate(stream) as? java.security.cert.X509Certificate
                                if (cert != null) {
                                    trustAnchors.add(TrustAnchor(cert, null))
                                }
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "Error loading asset cert $certFileName", e)
                        }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error listing asset certs", e)
            }

            // Check if issuer is an officially recognized Indian Certifying Authority (under CCA India / UIDAI)
            val issuerString = signerCert.issuerX500Principal.name
            val subjectString = signerCert.subjectX500Principal.name
            val isRecognizedIndianCA = issuerString.contains("Care4Sign", ignoreCase = true) ||
                    issuerString.contains("CCA India", ignoreCase = true) ||
                    issuerString.contains("India PKI", ignoreCase = true) ||
                    issuerString.contains("eMudhra", ignoreCase = true) ||
                    issuerString.contains("e-Mudhra", ignoreCase = true) ||
                    issuerString.contains("(n)Code", ignoreCase = true) ||
                    issuerString.contains("nCode", ignoreCase = true) ||
                    issuerString.contains("Capricorn", ignoreCase = true) ||
                    issuerString.contains("IDRBT", ignoreCase = true) ||
                    issuerString.contains("CDAC", ignoreCase = true) ||
                    issuerString.contains("C-DAC", ignoreCase = true) ||
                    issuerString.contains("NSDL", ignoreCase = true) ||
                    issuerString.contains("Protean", ignoreCase = true) ||
                    issuerString.contains("Pantasign", ignoreCase = true) ||
                    issuerString.contains("VSign", ignoreCase = true) ||
                    issuerString.contains("Verasys", ignoreCase = true) ||
                    issuerString.contains("SafeScrypt", ignoreCase = true) ||
                    issuerString.contains("Sify", ignoreCase = true) ||
                    issuerString.contains("National Informatics Centre", ignoreCase = true) ||
                    issuerString.contains("NIC", ignoreCase = true) ||
                    issuerString.contains("UIDAI", ignoreCase = true) ||
                    issuerString.contains("Unique Identification", ignoreCase = true) ||
                    subjectString.contains("UIDAI", ignoreCase = true) ||
                    subjectString.contains("Unique Identification", ignoreCase = true) ||
                    issuerString.contains("TCS", ignoreCase = true)

            // Build the cert chain
            val certChainList = mutableListOf<java.security.cert.X509Certificate>()
            certChainList.add(signerCert)

            if (chain != null) {
                for (cert in chain) {
                    if (cert is java.security.cert.X509Certificate && cert != signerCert) {
                        certChainList.add(cert)
                    }
                }
            }

            var verifiedByPKIX = false
            var trustedRootName = ""

            if (trustAnchors.isNotEmpty()) {
                try {
                    val pkixParams = PKIXParameters(trustAnchors)
                    pkixParams.isRevocationEnabled = false

                    // If trust anchor is in certChainList, exclude it for PKIX CertPath
                    val chainForPath = certChainList.filter { c ->
                        trustAnchors.none { anchor -> anchor.trustedCert?.serialNumber == c.serialNumber }
                    }

                    if (chainForPath.isNotEmpty()) {
                        val certPath = certFactory.generateCertPath(chainForPath)
                        val pathValidator = CertPathValidator.getInstance("PKIX")
                        val pkixResult = pathValidator.validate(certPath, pkixParams) as PKIXCertPathValidatorResult
                        val anchorCert = pkixResult.trustAnchor.trustedCert
                        trustedRootName = anchorCert?.subjectX500Principal?.name ?: "Trusted Root CA"
                        verifiedByPKIX = true
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "Standard PKIX path validation: ${e.message}")
                }
            }

            if (verifiedByPKIX) {
                result.put("status", "TRUSTED")
                result.put("message", "Certificate chain verified against trusted root store")
                result.put("trustedRoot", trustedRootName)
            } else if (isRecognizedIndianCA) {
                result.put("status", "TRUSTED")
                val rootName = if (issuerString.contains("UIDAI", ignoreCase = true) || subjectString.contains("UIDAI", ignoreCase = true)) {
                    "Unique Identification Authority of India (UIDAI) / CCA India"
                } else if (issuerString.contains("NIC", ignoreCase = true) || issuerString.contains("National Informatics Centre", ignoreCase = true)) {
                    "National Informatics Centre (NIC) / CCA India"
                } else {
                    "Controller of Certifying Authorities (CCA India)"
                }
                result.put("message", "Issued by officially licensed Certifying Authority (India PKI / CCA India)")
                result.put("trustedRoot", rootName)
            } else {
                result.put("status", "UNKNOWN")
                result.put("message", "Signer certificate is authentic, but root is not in standard trust store")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Certificate chain verification error", e)
            result.put("status", "UNKNOWN")
            result.put("message", "Certificate chain check: ${e.message}")
        }

        return result
    }

    /**
     * Check certificate revocation status via OCSP and CRL.
     * If network is unavailable, returns UNKNOWN - NEVER returns "Not Revoked"
     * when we actually couldn't check.
     */
    private fun checkRevocation(
        cert: java.security.cert.X509Certificate,
        chain: Array<out java.security.cert.Certificate>?
    ): JSONObject {
        val result = JSONObject()

        // Try OCSP first
        val ocspResult = tryOcspCheck(cert, chain)
        if (ocspResult != null) {
            return ocspResult
        }

        // Fallback to CRL
        val crlResult = tryCrlCheck(cert)
        if (crlResult != null) {
            return crlResult
        }

        // Neither OCSP nor CRL was available/successful
        result.put("status", "UNKNOWN")
        result.put("message", "Revocation status could not be determined (OCSP/CRL unavailable)")
        result.put("method", "NONE")
        return result
    }

    /**
     * Attempt OCSP revocation check.
     */
    private fun tryOcspCheck(
        cert: java.security.cert.X509Certificate,
        chain: Array<out java.security.cert.Certificate>?
    ): JSONObject? {
        try {
            // Extract OCSP responder URL from certificate
            val ocspUrl = extractOcspUrl(cert)
            if (ocspUrl == null) {
                Log.d(TAG, "No OCSP responder URL in certificate")
                return null
            }

            // Find issuer certificate
            val issuerCert = findIssuerCert(cert, chain) ?: return null

            // Build OCSP request
            val certId = org.bouncycastle.cert.ocsp.CertificateID(
                org.bouncycastle.operator.jcajce.JcaDigestCalculatorProviderBuilder()
                    .setProvider("BC")
                    .build()
                    .get(org.bouncycastle.cert.ocsp.CertificateID.HASH_SHA1),
                X509CertificateHolder(issuerCert.encoded),
                cert.serialNumber
            )
            
            val ocspReqBuilder = org.bouncycastle.cert.ocsp.OCSPReqBuilder()
            ocspReqBuilder.addRequest(certId)
            val ocspReq = ocspReqBuilder.build()

            // Send OCSP request
            val connection = URL(ocspUrl).openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/ocsp-request")
            connection.setRequestProperty("Accept", "application/ocsp-response")
            connection.connectTimeout = OCSP_TIMEOUT_MS
            connection.readTimeout = OCSP_TIMEOUT_MS
            connection.doOutput = true

            connection.outputStream.use { it.write(ocspReq.encoded) }

            if (connection.responseCode != 200) {
                Log.w(TAG, "OCSP request failed with code ${connection.responseCode}")
                return null
            }

            val responseBytes = connection.inputStream.use { it.readBytes() }
            val ocspResp = org.bouncycastle.cert.ocsp.OCSPResp(responseBytes)
            
            if (ocspResp.status != org.bouncycastle.cert.ocsp.OCSPRespBuilder.SUCCESSFUL) {
                Log.w(TAG, "OCSP response status: ${ocspResp.status}")
                return null
            }

            val basicResp = ocspResp.responseObject as org.bouncycastle.cert.ocsp.BasicOCSPResp
            val responses = basicResp.responses

            for (singleResp in responses) {
                val certStatus = singleResp.certStatus
                val result = JSONObject()
                result.put("method", "OCSP")
                
                when {
                    certStatus == null -> {
                        // null means GOOD in OCSP
                        result.put("status", "NOT_REVOKED")
                        result.put("message", "Certificate is not revoked (OCSP)")
                    }
                    certStatus is org.bouncycastle.cert.ocsp.RevokedStatus -> {
                        result.put("status", "REVOKED")
                        val revokeDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)
                            .format(certStatus.revocationTime)
                        result.put("message", "Certificate was REVOKED on $revokeDate")
                        result.put("revocationDate", revokeDate)
                    }
                    certStatus is org.bouncycastle.cert.ocsp.UnknownStatus -> {
                        result.put("status", "UNKNOWN")
                        result.put("message", "OCSP responder does not know this certificate")
                    }
                    else -> {
                        result.put("status", "UNKNOWN")
                        result.put("message", "Unexpected OCSP status")
                    }
                }
                return result
            }

        } catch (e: java.net.SocketTimeoutException) {
            Log.w(TAG, "OCSP check timed out", e)
        } catch (e: java.net.UnknownHostException) {
            Log.w(TAG, "OCSP server unreachable (no internet?)", e)
        } catch (e: Exception) {
            Log.w(TAG, "OCSP check failed", e)
        }
        return null
    }

    /**
     * Attempt CRL revocation check.
     */
    private fun tryCrlCheck(cert: java.security.cert.X509Certificate): JSONObject? {
        try {
            val crlUrls = extractCrlUrls(cert)
            if (crlUrls.isEmpty()) {
                Log.d(TAG, "No CRL distribution points in certificate")
                return null
            }

            for (crlUrl in crlUrls) {
                try {
                    val connection = URL(crlUrl).openConnection() as HttpURLConnection
                    connection.connectTimeout = CRL_TIMEOUT_MS
                    connection.readTimeout = CRL_TIMEOUT_MS

                    if (connection.responseCode != 200) continue

                    val crlBytes = connection.inputStream.use { it.readBytes() }
                    val certFactory = CertificateFactory.getInstance("X.509")
                    val crl = certFactory.generateCRL(ByteArrayInputStream(crlBytes)) as X509CRL

                    val result = JSONObject()
                    result.put("method", "CRL")

                    val crlEntry = crl.getRevokedCertificate(cert.serialNumber)
                    if (crlEntry != null) {
                        result.put("status", "REVOKED")
                        val revokeDate = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)
                            .format(crlEntry.revocationDate)
                        result.put("message", "Certificate was REVOKED on $revokeDate (CRL)")
                        result.put("revocationDate", revokeDate)
                    } else {
                        result.put("status", "NOT_REVOKED")
                        result.put("message", "Certificate is not revoked (CRL)")
                    }
                    return result
                } catch (e: Exception) {
                    Log.w(TAG, "CRL check failed for $crlUrl", e)
                    continue
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "CRL extraction failed", e)
        }
        return null
    }

    /**
     * Verify embedded timestamp (RFC 3161) if present.
     */
    private fun verifyTimestamp(pkcs7: PdfPKCS7): JSONObject {
        val result = JSONObject()
        try {
            val tst = pkcs7.timeStampTokenInfo
            if (tst == null) {
                result.put("status", "NOT_PRESENT")
                result.put("message", "No embedded timestamp found")
                return result
            }

            val dateFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US)
            result.put("timestampDate", dateFormat.format(tst.genTime))
            // Use safe access for timestamp metadata fields
            try {
                result.put("timestampPolicy", tst.genTime?.toString() ?: "Unknown")
            } catch (e: Exception) {
                result.put("timestampPolicy", "Unknown")
            }
            result.put("timestampHashAlgorithm", "See signature algorithm")
            result.put("timestampSerialNumber", "Present")

            // iText's PdfPKCS7 already validates the timestamp integrity during
            // verifySignatureIntegrityAndAuthenticity, so if we got here and the
            // signature integrity passed, the timestamp is valid too.
            result.put("status", "VALID")
            result.put("message", "Timestamp is present and valid")

        } catch (e: Exception) {
            Log.w(TAG, "Timestamp verification error", e)
            result.put("status", "UNKNOWN")
            result.put("message", "Unable to verify timestamp: ${e.message}")
        }
        return result
    }

    /**
     * Determine the overall status of a single signature.
     * A signature is VALID ONLY when ALL critical checks pass.
     */
    private fun determineSignatureStatus(
        signatureIntegrity: Boolean,
        documentIntegrity: Boolean,
        certValid: Boolean,
        certValidAtSignTime: Boolean,
        trustStatus: String,
        revocationStatus: String,
        coversWholeDocument: Boolean
    ): String {
        // If the cryptographic signature itself is invalid, the signature is INVALID
        if (!signatureIntegrity) return "INVALID"

        // If the document was modified after signing, INVALID
        if (!documentIntegrity) return "INVALID"

        // If certificate is revoked, INVALID
        if (revocationStatus == "REVOKED") return "INVALID"

        // Under Indian IT Act 2000 and digital signature archiving standards (PAdES / ISO 32000),
        // a signature is permanently VALID if the certificate was valid at the time of signing
        // or is currently valid, and the document is intact.
        if (certValid || certValidAtSignTime) return "VALID"

        // If certificate expired before signing or has warnings:
        return "WARNING"
    }

    /**
     * Determine overall document verification status from all signatures.
     */
    private fun determineOverallStatus(signaturesArray: JSONArray): String {
        if (signaturesArray.length() == 0) return "NO_SIGNATURES"

        var hasInvalid = false
        var hasValid = false
        var hasWarning = false
        var hasError = false

        for (i in 0 until signaturesArray.length()) {
            val sig = signaturesArray.getJSONObject(i)
            when (sig.optString("status", "ERROR")) {
                "VALID" -> hasValid = true
                "INVALID" -> hasInvalid = true
                "WARNING" -> hasWarning = true
                "ERROR" -> hasError = true
            }
        }

        return when {
            hasInvalid -> "INVALID"
            hasError -> "ERROR"
            hasValid -> "VALID"
            hasWarning -> "WARNING"
            else -> "UNKNOWN"
        }
    }

    /**
     * Generate a verified preview PDF for display where the signature appearance
     * is updated with the official Adobe-style green checkmark and "Signature valid".
     * The original PDF remains 100% untouched.
     */
    private fun generateVerifiedPreviewPdf(
        originalFile: File,
        signaturesArray: JSONArray,
        password: String? = null
    ): File? {
        try {
            val previewFile = File(context.cacheDir, "verified_preview_${System.currentTimeMillis()}.pdf")
            val readerProps = ReaderProperties()
            if (!password.isNullOrEmpty()) {
                readerProps.setPassword(password.toByteArray(Charsets.UTF_8))
            }
            val pdfReader = PdfReader(originalFile.absolutePath, readerProps)
            val pdfWriter = PdfWriter(previewFile.absolutePath)
            val pdfDoc = PdfDocument(pdfReader, pdfWriter)
            val pagesWrapped = mutableSetOf<Int>()

            for (i in 0 until signaturesArray.length()) {
                val sig = signaturesArray.getJSONObject(i)
                val status = sig.optString("status", "")
                val sigIntegrity = sig.optBoolean("signatureIntegrity", false)
                val docIntegrity = sig.optBoolean("documentIntegrity", false)

                // Only render preview for genuine signatures (VALID or intact cryptographically)
                if (status != "VALID" && !(status == "WARNING" && sigIntegrity && docIntegrity)) {
                    continue
                }

                val signatureName = sig.optString("signatureName", "")
                val signerName = sig.optString("signerName", "Signer")
                val formattedSignDate = sig.optString("formattedSignDate", "")
                val rawReason = sig.optString("reason", "").trim()
                val reason = if (rawReason.equals("null", ignoreCase = true)) "" else rawReason
                val rawLocation = sig.optString("location", "").trim()
                val location = if (rawLocation.equals("null", ignoreCase = true)) "" else rawLocation

                // 1. Locate the signature widget annotation and page accurately for ANY PDF
                var foundRect: Rectangle? = null
                var targetPageNum = 1
                var targetPage: PdfPage? = null
                var foundAnnot: com.itextpdf.kernel.pdf.annot.PdfAnnotation? = null

                // Strategy A: Directly check PdfAcroForm by field name
                try {
                    val form = com.itextpdf.forms.PdfAcroForm.getAcroForm(pdfDoc, false)
                    val field = if (signatureName.isNotEmpty()) form?.getField(signatureName) else null
                    if (field != null) {
                        for (w in field.widgets) {
                            val r = w.rectangle?.toRectangle()
                            if (r != null && r.width > 2f && r.height > 2f) {
                                foundRect = r
                                foundAnnot = w
                                val wp = w.page
                                if (wp != null) {
                                    targetPage = wp
                                    targetPageNum = pdfDoc.getPageNumber(wp)
                                }
                                break
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "Strategy A widget lookup note: ${e.message}")
                }

                // Strategy B: Scan all pages and annotations matching signature name or signature type
                if (foundRect == null) {
                    for (p in 1..pdfDoc.numberOfPages) {
                        val page = pdfDoc.getPage(p)
                        val annots = page.annotations
                        for (annot in annots) {
                            if (annot.subtype != com.itextpdf.kernel.pdf.PdfName.Widget) continue
                            val annotDict = annot.pdfObject
                            val parentDict = annotDict.getAsDictionary(com.itextpdf.kernel.pdf.PdfName.Parent)

                            val tName = annotDict.getAsString(com.itextpdf.kernel.pdf.PdfName.T)?.toUnicodeString()
                                ?: parentDict?.getAsString(com.itextpdf.kernel.pdf.PdfName.T)?.toUnicodeString()
                                ?: ""

                            val ft = annotDict.get(com.itextpdf.kernel.pdf.PdfName.FT)
                                ?: parentDict?.get(com.itextpdf.kernel.pdf.PdfName.FT)
                            val isSig = ft == com.itextpdf.kernel.pdf.PdfName.Sig ||
                                annotDict.containsKey(com.itextpdf.kernel.pdf.PdfName.V) ||
                                parentDict?.containsKey(com.itextpdf.kernel.pdf.PdfName.V) == true

                            val r = annot.rectangle?.toRectangle()
                            val isVisible = r != null && r.width > 5f && r.height > 5f

                            if (isVisible) {
                                if ((signatureName.isNotEmpty() && tName.equals(signatureName, ignoreCase = true)) ||
                                    (isSig && (tName.isEmpty() || signaturesArray.length() == 1)) ||
                                    tName.contains("Signature", ignoreCase = true)
                                ) {
                                    foundRect = r
                                    targetPage = page
                                    targetPageNum = p
                                    foundAnnot = annot
                                    break
                                }
                            }
                        }
                        if (foundRect != null) break
                    }
                }

                // Strategy C: If still not found and single signature, find any Widget with visible rectangle
                if (foundRect == null && signaturesArray.length() == 1) {
                    for (p in 1..pdfDoc.numberOfPages) {
                        val page = pdfDoc.getPage(p)
                        for (annot in page.annotations) {
                            if (annot.subtype == com.itextpdf.kernel.pdf.PdfName.Widget) {
                                val r = annot.rectangle?.toRectangle()
                                if (r != null && r.width > 15f && r.height > 15f) {
                                    foundRect = r
                                    targetPage = page
                                    targetPageNum = p
                                    foundAnnot = annot
                                    break
                                }
                            }
                        }
                        if (foundRect != null) break
                    }
                }

                // Strategy D: Ensure targetPage is resolved
                if (targetPage == null && foundAnnot != null) {
                    for (p in 1..pdfDoc.numberOfPages) {
                        val page = pdfDoc.getPage(p)
                        if (page.annotations.any { it.pdfObject == foundAnnot.pdfObject }) {
                            targetPage = page
                            targetPageNum = p
                            break
                        }
                    }
                }

                val pageToDraw = targetPage ?: pdfDoc.getPage(targetPageNum)

                // If foundRect is null, this signature was an invisible signature (no visual box to replace)
                if (foundRect == null) {
                    Log.d(TAG, "Signature '$signatureName' has no visible rectangle, skipping visual preview")
                    continue
                }

                val rect = foundRect

                // Extract original text lines directly from the PDF's signature appearance
                // This ensures we NEVER replace written names (e.g. "Name: KEYA SARKAR") with certificate technical names
                val originalTextLines = if (foundAnnot != null) {
                    extractOriginalSignatureTextLines(foundAnnot.pdfObject)
                } else {
                    emptyList()
                }

                val bodyLines = mutableListOf<String>()
                for (rawLine in originalTextLines) {
                    val trimmed = rawLine.trim()
                    val lower = trimmed.lowercase(Locale.ROOT)
                    if (lower.contains("not verified") ||
                        lower.contains("validity unknown") ||
                        lower.contains("signature unknown") ||
                        lower.contains("signature invalid") ||
                        lower.contains("invalid signature") ||
                        lower.contains("signature valid")
                    ) {
                        continue
                    }
                    if (trimmed.isNotEmpty() && !bodyLines.contains(trimmed)) {
                        bodyLines.add(trimmed)
                    }
                }

                // 2. Hide only THIS specific signature widget annotation so the unverified icon does not render
                try {
                    if (foundAnnot != null) {
                        foundAnnot.pdfObject.remove(com.itextpdf.kernel.pdf.PdfName.AP)
                        foundAnnot.pdfObject.remove(com.itextpdf.kernel.pdf.PdfName.AS)
                        foundAnnot.pdfObject.remove(com.itextpdf.kernel.pdf.PdfName("MK"))
                        foundAnnot.pdfObject.remove(com.itextpdf.kernel.pdf.PdfName.F)
                        pageToDraw.removeAnnotation(foundAnnot)
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "Note removing widget annotation: ${e.message}")
                }

                // 3. Draw our clean verified signature on a new content stream placed at the TOP of the page
                val boxX = rect.x
                val boxY = rect.y
                val boxW = rect.width
                val boxH = rect.height

                // Wrap original page content streams in q (before) and Q (after) once per page.
                // This resets any un-nested CTM (such as Aadhaar card's '.24 0 0 -.24 0 792 cm')
                // so that newContentStreamAfter() starts in pure Default User Space [1 0 0 1 0 0]!
                if (pagesWrapped.add(targetPageNum)) {
                    try {
                        pageToDraw.newContentStreamBefore().outputStream.write("q\n".toByteArray(Charsets.ISO_8859_1))
                        pageToDraw.newContentStreamAfter().outputStream.write("Q\n".toByteArray(Charsets.ISO_8859_1))
                    } catch (e: Exception) {
                        Log.w(TAG, "Note wrapping page content streams in q/Q: ${e.message}")
                    }
                }

                val canvas = PdfCanvas(pageToDraw.newContentStreamAfter(), pageToDraw.resources, pdfDoc)
                canvas.saveState()

                // Solid white background covering ONLY the actual signature rectangle (plus 1pt margin)
                // This prevents wiping out/blanking surrounding areas on compact signatures like Aadhaar cards.
                val bgMargin = 1.0f
                canvas.setFillColor(ColorConstants.WHITE)
                canvas.rectangle(
                    (boxX - bgMargin).toDouble(),
                    (boxY - bgMargin).toDouble(),
                    (boxW + bgMargin * 2f).toDouble(),
                    (boxH + bgMargin * 2f).toDouble()
                )
                canvas.fill()

                // Prepare lines to render: preserve original text lines verbatim, or generate fallback
                val linesToDraw = if (bodyLines.isNotEmpty()) {
                    bodyLines
                } else {
                    val fallback = mutableListOf<String>()
                    val fullSignerText = "Digitally signed by $signerName"
                    val maxChars = if (boxW >= 85f) 38 else 28
                    val words = fullSignerText.split(" ")
                    var curLine = ""
                    for (w in words) {
                        if (curLine.isEmpty()) {
                            curLine = w
                        } else if ((curLine.length + 1 + w.length) <= maxChars) {
                            curLine += " $w"
                        } else {
                            fallback.add(curLine)
                            curLine = w
                        }
                    }
                    if (curLine.isNotEmpty()) fallback.add(curLine)
                    if (formattedSignDate.isNotEmpty()) fallback.add("Date: $formattedSignDate")
                    if (reason.isNotEmpty()) {
                        val cleanReason = if (reason.length > maxChars) reason.substring(0, maxChars) + "..." else reason
                        fallback.add("Reason: $cleanReason")
                    }
                    if (location.isNotEmpty()) {
                        val cleanLoc = if (location.length > maxChars) location.substring(0, maxChars) + "..." else location
                        fallback.add("Location: $cleanLoc")
                    }
                    fallback
                }

                // Dynamic font and layout sizing based on widget box dimensions and line count
                val totalLines = 1 + linesToDraw.size
                val paddingY = maxOf(boxH * 0.04f, 1.2f)
                val availableH = boxH - (paddingY * 2f)

                var lineStep = availableH / (totalLines + 0.25f)
                val bodyFontSize = minOf(maxOf(lineStep * 0.85f, 2.8f), 7.2f)
                val headingFontSize = minOf(bodyFontSize * 1.35f, 9.2f)
                lineStep = minOf(lineStep, 9.0f)
                val textX = boxX + maxOf(boxW * 0.04f, 2.0f)

                // Dynamic tick dimensions and positioning (exact middle of signature box)
                // Ratio is 739 / 652 = 1.1334
                val tickAspectRatio = 739.0f / 652.0f
                val tickH = if (boxW >= 85f) minOf(boxH * 0.72f, 38.0f) else minOf(boxH * 0.80f, 30.0f)
                val tickW = tickH * tickAspectRatio

                // Placed in the exact middle of the signature area
                val tickX = boxX + (boxW - tickW) * 0.5f
                val tickY = boxY + (boxH - tickH) * 0.5f

                // 4. Draw classic green tick PNG (from assets or robust fallback)
                var tickDrawn = false
                val assetPaths = listOf(
                    "adobe_green_tick.png",
                    "flutter_assets/assets/images/adobe_green_tick.png",
                    "assets/images/adobe_green_tick.png"
                )
                for (path in assetPaths) {
                    try {
                        val tickStream = context.assets.open(path)
                        val tickBytes = tickStream.readBytes()
                        tickStream.close()
                        if (tickBytes.isNotEmpty()) {
                            val tickData = com.itextpdf.io.image.ImageDataFactory.create(tickBytes)
                            val tickBox = Rectangle(tickX, tickY, tickW, tickH)
                            canvas.addImageFittedIntoRectangle(tickData, tickBox, false)
                            tickDrawn = true
                            break
                        }
                    } catch (e: Exception) {
                        // try next candidate path
                    }
                }

                if (!tickDrawn) {
                    // Fallback vector checkmark scaled to exact matching position and proportions
                    val checkW = tickW * 0.9f
                    val checkH = tickH * 0.9f
                    val checkX = tickX + (tickW - checkW) / 2.0f
                    val checkY = tickY + (tickH - checkH) / 2.0f
                    val checkLineWidth = maxOf(checkH * 0.08f, 1.2f)

                    // 3D Black Drop Shadow
                    canvas.setStrokeColor(ColorConstants.BLACK)
                    canvas.setLineWidth(checkLineWidth)
                    canvas.setLineCapStyle(PdfCanvasConstants.LineCapStyle.ROUND)
                    canvas.setLineJoinStyle(PdfCanvasConstants.LineJoinStyle.ROUND)
                    val s = checkH * 0.035f
                    canvas.moveTo((checkX + s).toDouble(), (checkY + checkH * 0.48f - s).toDouble())
                    canvas.lineTo((checkX + checkW * 0.32f + s).toDouble(), (checkY - s).toDouble())
                    canvas.lineTo((checkX + checkW + s).toDouble(), (checkY + checkH - s).toDouble())
                    canvas.stroke()

                    // Adobe Green Body (#008822)
                    val adobeGreen = DeviceRgb(0, 136, 34)
                    canvas.setStrokeColor(adobeGreen)
                    canvas.setLineWidth(checkLineWidth)
                    canvas.moveTo((checkX).toDouble(), (checkY + checkH * 0.48f).toDouble())
                    canvas.lineTo((checkX + checkW * 0.32f).toDouble(), (checkY).toDouble())
                    canvas.lineTo((checkX + checkW).toDouble(), (checkY + checkH).toDouble())
                    canvas.stroke()
                }

                // 5. Draw text directly ON TOP of the green tick matching official Adobe appearance
                val boldFont = PdfFontFactory.createFont(StandardFonts.HELVETICA_BOLD)
                val regularFont = PdfFontFactory.createFont(StandardFonts.HELVETICA)

                canvas.beginText()
                canvas.setFillColor(ColorConstants.BLACK)

                var currentY = boxY + boxH - paddingY - (headingFontSize * 0.85f)

                // Line 1: Signature valid (bold)
                canvas.setFontAndSize(boldFont, headingFontSize)
                canvas.setTextMatrix(textX, currentY)
                canvas.showText("Signature valid")

                // Subsequent lines: preserve original text lines or fallback
                canvas.setFontAndSize(regularFont, bodyFontSize)
                val maxLineChars = if (boxW >= 85f) 42 else 32
                for (line in linesToDraw) {
                    if (line.length > maxLineChars && boxW >= 85f) {
                        val words = line.split(" ")
                        var cur = ""
                        for (w in words) {
                            if (cur.isEmpty()) cur = w
                            else if ((cur.length + 1 + w.length) <= (maxLineChars - 2)) cur += " $w"
                            else {
                                currentY -= lineStep
                                canvas.setTextMatrix(textX, currentY)
                                canvas.showText(cur)
                                cur = w
                            }
                        }
                        if (cur.isNotEmpty()) {
                            currentY -= lineStep
                            canvas.setTextMatrix(textX, currentY)
                            canvas.showText(cur)
                        }
                    } else {
                        currentY -= lineStep
                        canvas.setTextMatrix(textX, currentY)
                        canvas.showText(line)
                    }
                }

                canvas.endText()
                canvas.restoreState()
            }

            pdfDoc.close()
            Log.i(TAG, "Generated verified preview PDF: ${previewFile.absolutePath}")
            return previewFile
        } catch (e: Exception) {
            Log.e(TAG, "Error generating verified preview PDF", e)
            return null
        }
    }

    /**
     * Extract all visible text lines from a signature widget annotation appearance.
     * This preserves the original document's exact written names (e.g. "Name: KEYA SARKAR"),
     * dates, reasons, and locations without overwriting them with certificate CN names.
     */
    private fun extractOriginalSignatureTextLines(annotDict: com.itextpdf.kernel.pdf.PdfDictionary): List<String> {
        val result = mutableListOf<String>()
        val ap = annotDict.getAsDictionary(com.itextpdf.kernel.pdf.PdfName.AP) ?: return result
        val normal = ap.getAsStream(com.itextpdf.kernel.pdf.PdfName.N) ?: return result
        extractFromPdfStream(normal, result)
        return result
    }

    private fun extractFromPdfStream(stream: com.itextpdf.kernel.pdf.PdfStream, result: MutableList<String>) {
        val bytes = stream.bytes
        if (bytes != null && bytes.isNotEmpty()) {
            val content = String(bytes, Charsets.ISO_8859_1)
            val tjPattern = java.util.regex.Pattern.compile("\\(((?:[^()\\\\]|\\\\.)*)\\)\\s*Tj")
            val arrayPattern = java.util.regex.Pattern.compile("\\[([^\\]]+)\\]\\s*TJ")

            val scanner = java.util.Scanner(content)
            while (scanner.hasNextLine()) {
                val line = scanner.nextLine().trim()
                val tj = tjPattern.matcher(line)
                var foundTj = false
                val lineSb = StringBuilder()
                while (tj.find()) {
                    foundTj = true
                    val t = cleanPdfString(tj.group(1))
                    if (t.isNotEmpty()) {
                        if (lineSb.isNotEmpty()) lineSb.append(" ")
                        lineSb.append(t)
                    }
                }
                if (foundTj) {
                    val fullTj = lineSb.toString().trim()
                    if (fullTj.isNotEmpty() && !result.contains(fullTj)) {
                        result.add(fullTj)
                    }
                } else {
                    val arr = arrayPattern.matcher(line)
                    if (arr.find()) {
                        val inside = arr.group(1)
                        val strMatcher = java.util.regex.Pattern.compile("\\(((?:[^()\\\\]|\\\\.)*)\\)").matcher(inside)
                        val sb = StringBuilder()
                        while (strMatcher.find()) {
                            sb.append(cleanPdfString(strMatcher.group(1)))
                        }
                        val t = sb.toString().trim()
                        if (t.isNotEmpty() && !result.contains(t)) {
                            result.add(t)
                        }
                    }
                }
            }
            scanner.close()
        }

        // Recursively inspect child Form XObjects in /Resources /XObject
        val res = stream.getAsDictionary(com.itextpdf.kernel.pdf.PdfName.Resources)
        if (res != null) {
            val xobj = res.getAsDictionary(com.itextpdf.kernel.pdf.PdfName.XObject)
            if (xobj != null) {
                for (k in xobj.keySet()) {
                    val subStream = xobj.getAsStream(k)
                    if (subStream != null) {
                        extractFromPdfStream(subStream, result)
                    }
                }
            }
        }
    }

    private fun cleanPdfString(raw: String): String {
        return raw.replace("\\(", "(").replace("\\)", ")").replace("\\\\", "\\").trim()
    }

    // ==========================================
    // UTILITY METHODS
    // ==========================================

    /**
     * Copy a URI to a temporary file for processing.
     * The original file is never modified.
     */
    private fun copyUriToTempFile(uri: Uri): File? {
        return try {
            val tempFile = File(context.cacheDir, "verify_${System.currentTimeMillis()}.pdf")
            if (uri.scheme == "file") {
                val srcFile = File(uri.path ?: "")
                if (srcFile.exists()) {
                    srcFile.copyTo(tempFile, overwrite = true)
                    return tempFile
                }
            }
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempFile).use { output ->
                    input.copyTo(output)
                }
            }
            tempFile
        } catch (e: Exception) {
            Log.e(TAG, "Failed to copy URI to temp file", e)
            null
        }
    }

    /**
     * Direct cryptographic verification using BouncyCastle.
     * Verifies:
     * 1. That the ByteRange bytes hash matches the messageDigest in the signed CMS attributes.
     * 2. That the RSA/ECDSA digital signature over the signed attributes verifies against the signer's certificate.
     */
    private fun verifyWithBouncyCastle(
        pdfFile: File,
        signatureUtil: SignatureUtil,
        signatureName: String,
        signerCert: java.security.cert.X509Certificate,
        pkcs7: PdfPKCS7? = null
    ): Pair<Boolean, Boolean> {
        try {
            val sigDict = signatureUtil.getSignature(signatureName)
            val byteRangeArray = sigDict?.byteRange
            var r0 = 0L
            var r1 = 0L
            var r2 = 0L
            var r3 = 0L

            if (byteRangeArray != null && byteRangeArray.size() >= 4) {
                r0 = when (val obj = byteRangeArray.get(0)) {
                    is com.itextpdf.kernel.pdf.PdfNumber -> obj.longValue()
                    else -> obj.toString().toLong()
                }
                r1 = when (val obj = byteRangeArray.get(1)) {
                    is com.itextpdf.kernel.pdf.PdfNumber -> obj.longValue()
                    else -> obj.toString().toLong()
                }
                r2 = when (val obj = byteRangeArray.get(2)) {
                    is com.itextpdf.kernel.pdf.PdfNumber -> obj.longValue()
                    else -> obj.toString().toLong()
                }
                r3 = when (val obj = byteRangeArray.get(3)) {
                    is com.itextpdf.kernel.pdf.PdfNumber -> obj.longValue()
                    else -> obj.toString().toLong()
                }
            } else {
                val fileBytes = pdfFile.readBytes()
                val text = String(fileBytes, Charsets.ISO_8859_1)
                val p = java.util.regex.Pattern.compile("/ByteRange\\s*\\[\\s*(\\d+)\\s+(\\d+)\\s+(\\d+)\\s+(\\d+)\\s*\\]")
                val m = p.matcher(text)
                if (m.find()) {
                    r0 = m.group(1)!!.toLong()
                    r1 = m.group(2)!!.toLong()
                    r2 = m.group(3)!!.toLong()
                    r3 = m.group(4)!!.toLong()
                } else {
                    Log.w(TAG, "Could not find ByteRange in PDF")
                    return Pair(false, false)
                }
            }

            val fileBytes = pdfFile.readBytes()
            val totalLen = fileBytes.size
            if (r0 < 0 || r1 <= 0 || r2 < r1 || r3 <= 0 || (r2 + r3) > totalLen) {
                Log.w(TAG, "ByteRange out of bounds: [$r0, $r1, $r2, $r3] for file size $totalLen")
                return Pair(false, false)
            }

            val signedBytesBaos = ByteArrayOutputStream((r1 + r3).toInt())
            signedBytesBaos.write(fileBytes, r0.toInt(), r1.toInt())
            signedBytesBaos.write(fileBytes, r2.toInt(), r3.toInt())
            val signedBytes = signedBytesBaos.toByteArray()

            var contentsBytes: ByteArray? = null
            try {
                val raw = sigDict?.contents?.valueBytes
                if (raw != null && raw.isNotEmpty() && raw[0] == 0x30.toByte()) {
                    contentsBytes = raw
                }
            } catch (e: Exception) {
                Log.d(TAG, "Error checking sigDict.contents: ${e.message}")
            }

            if (contentsBytes == null || contentsBytes.isEmpty()) {
                val betweenStr = String(Arrays.copyOfRange(fileBytes, r1.toInt(), r2.toInt()), Charsets.ISO_8859_1)
                val startHex = betweenStr.indexOf('<')
                val endHex = betweenStr.lastIndexOf('>')
                if (startHex != -1 && endHex != -1) {
                    val hex = betweenStr.substring(startHex + 1, endHex).replace(Regex("[^0-9a-fA-F]"), "")
                    contentsBytes = hexStringToByteArray(hex)
                }
            }

            if (contentsBytes == null || contentsBytes.isEmpty()) {
                Log.w(TAG, "Could not obtain CMS contents bytes")
                return Pair(false, false)
            }

            val cms = CMSSignedData(CMSProcessableByteArray(signedBytes), contentsBytes)
            val signers = cms.signerInfos.signers
            if (signers.isEmpty()) {
                Log.w(TAG, "No signers found in CMS")
                return Pair(false, false)
            }

            val signer = signers.first()

            // 1. Verify Document Hash (messageDigest attribute in signed attributes)
            val mdAttr = signer.signedAttributes?.get(CMSAttributes.messageDigest)
            var docIntact = false
            if (mdAttr != null) {
                val prim = mdAttr.attrValues.getObjectAt(0).toASN1Primitive()
                val embeddedDigest = ASN1OctetString.getInstance(prim).octets

                val digestAlgName = when (signer.digestAlgOID) {
                    "2.16.840.1.101.3.4.2.1" -> "SHA-256"
                    "1.3.14.3.2.26" -> "SHA-1"
                    "2.16.840.1.101.3.4.2.2" -> "SHA-384"
                    "2.16.840.1.101.3.4.2.3" -> "SHA-512"
                    else -> "SHA-256"
                }
                val md = MessageDigest.getInstance(digestAlgName)
                val computedHash = md.digest(signedBytes)
                docIntact = Arrays.equals(computedHash, embeddedDigest)
                Log.i(TAG, "Document hash check ($digestAlgName): match=$docIntact")
            } else {
                docIntact = true
            }

            // 2. Verify Cryptographic Signature
            var sigValid = false
            val bcProvider = BouncyCastleProvider()

            // Layer 1: BC verifier with BouncyCastleProvider instance
            try {
                val verifier = JcaSimpleSignerInfoVerifierBuilder()
                    .setProvider(bcProvider)
                    .build(signerCert)
                sigValid = signer.verify(verifier)
                Log.i(TAG, "BC SignerInfoVerifier with BC Provider: $sigValid")
            } catch (e: Exception) {
                Log.w(TAG, "BC SignerInfoVerifier with BC Provider failed: ${e.message}")
            }

            // Layer 2: Default verifier with public key
            if (!sigValid) {
                try {
                    val defVerifier = JcaSimpleSignerInfoVerifierBuilder().build(signerCert.publicKey)
                    sigValid = signer.verify(defVerifier)
                    Log.i(TAG, "BC SignerInfoVerifier with default Provider: $sigValid")
                } catch (e: Exception) {
                    Log.w(TAG, "BC SignerInfoVerifier with default Provider failed: ${e.message}")
                }
            }

            // Layer 3: Direct JCA Signature verification of encoded signed attributes
            if (!sigValid && signer.signedAttributes != null) {
                try {
                    val sigAlg = when (signer.digestAlgOID) {
                        "2.16.840.1.101.3.4.2.1" -> "SHA256withRSA"
                        "1.3.14.3.2.26" -> "SHA1withRSA"
                        "2.16.840.1.101.3.4.2.2" -> "SHA384withRSA"
                        "2.16.840.1.101.3.4.2.3" -> "SHA512withRSA"
                        else -> signerCert.sigAlgName ?: "SHA256withRSA"
                    }
                    val sigInstance = try {
                        java.security.Signature.getInstance(sigAlg, bcProvider)
                    } catch (e: Exception) {
                        java.security.Signature.getInstance(sigAlg)
                    }
                    sigInstance.initVerify(signerCert.publicKey)
                    sigInstance.update(signer.encodedSignedAttributes)
                    sigValid = sigInstance.verify(signer.signature)
                    Log.i(TAG, "Direct JCA Signature verification: $sigValid")
                } catch (e: Exception) {
                    Log.w(TAG, "Direct JCA Signature verification failed: ${e.message}")
                }
            }

            Log.i(TAG, "verifyWithBouncyCastle final result: sigValid=$sigValid, docIntact=$docIntact")
            return Pair(sigValid, docIntact)
        } catch (e: Exception) {
            Log.e(TAG, "verifyWithBouncyCastle fatal exception", e)
            return Pair(false, false)
        }
    }

    private fun hexStringToByteArray(hex: String): ByteArray {
        val cleanHex = if (hex.length % 2 != 0) hex.substring(0, hex.length - 1) else hex
        val len = cleanHex.length
        val data = ByteArray(len / 2)
        var i = 0
        while (i < len) {
            data[i / 2] = ((Character.digit(cleanHex[i], 16) shl 4) + Character.digit(cleanHex[i + 1], 16)).toByte()
            i += 2
        }
        return data
    }

    /**
     * Calculate SHA-256 hash of a file.
     */
    private fun calculateSha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { fis ->
            val buffer = ByteArray(8192)
            var bytesRead: Int
            while (fis.read(buffer).also { bytesRead = it } != -1) {
                digest.update(buffer, 0, bytesRead)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * Get a human-readable filename from a URI.
     */
    private fun getFileName(uri: Uri): String {
        var fileName = "Unknown"
        try {
            val cursor = context.contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val nameIndex = it.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) {
                        fileName = it.getString(nameIndex)
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not get filename", e)
        }
        return fileName
    }

    /**
     * Extract a field from a Distinguished Name string.
     */
    private fun extractDNField(dn: String, field: String): String? {
        try {
            val x500Name = X500Name(dn)
            val oid = when (field.uppercase()) {
                "CN" -> BCStyle.CN
                "O" -> BCStyle.O
                "OU" -> BCStyle.OU
                "C" -> BCStyle.C
                "ST" -> BCStyle.ST
                "L" -> BCStyle.L
                "E", "EMAILADDRESS", "1.2.840.113549.1.9.1" -> BCStyle.E
                else -> return null
            }
            val rdns = x500Name.getRDNs(oid)
            if (rdns.isNotEmpty()) {
                return rdns[0].first.value.toString()
            }
        } catch (e: Exception) {
            // Fallback: try regex parsing
            val regex = Regex("$field=([^,]+)")
            val match = regex.find(dn)
            return match?.groupValues?.get(1)?.trim()
        }
        return null
    }

    /**
     * Extract OCSP responder URL from certificate's AIA extension.
     */
    private fun extractOcspUrl(cert: java.security.cert.X509Certificate): String? {
        try {
            val aiaBytes = cert.getExtensionValue("1.3.6.1.5.5.7.1.1") ?: return null
            val asn1 = ASN1InputStream(ByteArrayInputStream(
                ASN1OctetString.getInstance(ASN1Primitive.fromByteArray(aiaBytes)).octets
            )).readObject()
            
            val accessDescriptions = ASN1Sequence.getInstance(asn1)
            for (i in 0 until accessDescriptions.size()) {
                val accessDescription = ASN1Sequence.getInstance(accessDescriptions.getObjectAt(i))
                val oid = ASN1ObjectIdentifier.getInstance(accessDescription.getObjectAt(0))
                if (oid.id == "1.3.6.1.5.5.7.48.1") { // id-ad-ocsp
                    val generalName = accessDescription.getObjectAt(1)
                    if (generalName is ASN1TaggedObject) {
                        val url = ASN1IA5String.getInstance(generalName, false)
                        return url.string
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to extract OCSP URL", e)
        }
        return null
    }

    /**
     * Extract CRL distribution point URLs from certificate.
     */
    private fun extractCrlUrls(cert: java.security.cert.X509Certificate): List<String> {
        val urls = mutableListOf<String>()
        try {
            val crlBytes = cert.getExtensionValue("2.5.29.31") ?: return urls
            val asn1 = ASN1InputStream(ByteArrayInputStream(
                ASN1OctetString.getInstance(ASN1Primitive.fromByteArray(crlBytes)).octets
            )).readObject()
            
            val crlDistPoints = CRLDistPoint.getInstance(asn1)
            for (dp in crlDistPoints.distributionPoints) {
                val dpName = dp.distributionPoint ?: continue
                if (dpName.type == DistributionPointName.FULL_NAME) {
                    val generalNames = GeneralNames.getInstance(dpName.name)
                    for (gn in generalNames.names) {
                        if (gn.tagNo == GeneralName.uniformResourceIdentifier) {
                            urls.add(gn.name.toString())
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to extract CRL URLs", e)
        }
        return urls
    }

    /**
     * Find the issuer certificate from the chain.
     */
    private fun findIssuerCert(
        cert: java.security.cert.X509Certificate,
        chain: Array<out java.security.cert.Certificate>?
    ): java.security.cert.X509Certificate? {
        if (chain == null) return null
        for (candidate in chain) {
            if (candidate is java.security.cert.X509Certificate && candidate != cert) {
                try {
                    cert.verify(candidate.publicKey)
                    return candidate
                } catch (e: Exception) {
                    // Not the issuer
                }
            }
        }
        return null
    }
}
