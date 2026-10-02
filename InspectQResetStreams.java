import com.itextpdf.kernel.pdf.*;

public class InspectQResetStreams {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("test_q_reset.pdf"));
        PdfPage page = doc.getPage(1);
        System.out.println("Stream count: " + page.getContentStreamCount());
        for (int i = 0; i < page.getContentStreamCount(); i++) {
            PdfStream s = page.getContentStream(i);
            byte[] b = s.getBytes();
            System.out.println("Stream " + i + " len=" + (b != null ? b.length : 0));
            if (b != null && b.length > 0) {
                String str = new String(b, java.nio.charset.StandardCharsets.ISO_8859_1);
                System.out.println("  Content: " + (str.length() > 60 ? str.substring(0, 60) + "..." : str.trim()));
            }
        }
        doc.close();
    }
}
