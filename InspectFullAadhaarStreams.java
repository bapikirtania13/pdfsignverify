import com.itextpdf.kernel.pdf.*;

public class InspectFullAadhaarStreams {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("test_full_verified_aadhaar.pdf"));
        PdfPage page = doc.getPage(1);
        System.out.println("Stream count: " + page.getContentStreamCount());
        for (int i = 0; i < page.getContentStreamCount(); i++) {
            PdfStream s = page.getContentStream(i);
            byte[] b = s.getBytes();
            System.out.println("Stream " + i + " len=" + (b != null ? b.length : 0));
            if (b != null && b.length > 0) {
                String str = new String(b, java.nio.charset.StandardCharsets.ISO_8859_1);
                if (b.length < 500) {
                    System.out.println("  " + str);
                } else {
                    System.out.println("  start: " + str.substring(0, 100));
                    System.out.println("  end: " + str.substring(str.length() - 100));
                }
            }
        }
        System.out.println("Annots count: " + page.getAnnotations().size());
        doc.close();
    }
}
