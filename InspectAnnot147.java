import com.itextpdf.kernel.pdf.*;
import java.util.*;

public class InspectAnnot147 {
    public static void main(String[] args) throws Exception {
        PdfDocument doc = new PdfDocument(new PdfReader("eadhaar_original.pdf", new ReaderProperties().setPassword("PASSWORD_HERE".getBytes("UTF-8"))));
        PdfDictionary annot = (PdfDictionary) doc.getPdfObject(147);
        System.out.println("Annot 147 keys: " + annot.keySet());
        System.out.println("  Rect: " + annot.get(PdfName.Rect));
        PdfDictionary ap = annot.getAsDictionary(PdfName.AP);
        System.out.println("  AP: " + (ap != null ? ap.keySet() : "null"));
        if (ap != null) {
            PdfObject n = ap.get(PdfName.N);
            System.out.println("  AP/N type: " + (n != null ? n.getClass().getSimpleName() : "null"));
            if (n instanceof PdfStream) {
                PdfStream s = (PdfStream) n;
                System.out.println("  AP/N keys: " + s.keySet());
                System.out.println("  AP/N BBox: " + s.get(PdfName.BBox));
                System.out.println("  AP/N Matrix: " + s.get(PdfName.Matrix));
                byte[] bytes = s.getBytes();
                if (bytes != null) {
                    System.out.println("  AP/N content: " + new String(bytes));
                }
                PdfDictionary res = s.getAsDictionary(PdfName.Resources);
                if (res != null) {
                    System.out.println("  AP/N Resources: " + res.keySet());
                    PdfDictionary xobj = res.getAsDictionary(PdfName.XObject);
                    if (xobj != null) {
                        System.out.println("  AP/N XObjects: " + xobj.keySet());
                        for (PdfName key : xobj.keySet()) {
                            PdfObject xo = xobj.get(key);
                            System.out.println("    " + key + " type=" + xo.getClass().getSimpleName());
                            if (xo instanceof PdfStream) {
                                PdfStream xs = (PdfStream) xo;
                                System.out.println("      keys: " + xs.keySet());
                                System.out.println("      BBox: " + xs.get(PdfName.BBox));
                                System.out.println("      Matrix: " + xs.get(PdfName.Matrix));
                                byte[] xb = xs.getBytes();
                                if (xb != null) {
                                    System.out.println("      content: " + new String(xb));
                                }
                            }
                        }
                    }
                }
            }
        }
        doc.close();
    }
}
