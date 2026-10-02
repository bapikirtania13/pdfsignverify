import com.itextpdf.kernel.pdf.*;
import java.util.*;

public class TestExtraction {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        PdfPage page = doc.getPage(1);
        for (com.itextpdf.kernel.pdf.annot.PdfAnnotation a : page.getAnnotations()) {
            List<String> res = new ArrayList<>();
            extractOriginal(a.getPdfObject(), res);
            System.out.println("Extracted lines: " + res);
        }
        doc.close();
    }

    static void extractOriginal(PdfDictionary dict, List<String> res) {
        PdfDictionary ap = dict.getAsDictionary(PdfName.AP);
        if (ap == null) return;
        PdfStream n = ap.getAsStream(PdfName.N);
        if (n == null) return;
        extractFromStream(n, res);
    }

    static void extractFromStream(PdfStream s, List<String> res) {
        byte[] b = s.getBytes();
        if (b != null) {
            String content = new String(b, java.nio.charset.StandardCharsets.ISO_8859_1);
            java.util.regex.Pattern tjPattern = java.util.regex.Pattern.compile("\\(((?:[^()\\\\]|\\\\.)*)\\)\\s*Tj");
            java.util.Scanner scanner = new java.util.Scanner(content);
            while (scanner.hasNextLine()) {
                String line = scanner.nextLine().trim();
                java.util.regex.Matcher m = tjPattern.matcher(line);
                StringBuilder sb = new StringBuilder();
                boolean found = false;
                while (m.find()) {
                    found = true;
                    String t = m.group(1).trim();
                    if (!t.isEmpty()) {
                        if (sb.length() > 0) sb.append(" ");
                        sb.append(t);
                    }
                }
                if (found) {
                    String full = sb.toString().trim();
                    if (!full.isEmpty() && !res.contains(full)) res.add(full);
                }
            }
            scanner.close();
        }
        PdfDictionary resources = s.getAsDictionary(PdfName.Resources);
        if (resources != null) {
            PdfDictionary xobj = resources.getAsDictionary(PdfName.XObject);
            if (xobj != null) {
                for (PdfName k : xobj.keySet()) {
                    PdfStream sub = xobj.getAsStream(k);
                    if (sub != null) extractFromStream(sub, res);
                }
            }
        }
    }
}
