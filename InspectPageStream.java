import com.itextpdf.kernel.pdf.*;
import java.io.*;

public class InspectPageStream {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        PdfPage page = doc.getPage(1);
        System.out.println("Page content streams count: " + page.getContentStreamCount());
        for (int i = 0; i < page.getContentStreamCount(); i++) {
            PdfStream s = page.getContentStream(i);
            byte[] b = s.getBytes();
            System.out.println("Stream " + i + " len=" + (b != null ? b.length : 0));
            if (b != null && b.length > 0) {
                String str = new String(b, java.nio.charset.StandardCharsets.ISO_8859_1);
                // Print first 500 chars and last 500 chars
                System.out.println("Start of stream " + i + ":\n" + str.substring(0, Math.min(500, str.length())));
                if (str.length() > 500) {
                    System.out.println("End of stream " + i + ":\n" + str.substring(str.length() - 500));
                }
            }
        }
        
        // Check if there are form XObjects or if the page has a matrix
        PdfDictionary pageDict = page.getPdfObject();
        System.out.println("Page keys: " + pageDict.keySet());
        
        doc.close();
    }
}
