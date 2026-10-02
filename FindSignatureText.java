import com.itextpdf.kernel.pdf.*;
import java.util.*;

public class FindSignatureText {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        int numObjects = doc.getNumberOfPdfObjects();
        System.out.println("Total PDF objects: " + numObjects);
        
        for (int i = 1; i <= numObjects; i++) {
            PdfObject obj = doc.getPdfObject(i);
            if (obj == null) continue;
            if (obj.isStream()) {
                PdfStream s = (PdfStream) obj;
                byte[] b = s.getBytes();
                if (b != null) {
                    String str = new String(b, java.nio.charset.StandardCharsets.ISO_8859_1);
                    if (str.contains("Signature Not Verified") || str.contains("Digitally signed")) {
                        System.out.println("Found in Stream obj #" + i + " length=" + b.length);
                        System.out.println("Dictionary: " + s.keySet());
                        System.out.println("Content: " + str);
                    }
                }
            } else if (obj.isDictionary()) {
                PdfDictionary d = (PdfDictionary) obj;
                String str = d.toString();
                if (str.contains("Signature Not Verified") || str.contains("Digitally signed")) {
                    System.out.println("Found in Dict obj #" + i + ": " + str);
                }
            }
        }
        
        // Check ALL annotations on Page 1
        PdfPage page = doc.getPage(1);
        System.out.println("Page 1 annotations: " + page.getAnnotations().size());
        for (com.itextpdf.kernel.pdf.annot.PdfAnnotation a : page.getAnnotations()) {
            System.out.println("Annot obj #" + a.getPdfObject().getIndirectReference());
            System.out.println("  Rect: " + a.getRectangle().toRectangle());
            System.out.println("  Dict: " + a.getPdfObject());
        }
        
        doc.close();
    }
}
