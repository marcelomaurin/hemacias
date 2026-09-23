"""
Testes sintéticos de calibração óptica e morfometria celular para validação metrológica.
Cobre calibração teórica, resize digital, calibração física, anisotropia e PCA invariante à rotação.
"""
import math
import unittest


def calculate_theoretical_scale(obj_mag: float, adapter_mag: float, sensor_pixel_um: float) -> float:
    mag = max(0.01, obj_mag * adapter_mag)
    return sensor_pixel_um / mag


def calculate_resize_factor(acq_size: int, ana_size: int) -> float:
    if acq_size <= 0 or ana_size <= 0:
        return 1.0
    return acq_size / ana_size


def calibrate_from_line(known_um: float, dist_px: float) -> float:
    if dist_px < 2.0 or known_um <= 0.0:
        return 0.0
    return known_um / dist_px


def calculate_pca_axes(points):
    """
    Calcula eixos maior e menor via PCA (matriz de covariancia 2x2) de um conjunto de vertices 2D.
    """
    n = len(points)
    if n < 3:
        return 0.0, 0.0, 1.0

    mean_x = sum(p[0] for p in points) / n
    mean_y = sum(p[1] for p in points) / n

    var_x = sum((p[0] - mean_x) ** 2 for p in points) / n
    var_y = sum((p[1] - mean_y) ** 2 for p in points) / n
    cov_xy = sum((p[0] - mean_x) * (p[1] - mean_y) for p in points) / n

    theta = 0.5 * math.atan2(2.0 * cov_xy, var_x - var_y)
    cos_t = math.cos(theta)
    sin_t = math.sin(theta)

    proj1 = [p[0] * cos_t + p[1] * sin_t for p in points]
    proj2 = [-p[0] * sin_t + p[1] * cos_t for p in points]

    major = max(proj1) - min(proj1)
    minor = max(proj2) - min(proj2)
    if minor > major:
        major, minor = minor, major

    aspect = major / max(0.001, minor)
    return major, minor, aspect


def generate_ellipse_polygon(cx: float, cy: float, a: float, b: float, angle_deg: float, n_points: int = 120):
    rad = math.radians(angle_deg)
    cos_a = math.cos(rad)
    sin_a = math.sin(rad)
    pts = []
    for i in range(n_points):
        t = 2.0 * math.pi * i / n_points
        x_raw = a * math.cos(t)
        y_raw = b * math.sin(t)
        x_rot = cx + (x_raw * cos_a - y_raw * sin_a)
        y_rot = cy + (x_raw * sin_a + y_raw * cos_a)
        pts.append((x_rot, y_rot))
    return pts


def polygon_area(points):
    n = len(points)
    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += points[i][0] * points[j][1] - points[j][0] * points[i][1]
    return abs(area) * 0.5


def polygon_perimeter(points):
    n = len(points)
    p = 0.0
    for i in range(n):
        j = (i + 1) % n
        dx = points[j][0] - points[i][0]
        dy = points[j][1] - points[i][1]
        p += math.hypot(dx, dy)
    return p


