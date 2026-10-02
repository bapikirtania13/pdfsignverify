import com.itextpdf.kernel.pdf.*;
import com.itextpdf.kernel.pdf.canvas.parser.*;
import com.itextpdf.kernel.pdf.canvas.parser.listener.*;
import com.itextpdf.kernel.pdf.canvas.parser.data.*;
import java.util.*;

public class FindAllCoords {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        PdfPage page = doc.getPage(1);
        
        System.out.println("Page MediaBox: " + page.getMediaBox());
        System.out.println("Page CropBox: " + page.getCropBox());
        
        for (com.itextpdf.kernel.pdf.annot.PdfAnnotation a : page.getAnnotations()) {
            com.itextpdf.kernel.geom.Rectangle r = a.getRectangle().toRectangle();
            System.out.printf("Annotation: subtype=%s rect=[x=%.2f, y=%.2f, w=%.2f, h=%.2f]\n", 
                a.getSubtype(), r.getX(), r.getY(), r.getWidth(), r.getHeight());
        }
        
        ITextExtractionStrategy strategy = new ITextExtractionStrategy() {
            @Override
            public void eventOccurred(IEventData data, EventType type) {
                if (type == EventType.RENDER_TEXT) {
                    TextRenderInfo info = (TextRenderInfo) data;
                    String text = info.getText();
                    if (text.contains("Mobile") || text.contains("4114") || text.contains("Unique") || 
                        text.contains("KIRTANIA") || text.contains("Enrolment") || text.contains("Signature")) {
                        com.itextpdf.kernel.geom.LineSegment seg = info.getBaseline();
                        System.out.printf("TEXT: '%s' at x=%.1f, y=%.1f (end x=%.1f, y=%.1f)\n", 
                            text, seg.getStartPoint().get(0), seg.getStartPoint().get(1),
                            seg.getEndPoint().get(0), seg.getEndPoint().get(1));
                    }
                }
            }

            @Override
            public Set<EventType> getSupportedEvents() {
                return Collections.singleton(EventType.RENDER_TEXT);
            }

            @Override
            public String getResultantText() {
                return "";
            }
        };
        
        PdfCanvasProcessor processor = new PdfCanvasProcessor(strategy);
        processor.processPageContent(page);
        
        doc.close();
    }
}
