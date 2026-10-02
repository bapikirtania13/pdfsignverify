import com.itextpdf.kernel.pdf.*;

public class CheckBBoxMatrix {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        int[] ids = {141, 142, 143, 144, 145, 146, 147};
        for (int id : ids) {
            PdfObject obj = doc.getPdfObject(id);
            if (obj != null) {
                System.out.println("Obj #" + id + " type=" + obj.getClass().getSimpleName());
                if (obj.isDictionary() || obj.isStream()) {
                    PdfDictionary d = (PdfDictionary) obj;
                    System.out.println("  keys: " + d.keySet());
                    System.out.println("  BBox: " + d.get(PdfName.BBox));
                    System.out.println("  Matrix: " + d.get(PdfName.Matrix));
                    System.out.println("  Rect: " + d.get(PdfName.Rect));
                }
            }
        }
        doc.close();
    }
}
