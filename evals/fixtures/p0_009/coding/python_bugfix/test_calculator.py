import unittest

from calculator import divide


class CalculatorTest(unittest.TestCase):
    def test_positive(self):
        self.assertEqual(divide(8, 2), 4)

    def test_negative(self):
        self.assertEqual(divide(-9, 3), -3)

    def test_zero_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "division_by_zero"):
            divide(1, 0)


if __name__ == "__main__":
    unittest.main()
