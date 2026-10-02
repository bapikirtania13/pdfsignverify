import com.itextpdf.kernel.pdf.*;
import com.itextpdf.kernel.geom.*;
import com.itextpdf.kernel.pdf.canvas.*;
import com.itextpdf.kernel.colors.*;
import com.itextpdf.kernel.font.*;
import com.itextpdf.io.font.constants.StandardFonts;
import java.io.*;

public class TestPreviewGeneration {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(
            new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))),
            new PdfWriter("test_output_preview.pdf")
        );

        PdfPage page = doc.getPage(1);
        System.out.println("Page size: " + page.getPageSize());

        for (com.itextpdf.kernel.pdf.annot.PdfAnnotation annot : page.getAnnotations()) {
            System.out.println("Annot: " + annot.getSubtype() + " rect=" + annot.getRectangle().toRectangle());
        }

        doc.close();
    }
}
