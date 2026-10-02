import com.itextpdf.kernel.pdf.*;
import com.itextpdf.kernel.geom.*;

public class CheckPageGeom {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        for (int p = 1; p <= doc.getNumberOfPages(); p++) {
            PdfPage page = doc.getPage(p);
            System.out.println("Page " + p + ":");
            System.out.println("  Rotation: " + page.getRotation());
            System.out.println("  MediaBox: " + page.getMediaBox());
            System.out.println("  CropBox: " + page.getCropBox());
            System.out.println("  PageSize: " + page.getPageSize());
            System.out.println("  PageSizeWithRotation: " + page.getPageSizeWithRotation());
            for (com.itextpdf.kernel.pdf.annot.PdfAnnotation a : page.getAnnotations()) {
                System.out.println("  Annot rect: " + a.getRectangle().toRectangle());
            }
        }
        doc.close();
    }
}
