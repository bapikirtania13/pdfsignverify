import java.io.*;
import java.nio.file.*;
import java.security.*;
import java.security.cert.*;
import java.util.*;
import org.bouncycastle.cms.*;
import org.bouncycastle.cms.jcajce.*;
import org.bouncycastle.cert.*;
import org.bouncycastle.cert.jcajce.*;
import org.bouncycastle.util.Store;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.asn1.cms.Attribute;
import org.bouncycastle.asn1.cms.CMSAttributes;
import org.bouncycastle.asn1.ASN1OctetString;
import org.bouncycastle.asn1.ASN1Primitive;

public class TestVerify {
    public static void main(String[] args) throws Exception {
        Security.addProvider(new BouncyCastleProvider());
        
        String[] files = {
            "C:/Users/djbap/.gemini/antigravity-ide/brain/6d31ea71-d183-4dc4-8011-4defae57b7d2/.user_uploaded/media_1790880631389.pdf",
            "C:/Users/djbap/.gemini/antigravity-ide/brain/6d31ea71-d183-4dc4-8011-4defae57b7d2/.user_uploaded/media_1790880750305.pdf"
        };
        
        for (String filePath : files) {
            System.out.println("\n=======================================================");
            System.out.println("VERIFYING: " + filePath);
            File file = new File(filePath);
            if (!file.exists()) {
                System.out.println("File does not exist!");
                continue;
            }
            byte[] fileBytes = Files.readAllBytes(file.toPath());
            String text = new String(fileBytes, "ISO-8859-1");
            
            // Find ByteRange
            int brIdx = text.indexOf("/ByteRange");
            if (brIdx == -1) {
                System.out.println("No ByteRange found!");
                continue;
            }
            int startBracket = text.indexOf('[', brIdx);
            int endBracket = text.indexOf(']', startBracket);
            String[] parts = text.substring(startBracket + 1, endBracket).trim().split("\\s+");
            int r0 = Integer.parseInt(parts[0]);
            int r1 = Integer.parseInt(parts[1]);
            int r2 = Integer.parseInt(parts[2]);
            int r3 = Integer.parseInt(parts[3]);
            System.out.println("ByteRange: [" + r0 + ", " + r1 + ", " + r2 + ", " + r3 + "]");
            
            // Extract signed bytes (ByteRange portions)
            ByteArrayOutputStream signedBytesBaos = new ByteArrayOutputStream();
            signedBytesBaos.write(fileBytes, r0, r1);
            signedBytesBaos.write(fileBytes, r2, r3);
            byte[] signedBytes = signedBytesBaos.toByteArray();
            System.out.println("Signed byte length: " + signedBytes.length);
            
            // Calculate SHA-256 of signed bytes
            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            byte[] computedHash = sha256.digest(signedBytes);
            System.out.println("Computed SHA-256 of ByteRange: " + bytesToHex(computedHash));
            
            // Also try SHA-1, SHA-384, SHA-512 just in case
            byte[] computedSha1 = MessageDigest.getInstance("SHA-1").digest(signedBytes);
            byte[] computedSha512 = MessageDigest.getInstance("SHA-512").digest(signedBytes);
            
            // Between r1 and r2 is /Contents <hex>
            byte[] between = Arrays.copyOfRange(fileBytes, r1, r2);
            String betweenStr = new String(between, "ISO-8859-1");
            int startHex = betweenStr.indexOf('<');
            int endHex = betweenStr.lastIndexOf('>');
            String hex = betweenStr.substring(startHex + 1, endHex).replaceAll("[\\s\\r\\n]+", "");
            byte[] sigBytes = hexToBytes(hex);
            System.out.println("Signature (/Contents) length: " + sigBytes.length + " bytes");
            
            // Parse CMS with detached content provided!
            CMSSignedData cms = new CMSSignedData(new CMSProcessableByteArray(signedBytes), sigBytes);
            SignerInformationStore signers = cms.getSignerInfos();
            System.out.println("Signer count in CMS: " + signers.size());
            
            for (SignerInformation signer : signers.getSigners()) {
                System.out.println("Signer SID: " + signer.getSID());
                System.out.println("Digest Alg OID: " + signer.getDigestAlgOID());
                System.out.println("Encryption Alg OID: " + signer.getEncryptionAlgOID());
                
                // Check message-digest attribute
                Attribute mdAttr = signer.getSignedAttributes().get(CMSAttributes.messageDigest);
                if (mdAttr != null) {
                    ASN1Primitive prim = mdAttr.getAttrValues().getObjectAt(0).toASN1Primitive();
                    byte[] embeddedDigest = ASN1OctetString.getInstance(prim).getOctets();
                    System.out.println("Embedded MessageDigest attribute in CMS: " + bytesToHex(embeddedDigest));
                    
                    if (Arrays.equals(computedHash, embeddedDigest)) {
                        System.out.println(">>> MATCH! Document hash matches SHA-256 of ByteRange! (Document Intact)");
                    } else if (Arrays.equals(computedSha1, embeddedDigest)) {
                        System.out.println(">>> MATCH! Document hash matches SHA-1 of ByteRange!");
                    } else if (Arrays.equals(computedSha512, embeddedDigest)) {
                        System.out.println(">>> MATCH! Document hash matches SHA-512 of ByteRange!");
                    } else {
                        System.out.println(">>> MISMATCH! Embedded digest does NOT match computed hash!");
                    }
                }
                
                // Get signing certificate
                Store<X509CertificateHolder> certStore = cms.getCertificates();
                Collection<X509CertificateHolder> certs = certStore.getMatches(signer.getSID());
                System.out.println("Matching certs: " + certs.size());
                for (X509CertificateHolder holder : certs) {
                    X509Certificate cert = new JcaX509CertificateConverter().setProvider("BC").getCertificate(holder);
                    System.out.println("Subject: " + cert.getSubjectDN());
                    System.out.println("Issuer: " + cert.getIssuerDN());
                    System.out.println("Not Before: " + cert.getNotBefore());
                    System.out.println("Not After: " + cert.getNotAfter());
                    
                    // Check AIA extension
                    byte[] aia = cert.getExtensionValue("1.3.6.1.5.5.7.1.1");
                    if (aia != null) {
                        System.out.println("AIA extension present! Bytes: " + bytesToHex(aia));
                    }
                    // Check CRL DP extension
                    byte[] crlDp = cert.getExtensionValue("2.5.29.31");
                    if (crlDp != null) {
                        System.out.println("CRL DP extension present! Bytes: " + bytesToHex(crlDp));
                    }
                    
                    // Verify CMS signature with BouncyCastle
                    try {
                        SignerInformationVerifier verifier = new JcaSimpleSignerInfoVerifierBuilder()
                            .setProvider("BC")
                            .build(cert);
                        boolean sigOk = signer.verify(verifier);
                        System.out.println(">>> BouncyCastle signer.verify(verifier): " + sigOk);
                    } catch (Exception e) {
                        System.out.println(">>> BouncyCastle signer.verify exception: " + e.getMessage());
                        e.printStackTrace(System.out);
                    }
                }
                
                // Print all certificates in CMS
                System.out.println("All certs in CMS:");
                for (X509CertificateHolder holder : certStore.getMatches(null)) {
                    System.out.println("  - Subject: " + holder.getSubject());
                    System.out.println("    Issuer:  " + holder.getIssuer());
                }
            }
        }
    }
    
    private static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) sb.append(String.format("%02x", b));
        return sb.toString();
    }
    
    private static byte[] hexToBytes(String hex) {
        int len = hex.length();
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(hex.charAt(i), 16) << 4)
                                 + Character.digit(hex.charAt(i+1), 16));
        }
        return data;
    }
}
