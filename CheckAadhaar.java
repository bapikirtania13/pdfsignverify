import com.itextpdf.kernel.pdf.*;
import com.itextpdf.signatures.*;
import java.util.*;

public class CheckAadhaar {
    public static void main(String[] args) throws Exception {
        String path = "C:/Users/djbap/.gemini/antigravity-ide/brain/6d31ea71-d183-4dc4-8011-4defae57b7d2/.user_uploaded/media_1790880750305.pdf";
        PdfDocument doc = new PdfDocument(new PdfReader(path));
        SignatureUtil su = new SignatureUtil(doc);
        List<String> names = su.getSignatureNames();
        System.out.println("Signatures count: " + names.size());
        for (String name : names) {
            System.out.println("Signature: " + name);
            PdfPKCS7 pkcs7 = su.readSignatureData(name);
            System.out.println("  SignerName: " + pkcs7.getSignName());
            System.out.println("  SignDate: " + pkcs7.getSignDate());
            System.out.println("  Reason: " + pkcs7.getReason());
            System.out.println("  Location: " + pkcs7.getLocation());
            System.out.println("  verifySignatureIntegrityAndAuthenticity: " + pkcs7.verifySignatureIntegrityAndAuthenticity());
        }
        for (int p = 1; p <= doc.getNumberOfPages(); p++) {
            PdfPage page = doc.getPage(p);
            System.out.println("Page " + p + " annots: " + page.getAnnotations().size());
            for (com.itextpdf.kernel.pdf.annot.PdfAnnotation a : page.getAnnotations()) {
                System.out.println("  Annot: subtype=" + a.getSubtype() + " rect=" + a.getRectangle().toRectangle());
                System.out.println("    dict: " + a.getPdfObject().keySet());
            }
        }
        doc.close();
    }
}
