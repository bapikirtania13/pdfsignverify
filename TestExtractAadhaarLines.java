import com.itextpdf.kernel.pdf.*;
import java.util.*;

public class TestExtractAadhaarLines {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        PdfPage page = doc.getPage(1);
        for (com.itextpdf.kernel.pdf.annot.PdfAnnotation a : page.getAnnotations()) {
            if (a.getSubtype().equals(PdfName.Widget)) {
                List<String> lines = new ArrayList<>();
                PdfDictionary ap = a.getPdfObject().getAsDictionary(PdfName.AP);
                if (ap != null) {
                    PdfStream normal = ap.getAsStream(PdfName.N);
                    if (normal != null) {
                        extractFromStream(normal, lines);
                    }
                }
                System.out.println("Extracted lines count: " + lines.size());
                for (String l : lines) {
                    System.out.println("  LINE: [" + l + "]");
                }
            }
        }
        doc.close();
    }

    private static void extractFromStream(PdfStream stream, List<String> result) {
        byte[] bytes = stream.getBytes();
        if (bytes != null && bytes.length > 0) {
            String content = new String(bytes, java.nio.charset.StandardCharsets.ISO_8859_1);
            java.util.regex.Pattern tjPattern = java.util.regex.Pattern.compile("\\(((?:[^()\\\\]|\\\\.)*)\\)\\s*Tj");
            java.util.regex.Pattern arrayPattern = java.util.regex.Pattern.compile("\\[([^\\]]+)\\]\\s*TJ");

            Scanner scanner = new Scanner(content);
            while (scanner.hasNextLine()) {
                String line = scanner.nextLine().trim();
                java.util.regex.Matcher tj = tjPattern.matcher(line);
                boolean foundTj = false;
                StringBuilder lineSb = new StringBuilder();
                while (tj.find()) {
                    foundTj = true;
                    String t = cleanPdfString(tj.group(1));
                    if (!t.isEmpty()) {
                        if (lineSb.length() > 0) lineSb.append(" ");
                        lineSb.append(t);
                    }
                }
                if (foundTj) {
                    String fullTj = lineSb.toString().trim();
                    if (!fullTj.isEmpty() && !result.contains(fullTj)) {
                        result.add(fullTj);
                    }
                } else {
                    java.util.regex.Matcher arr = arrayPattern.matcher(line);
                    if (arr.find()) {
                        String inside = arr.group(1);
                        java.util.regex.Matcher strMatcher = java.util.regex.Pattern.compile("\\(((?:[^()\\\\]|\\\\.)*)\\)").matcher(inside);
                        StringBuilder sb = new StringBuilder();
                        while (strMatcher.find()) {
                            sb.append(cleanPdfString(strMatcher.group(1)));
                        }
                        String t = sb.toString().trim();
                        if (!t.isEmpty() && !result.contains(t)) {
                            result.add(t);
                        }
                    }
                }
            }
            scanner.close();
        }

        PdfDictionary res = stream.getAsDictionary(PdfName.Resources);
        if (res != null) {
            PdfDictionary xobj = res.getAsDictionary(PdfName.XObject);
            if (xobj != null) {
                for (PdfName k : xobj.keySet()) {
                    PdfStream subStream = xobj.getAsStream(k);
                    if (subStream != null) {
                        extractFromStream(subStream, result);
                    }
                }
            }
        }
    }

    private static String cleanPdfString(String raw) {
        return raw.replace("\\(", "(").replace("\\)", ")").replace("\\\\", "\\").trim();
    }
}
