import com.itextpdf.kernel.pdf.*;
import com.itextpdf.kernel.geom.*;
import com.itextpdf.kernel.pdf.canvas.*;
import com.itextpdf.kernel.colors.*;
import java.io.*;

public class TestGraphicsStateReset {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(
            new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))),
            new PdfWriter("test_q_reset.pdf")
        );

        PdfPage page = doc.getPage(1);
        System.out.println("Original stream count: " + page.getContentStreamCount());

        // Prepend 'q\n' stream before all existing streams
        PdfStream startStream = new PdfStream("q\n".getBytes("ISO-8859-1"));
        page.newContentStreamBefore().getOutputStream().write("q\n".getBytes("ISO-8859-1"));

        // Append 'Q\n' stream after all existing streams
        page.newContentStreamAfter().getOutputStream().write("Q\n".getBytes("ISO-8859-1"));

        // Now add our drawing stream
        PdfCanvas canvas = new PdfCanvas(page.newContentStreamAfter(), page.getResources(), doc);
        canvas.saveState();
        canvas.setFillColor(new DeviceRgb(255, 0, 0)); // Red test box
        canvas.rectangle(80, 339, 50, 30);
        canvas.fill();
        canvas.restoreState();

        doc.close();
        System.out.println("Successfully created test_q_reset.pdf");
    }
}
