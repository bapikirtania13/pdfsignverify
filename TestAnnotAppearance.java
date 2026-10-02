import com.itextpdf.kernel.pdf.*;
import com.itextpdf.kernel.pdf.annot.*;
import com.itextpdf.kernel.pdf.xobject.*;
import com.itextpdf.kernel.pdf.canvas.*;
import com.itextpdf.kernel.colors.*;
import com.itextpdf.kernel.geom.*;
import com.itextpdf.kernel.font.*;
import com.itextpdf.io.font.constants.StandardFonts;
import java.io.*;

public class TestAnnotAppearance {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(
            new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))),
            new PdfWriter("test_annot_verified.pdf")
        );

        PdfPage page = doc.getPage(1);
        PdfAnnotation annot = page.getAnnotations().get(0);
        Rectangle r = annot.getRectangle().toRectangle();
        System.out.println("Annot rect: " + r);
        float w = r.getWidth();
        float h = r.getHeight();

        PdfFormXObject xobj = new PdfFormXObject(new Rectangle(w, h));
        PdfCanvas canvas = new PdfCanvas(xobj, doc);

        // White background
        canvas.setFillColor(ColorConstants.WHITE);
        canvas.rectangle(0, 0, w, h);
        canvas.fill();

        // Draw green checkmark vector
        float checkW = w * 0.4f;
        float checkH = h * 0.6f;
        float checkX = (w - checkW) / 2f;
        float checkY = (h - checkH) / 2f;

        canvas.setStrokeColor(new DeviceRgb(0, 136, 34));
        canvas.setLineWidth(1.5f);
        canvas.moveTo(checkX, checkY + checkH * 0.48f);
        canvas.lineTo(checkX + checkW * 0.32f, checkY);
        canvas.lineTo(checkX + checkW, checkY + checkH);
        canvas.stroke();

        // Text
        PdfFont boldFont = PdfFontFactory.createFont(StandardFonts.HELVETICA_BOLD);
        PdfFont regFont = PdfFontFactory.createFont(StandardFonts.HELVETICA);

        canvas.beginText();
        canvas.setFillColor(ColorConstants.BLACK);
        canvas.setFontAndSize(boldFont, 5f);
        canvas.setTextMatrix(2, h - 6);
        canvas.showText("Signature valid");

        canvas.setFontAndSize(regFont, 3.5f);
        canvas.setTextMatrix(2, h - 11);
        canvas.showText("Digitally signed by UIDAI");
        canvas.endText();

        annot.setNormalAppearance(xobj.getPdfObject());

        doc.close();
        System.out.println("Saved test_annot_verified.pdf successfully!");
    }
}