class TestMorphometryMath(unittest.TestCase):
    # Tarefa 69: Teste para 40x sem resize
    def test_theoretical_scale_40x_no_resize(self):
        scale = calculate_theoretical_scale(obj_mag=40.0, adapter_mag=1.0, sensor_pixel_um=3.45)
        self.assertAlmostEqual(scale, 0.08625, places=5)

    # Tarefa 70: Teste para adaptador 0.5x
    def test_theoretical_scale_adapter_05x(self):
        scale = calculate_theoretical_scale(obj_mag=40.0, adapter_mag=0.5, sensor_pixel_um=3.45)
        self.assertAlmostEqual(scale, 0.1725, places=4)

    # Tarefa 71: Teste para adaptador 2x
    def test_theoretical_scale_adapter_2x(self):
        scale = calculate_theoretical_scale(obj_mag=40.0, adapter_mag=2.0, sensor_pixel_um=3.45)
        self.assertAlmostEqual(scale, 0.043125, places=6)

    # Tarefa 72: Teste de resize 3840 -> 1920 (escala dobra)
    def test_resize_3840_to_1920(self):
        rf_x = calculate_resize_factor(3840, 1920)
        rf_y = calculate_resize_factor(2160, 1080)
        self.assertEqual(rf_x, 2.0)
        self.assertEqual(rf_y, 2.0)
        base_scale = 0.08625
        effective_scale = base_scale * rf_x
        self.assertAlmostEqual(effective_scale, 0.1725, places=4)

    # Tarefa 73: Teste de resize 1920 -> 1920 (escala nao muda)
    def test_resize_1920_to_1920(self):
        rf = calculate_resize_factor(1920, 1920)
        self.assertEqual(rf, 1.0)
        base_scale = 0.08625
        effective_scale = base_scale * rf
        self.assertAlmostEqual(effective_scale, base_scale, places=5)

    # Tarefa 74: Teste de micrômetro (100 um / 1813 px)
    def test_stage_micrometer_calibration(self):
        scale = calibrate_from_line(known_um=100.0, dist_px=1813.0)
        self.assertAlmostEqual(scale, 0.0551572, places=5)
        self.assertEqual(f"{scale:.5f}", "0.05516")

    # Tarefa 75: Teste de area anisotropica (AreaPX = 1000, ScaleX = 0.05, ScaleY = 0.06 -> 3.0 um2)
    def test_anisotropic_area(self):
        area_px = 1000.0
        scale_x = 0.05
        scale_y = 0.06
        area_um2 = area_px * scale_x * scale_y
        self.assertAlmostEqual(area_um2, 3.0, places=4)

    # Tarefa 76: Teste de diametro equivalente fisico a partir de area_um2
    def test_equivalent_diameter_physical(self):
        area_um2 = 3.0
        deq_um = 2.0 * math.sqrt(area_um2 / math.pi)
        self.assertAlmostEqual(deq_um, 1.9544, places=3)

    # Tarefa 77: Teste de circularidade para circulo sintetico (~1.0)
    def test_circularity_synthetic_circle(self):
        circle_pts = generate_ellipse_polygon(cx=100, cy=100, a=40, b=40, angle_deg=0, n_points=180)
        area = polygon_area(circle_pts)
        perimeter = polygon_perimeter(circle_pts)
        raw_circularity = (4.0 * math.pi * area) / (perimeter ** 2)
        self.assertAlmostEqual(raw_circularity, 1.0, places=2)
        self.assertLessEqual(raw_circularity, 1.01)
        self.assertGreaterEqual(raw_circularity, 0.99)

    # Tarefa 78: Teste para elipse (circularidade menor que a do circulo)
    def test_circularity_ellipse_less_than_circle(self):
        circle_pts = generate_ellipse_polygon(100, 100, 40, 40, 0, 120)
        circ_circle = (4.0 * math.pi * polygon_area(circle_pts)) / (polygon_perimeter(circle_pts) ** 2)

        ellipse_pts = generate_ellipse_polygon(100, 100, 40, 20, 0, 120)
        circ_ellipse = (4.0 * math.pi * polygon_area(ellipse_pts)) / (polygon_perimeter(ellipse_pts) ** 2)

        self.assertLess(circ_ellipse, circ_circle)
        self.assertLess(circ_ellipse, 0.85)

    # Tarefa 79: Teste de rotacao: elipse a 0, 30, 45 e 90 graus mantem os mesmos eixos pelo PCA
    def test_pca_rotation_invariance(self):
        a_true = 50.0  # Diametro maior real = 2 * a = 100
        b_true = 25.0  # Diametro menor real = 2 * b = 50
        angles = [0, 30, 45, 90]
        results = []
        for ang in angles:
            pts = generate_ellipse_polygon(200, 200, a_true, b_true, ang, n_points=240)
            maj, mino, aspect = calculate_pca_axes(pts)
            results.append((maj, mino))
            self.assertAlmostEqual(maj, 2.0 * a_true, delta=1.0)
            self.assertAlmostEqual(mino, 2.0 * b_true, delta=1.0)

        # Variacao entre angulos deve ser menor que 1%
        first_maj, first_min = results[0]
        for maj, mino in results[1:]:
            self.assertAlmostEqual(maj, first_maj, delta=0.5)
            self.assertAlmostEqual(mino, first_min, delta=0.5)

    # Tarefa 80: Teste que prova o problema da bounding box vs PCA
    def test_bounding_box_failure_vs_pca(self):
        a = 50.0
        b = 20.0
        # Elipse a 0 graus: bounding box coincide com eixos
        pts_0 = generate_ellipse_polygon(200, 200, a, b, 0)
        bbox_w_0 = max(p[0] for p in pts_0) - min(p[0] for p in pts_0)
        bbox_h_0 = max(p[1] for p in pts_0) - min(p[1] for p in pts_0)
        maj_pca_0, min_pca_0, _ = calculate_pca_axes(pts_0)

        # Elipse a 45 graus: bounding box distorcida (~77 x ~77), mas PCA preserva 100 x 40
        pts_45 = generate_ellipse_polygon(200, 200, a, b, 45)
        bbox_w_45 = max(p[0] for p in pts_45) - min(p[0] for p in pts_45)
        bbox_h_45 = max(p[1] for p in pts_45) - min(p[1] for p in pts_45)
        maj_pca_45, min_pca_45, _ = calculate_pca_axes(pts_45)

        # A bounding box a 45 graus e muito diferente da a 0 graus (erro grosseiro)
        self.assertNotAlmostEqual(bbox_w_45, bbox_w_0, delta=10.0)

        # O PCA a 45 graus e identico ao a 0 graus (invariante a rotacao)
        self.assertAlmostEqual(maj_pca_45, maj_pca_0, delta=1.0)
        self.assertAlmostEqual(min_pca_45, min_pca_0, delta=1.0)

    # Tarefa 81: Objeto de borda excluido das estatisticas validas
    def test_border_object_exclusion(self):
        measurements = [
            {"id": 1, "touches_border": True, "valid": False, "diam": 7.5},
            {"id": 2, "touches_border": False, "valid": True, "diam": 7.6},
            {"id": 3, "touches_border": False, "valid": True, "diam": 7.4},
        ]
        valid_diams = [m["diam"] for m in measurements if m["valid"]]
        self.assertEqual(len(valid_diams), 2)
        mean_diam = sum(valid_diams) / len(valid_diams)
        self.assertAlmostEqual(mean_diam, 7.5, places=2)

    # Tarefa 82: BOUNDING_BOX_ESTIMATE contado, mas nao entra na morfometria
    def test_bounding_box_estimate_exclusion(self):
        measurements = [
            {"id": 1, "geom_source": "POLYGON", "valid": True, "diam": 7.5},
            {"id": 2, "geom_source": "BOUNDING_BOX_ESTIMATE", "valid": False, "diam": 12.0},
        ]
        cell_count = len(measurements)
        valid_cells = [m for m in measurements if m["valid"]]
        self.assertEqual(cell_count, 2)
        self.assertEqual(len(valid_cells), 1)
        self.assertEqual(valid_cells[0]["diam"], 7.5)


if __name__ == "__main__":
    unittest.main()
