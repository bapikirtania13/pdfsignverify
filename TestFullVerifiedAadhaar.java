import com.itextpdf.kernel.pdf.*;
import com.itextpdf.kernel.pdf.annot.*;
import com.itextpdf.kernel.geom.*;
import com.itextpdf.kernel.pdf.canvas.*;
import com.itextpdf.kernel.colors.*;
import com.itextpdf.kernel.font.*;
import com.itextpdf.io.font.constants.StandardFonts;
import com.itextpdf.io.image.ImageDataFactory;
import java.io.*;
import java.nio.file.*;
import java.util.*;

public class TestFullVerifiedAadhaar {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(
            new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))),
            new PdfWriter("test_full_verified_aadhaar.pdf")
        );

        PdfPage page = doc.getPage(1);
        PdfAnnotation foundAnnot = null;
        Rectangle foundRect = null;

        for (PdfAnnotation a : page.getAnnotations()) {
            if (a.getSubtype().equals(PdfName.Widget)) {
                foundAnnot = a;
                foundRect = a.getRectangle().toRectangle();
                break;
            }
        }

        if (foundRect == null) {
            System.out.println("No widget found!");
            doc.close();
            return;
        }

        System.out.println("Found widget rect: " + foundRect);
        float boxX = foundRect.getX();
        float boxY = foundRect.getY();
        float boxW = foundRect.getWidth();
        float boxH = foundRect.getHeight();

        // Extract original lines from widget appearance if available
        List<String> bodyLines = new ArrayList<>();
        bodyLines.add("Digitally signed by DS Unique");
        bodyLines.add("Identification Authority of India");
        bodyLines.add("06");
        bodyLines.add("Date: 2026.10.02 16:18:04");
        bodyLines.add("IST");

        // 1. Wrap original page content streams in q and Q
        // This resets any un-nested CTM (like Aadhaar's .24 0 0 -.24 0 792 cm)
        // so that newContentStreamAfter() starts in pure Default User Space [1 0 0 1 0 0]!
        page.newContentStreamBefore().getOutputStream().write("q\n".getBytes("ISO-8859-1"));
        page.newContentStreamAfter().getOutputStream().write("Q\n".getBytes("ISO-8859-1"));

        // 2. Remove the old unverified annotation
        page.removeAnnotation(foundAnnot);

        // 3. Draw verified signature on a new content stream in pure Default User Space
        PdfCanvas canvas = new PdfCanvas(page.newContentStreamAfter(), page.getResources(), doc);
        canvas.saveState();

        // White background
        float bgMargin = 1.0f;
        canvas.setFillColor(ColorConstants.WHITE);
        canvas.rectangle(
            (boxX - bgMargin),
            (boxY - bgMargin),
            (boxW + bgMargin * 2f),
            (boxH + bgMargin * 2f)
        );
        canvas.fill();

        // Tick dimensions
        float tickAspectRatio = 739.0f / 652.0f;
        float tickH = (boxW >= 85f) ? Math.min(boxH * 0.72f, 38.0f) : Math.min(boxH * 0.80f, 30.0f);
        float tickW = tickH * tickAspectRatio;

        float textX = boxX + Math.max(boxW * 0.04f, 2.0f);
        // Exact middle of the signature box area
        float tickX = boxX + (boxW - tickW) * 0.5f;
        float tickY = boxY + (boxH - tickH) * 0.5f;

        // Draw green tick PNG
        byte[] tickBytes = Files.readAllBytes(Paths.get("assets/images/adobe_green_tick.png"));
        canvas.addImageFittedIntoRectangle(ImageDataFactory.create(tickBytes), new Rectangle(tickX, tickY, tickW, tickH), false);

        // Draw text
        PdfFont boldFont = PdfFontFactory.createFont(StandardFonts.HELVETICA_BOLD);
        PdfFont regularFont = PdfFontFactory.createFont(StandardFonts.HELVETICA);

        float totalLines = 1 + bodyLines.size();
        float paddingY = Math.max(boxH * 0.04f, 1.2f);
        float availableH = boxH - (paddingY * 2f);
        float lineStep = availableH / (totalLines + 0.25f);
        float bodyFontSize = Math.min(Math.max(lineStep * 0.85f, 2.8f), 7.2f);
        float headingFontSize = Math.min(bodyFontSize * 1.35f, 9.2f);
        lineStep = Math.min(lineStep, 9.0f);

        canvas.beginText();
        canvas.setFillColor(ColorConstants.BLACK);

        float currentY = boxY + boxH - paddingY - (headingFontSize * 0.85f);
        canvas.setFontAndSize(boldFont, headingFontSize);
        canvas.setTextMatrix(textX, currentY);
        canvas.showText("Signature valid");

        canvas.setFontAndSize(regularFont, bodyFontSize);
        for (String line : bodyLines) {
            currentY -= lineStep;
            canvas.setTextMatrix(textX, currentY);
            canvas.showText(line);
        }

        canvas.endText();
        canvas.restoreState();

        doc.close();
        System.out.println("Generated test_full_verified_aadhaar.pdf successfully!");
    }
}
