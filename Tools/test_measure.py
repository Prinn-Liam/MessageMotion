import unittest
from measure_motion import bands, match_rows, sample_metrics


class MeasurementTests(unittest.TestCase):
    def test_join_small_holes_but_keep_separate_bubbles(self):
        mask = [0] * 3 + [1] * 10 + [0] * 2 + [1] * 10 + [0] * 8 + [1] * 12 + [0] * 2
        self.assertEqual(bands(mask, 0, len(mask), minimum_height=8, join_gap=3), [(3, 25), (33, 45)])

    def test_track_translation_using_unequal_bubble_heights(self):
        previous = [(100, 220), (244, 400), (424, 560)]
        current = [(70, 190), (214, 370), (394, 530)]
        ids, shift = match_rows(previous, [4, 5, 6], current, 0, 1000)
        self.assertEqual(ids, [4, 5, 6])
        self.assertEqual(shift, -30)

    def test_metrics_label_points_and_estimated_speed(self):
        result = sample_metrics([(100, 220), (250, 400)], [4, 5], shift=-30,
                                frame=60, fps=60, scale=3, normal_gap=8, top=0, bottom=1000)
        self.assertEqual(result["time_seconds"], 1)
        self.assertEqual(result["estimated_scroll_points_per_second"], -600)
        self.assertEqual(result["gaps"][0]["deviation_points"], 2)

    def test_partial_edge_rows_are_not_reported_as_full_gap_measurements(self):
        result = sample_metrics([(0, 120), (144, 300)], [0, 1], shift=0,
                                frame=0, fps=60, scale=3, normal_gap=8, top=0, bottom=1000)
        self.assertEqual(result["gaps"], [])


if __name__ == "__main__":
    unittest.main()
