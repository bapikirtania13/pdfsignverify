import com.itextpdf.kernel.pdf.*;
import com.itextpdf.signatures.*;
import java.util.*;

public class CheckUploadedPdf {
    public static void main(String[] args) throws Exception {
        String path = "eadhaar_original.pdf";
        PdfReader reader = new PdfReader(path, new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8")));
        PdfDocument doc = new PdfDocument(reader);
        System.out.println("Pages: " + doc.getNumberOfPages());
        for (int p = 1; p <= doc.getNumberOfPages(); p++) {
            PdfPage page = doc.getPage(p);
            System.out.println("Page " + p + ": rotation=" + page.getRotation() + " mediaBox=" + page.getMediaBox());
            for (com.itextpdf.kernel.pdf.annot.PdfAnnotation a : page.getAnnotations()) {
                com.itextpdf.kernel.geom.Rectangle r = a.getRectangle().toRectangle();
                System.out.println("  Annot rect: x=" + r.getX() + " y=" + r.getY() + " w=" + r.getWidth() + " h=" + r.getHeight() + " subtype=" + a.getSubtype());
            }
        }
        SignatureUtil su = new SignatureUtil(doc);
        System.out.println("Sigs: " + su.getSignatureNames());
        for (String s : su.getSignatureNames()) {
            System.out.println("  Sig " + s + " covers whole: " + su.signatureCoversWholeDocument(s));
        }
        doc.close();
    }
}
