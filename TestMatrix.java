import com.itextpdf.kernel.geom.*;

public class TestMatrix {
    public static void main(String[] args) {
        Matrix m1 = new Matrix(0.24f, 0, 0, -0.24f, 0, 792f);
        Matrix m2 = new Matrix(2.1875f, 0, 0, 2.1875f, 115.625f, 115.625f);
        Matrix combined = m2.multiply(m1);
        System.out.println("Combined matrix: " + combined);
        
        // Point (39, 153)
        Point p1 = new Point(39, 153);
        Point trans1 = transform(combined, 39, 153);
        System.out.println("Point (39, 153) -> " + trans1);
        
        Point trans2 = transform(combined, 39 + 983, 153 + 1192);
        System.out.println("Point (39+983, 153+1192) -> " + trans2);
    }
    
    static Point transform(Matrix m, float x, float y) {
        // [x, y, 1] * Matrix
        float nx = x * m.get(Matrix.I11) + y * m.get(Matrix.I21) + m.get(Matrix.I31);
        float ny = x * m.get(Matrix.I12) + y * m.get(Matrix.I22) + m.get(Matrix.I32);
        return new Point((int)nx, (int)ny);
    }
}
