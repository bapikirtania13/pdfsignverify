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

public class TestEDistrictVerification {
    public static void main(String[] args) throws Exception {
        String inputPath = "C:/Users/djbap/.gemini/antigravity-ide/brain/6d31ea71-d183-4dc4-8011-4defae57b7d2/.user_uploaded/media_1790880631389.pdf";
        PdfDocument doc = new PdfDocument(
            new PdfReader(inputPath),
            new PdfWriter("test_edistrict_verified.pdf")
        );

        PdfPage page = doc.getPage(1);
        PdfAnnotation foundAnnot = null;
        Rectangle foundRect = null;

        for (PdfAnnotation a : page.getAnnotations()) {
            if (a.getSubtype().equals(PdfName.Widget)) {
                Rectangle r = a.getRectangle().toRectangle();
                if (r.getWidth() > 10 && r.getHeight() > 10) {
                    foundAnnot = a;
                    foundRect = r;
                    break;
                }
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

        List<String> bodyLines = new ArrayList<>();
        bodyLines.add("Digitally signed by NILADRI SARKAR");
        bodyLines.add("Date: 2026.09.28 14:22:10 IST");
        bodyLines.add("Reason: Certificate issuance");
        bodyLines.add("Location: Kolkata, India");

        // 1. Wrap original page content streams in q and Q
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
        System.out.println("Generated test_edistrict_verified.pdf successfully!");
    }
}
