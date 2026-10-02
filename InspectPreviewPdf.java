import com.itextpdf.kernel.pdf.*;
import java.io.*;

public class InspectPreviewPdf {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_preview.pdf"));
        PdfPage page = doc.getPage(1);
        System.out.println("Preview Page size: " + page.getPageSize());
        System.out.println("Preview stream count: " + page.getContentStreamCount());
        for (int i = 0; i < page.getContentStreamCount(); i++) {
            PdfStream s = page.getContentStream(i);
            byte[] b = s.getBytes();
            System.out.println("Stream " + i + " len=" + (b != null ? b.length : 0));
            if (b != null && b.length > 0) {
                String str = new String(b, java.nio.charset.StandardCharsets.ISO_8859_1);
                System.out.println("--- Stream " + i + " content start ---");
                System.out.println(str.substring(0, Math.min(600, str.length())));
                if (str.length() > 600) {
                    System.out.println("--- Stream " + i + " content end ---");
                    System.out.println(str.substring(str.length() - 600));
                }
            }
        }
        doc.close();
    }
}
