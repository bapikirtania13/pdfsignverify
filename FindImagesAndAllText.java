import com.itextpdf.kernel.pdf.*;
import com.itextpdf.kernel.pdf.canvas.parser.*;
import com.itextpdf.kernel.pdf.canvas.parser.listener.*;
import com.itextpdf.kernel.pdf.canvas.parser.data.*;
import java.util.*;

public class FindImagesAndAllText {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        PdfPage page = doc.getPage(1);
        
        IEventListener listener = new IEventListener() {
            @Override
            public void eventOccurred(IEventData data, EventType type) {
                if (type == EventType.RENDER_IMAGE) {
                    ImageRenderInfo info = (ImageRenderInfo) data;
                    com.itextpdf.kernel.geom.Matrix m = info.getImageCtm();
                    System.out.printf("IMAGE at x=%.1f, y=%.1f, w=%.1f, h=%.1f\n", 
                        m.get(com.itextpdf.kernel.geom.Matrix.I31), 
                        m.get(com.itextpdf.kernel.geom.Matrix.I32),
                        m.get(com.itextpdf.kernel.geom.Matrix.I11),
                        m.get(com.itextpdf.kernel.geom.Matrix.I22));
                } else if (type == EventType.RENDER_TEXT) {
                    TextRenderInfo info = (TextRenderInfo) data;
                    String t = info.getText();
                    if (t.contains("4114") || t.contains("Aadhaar") || t.contains("VID") || t.contains("Signature") || t.contains("Not Verified") || t.contains("Digitally")) {
                        com.itextpdf.kernel.geom.LineSegment seg = info.getBaseline();
                        System.out.printf("TEXT '%s' at x=%.1f, y=%.1f\n", t, seg.getStartPoint().get(0), seg.getStartPoint().get(1));
                    }
                }
            }

            @Override
            public Set<EventType> getSupportedEvents() {
                Set<EventType> s = new HashSet<>();
                s.add(EventType.RENDER_IMAGE);
                s.add(EventType.RENDER_TEXT);
                return s;
            }
        };
        
        PdfCanvasProcessor p = new PdfCanvasProcessor(listener);
        p.processPageContent(page);
        doc.close();
    }
}
