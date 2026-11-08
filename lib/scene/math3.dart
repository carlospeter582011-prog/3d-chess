import 'dart:math' as math;

/// Minimal immutable 3D vector (enough for the camera and picking maths).
class V3 {
  final double x, y, z;
  const V3(this.x, this.y, this.z);
  static const V3 zero = V3(0, 0, 0);
  static const V3 up = V3(0, 1, 0);

  V3 operator +(V3 o) => V3(x + o.x, y + o.y, z + o.z);
  V3 operator -(V3 o) => V3(x - o.x, y - o.y, z - o.z);
  V3 operator *(double s) => V3(x * s, y * s, z * s);
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  V3 cross(V3 o) => V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  double get length => math.sqrt(x * x + y * y + z * z);
  V3 get normalized {
    final l = length;
    return l == 0 ? this : V3(x / l, y / l, z / l);
  }

  double distanceTo(V3 o) => (this - o).length;

  V3 lerp(V3 o, double t) => V3(x + (o.x - x) * t, y + (o.y - y) * t, z + (o.z - z) * t);

  @override
  String toString() => 'V3(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}

double degToRad(double d) => d * math.pi / 180.0;

double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Cubic ease in/out, same curve as the web version.
double easeInOut(double k) => k < 0.5 ? 4 * k * k * k : 1 - math.pow(-2 * k + 2, 3) / 2;
