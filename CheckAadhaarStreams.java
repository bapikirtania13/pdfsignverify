import com.itextpdf.kernel.pdf.*;
public class CheckAadhaarStreams {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        PdfPage page = doc.getPage(1);
        System.out.println("Page 1 streams: " + page.getContentStreamCount());
        for (int i = 0; i < page.getContentStreamCount(); i++) {
            System.out.println("Stream " + i + " length: " + page.getContentStream(i).getBytes().length);
        }
        System.out.println("Page 1 annots: " + page.getAnnotations().size());
        for (com.itextpdf.kernel.pdf.annot.PdfAnnotation a : page.getAnnotations()) {
            System.out.println("  Annot subtype=" + a.getSubtype() + " rect=" + a.getRectangle().toRectangle());
        }
        doc.close();
    }
}
