import com.itextpdf.kernel.pdf.*;

public class CountQ {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        PdfPage page = doc.getPage(1);
        PdfStream s = page.getContentStream(0);
        String str = new String(s.getBytes(), java.nio.charset.StandardCharsets.ISO_8859_1);
        String[] tokens = str.split("\\s+");
        int qCount = 0;
        int QCount = 0;
        for (String t : tokens) {
            if (t.equals("q")) qCount++;
            if (t.equals("Q")) QCount++;
        }
        System.out.println("q count: " + qCount + ", Q count: " + QCount);
        doc.close();
    }
}
