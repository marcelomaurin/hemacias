"""
Testes sinteticos de morfometria e calibração óptica para validação matemática.
"""
import math
import unittest


class TestMorphometryMath(unittest.TestCase):
    def test_scale_conversion_diameter(self):
        px = 50.0
        scale = 0.15  # um/px
        um = px * scale
        self.assertAlmostEqual(um, 7.50, places=2)

    def test_scale_conversion_area(self):
        area_px = 2000.0
        scale = 0.15  # um/px
        area_um2 = area_px * (scale ** 2)
        self.assertAlmostEqual(area_um2, 45.0, places=2)

    def test_equivalent_diameter_circle(self):
        # Circulo de raio 40 px -> diametro 80 px
        r_px = 40.0
        d_real_px = 80.0
        area_px = math.pi * (r_px ** 2)
        d_eq_px = 2.0 * math.sqrt(area_px / math.pi)
        self.assertAlmostEqual(d_eq_px, d_real_px, places=3)

        scale = 0.10  # um/px
        d_um = d_eq_px * scale
        self.assertAlmostEqual(d_um, 8.00, places=2)

    def test_circularity_perfect_circle(self):
        r_px = 40.0
        area_px = math.pi * (r_px ** 2)
        perimeter_px = 2.0 * math.pi * r_px
        circularity = (4.0 * math.pi * area_px) / (perimeter_px ** 2)
        self.assertAlmostEqual(circularity, 1.00, places=3)

    def test_scale_bar_calculation(self):
        bar_um = 10.0
        pixel_size_um = 0.10
        bar_pixels = bar_um / pixel_size_um
        self.assertEqual(int(bar_pixels), 100)

    def test_lab_indices(self):
        # Exemplo clinico normal: RBC = 4.80 M/uL, Hb = 14.5 g/dL, Hct = 43.0%
        rbc = 4.80
        hb = 14.5
        hct = 43.0

        # MCV = Hct * 10 / RBC
        mcv = (hct * 10.0) / rbc
        self.assertAlmostEqual(mcv, 89.58, places=1)

        # MCH = Hb * 10 / RBC
        mch = (hb * 10.0) / rbc
        self.assertAlmostEqual(mch, 30.21, places=1)

        # MCHC = Hb * 100 / Hct
        mchc = (hb * 100.0) / hct
        self.assertAlmostEqual(mchc, 33.72, places=1)


if __name__ == "__main__":
    unittest.main()
