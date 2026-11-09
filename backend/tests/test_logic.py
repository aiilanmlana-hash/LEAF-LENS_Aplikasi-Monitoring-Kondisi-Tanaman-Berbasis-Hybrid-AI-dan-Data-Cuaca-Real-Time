import asyncio
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import cv2
import numpy as np

from backend.main import (
    _analyze,
    _classify,
    _numeric_ann_model,
    _plant_village_details,
    _safe_plant_id,
    _segment,
    _validate_prediction,
    LOW_CONFIDENCE_MESSAGE,
    OOD_CLASS_NAME,
    OOD_CONFIDENCE_THRESHOLD,
    OOD_MESSAGE,
    UNSUPPORTED_PLANT_MESSAGE,
    app,
    fuzzy_health_score,
)
from backend.compact_context import build_compact_ai_context
from backend.care_recommendations import recommend_care
from backend.auth import verified_user
from backend.fuzzy_logic import sugeno_health_score
from fastapi import HTTPException
from backend.numeric_ann import NumericFeatureANN
from backend.prepare_dataset import prepare_dataset
from backend.segmentation import numeric_image_features
from backend.train_numeric_ann import FEATURE_COLUMNS, load_dataset
from backend.train_plant_model import (
    _confidence_distribution,
    _filter_target_classes,
    _metrics,
    _validation_duplicate_indexes,
)
from backend.weather import resolve_weather


class FuzzyHealthScoreTests(unittest.TestCase):
    def test_no_leaf_returns_unknown(self):
        self.assertEqual(fuzzy_health_score(1.0, 2.0), (0.0, "Tidak diketahui"))

    def test_green_dominant_leaf_is_healthier_than_yellow_dominant_leaf(self):
        healthy_score, healthy_status = fuzzy_health_score(55.0, 2.0)
        dry_score, dry_status = fuzzy_health_score(5.0, 45.0)
        self.assertGreater(healthy_score, dry_score)
        self.assertEqual(healthy_status, "Sehat")
        self.assertEqual(dry_status, "Kritis")

    def test_score_is_bounded(self):
        score, _ = fuzzy_health_score(99.0, 0.0)
        self.assertGreaterEqual(score, 0.0)
        self.assertLessEqual(score, 100.0)

    def test_completely_green_leaf_is_healthy(self):
        score, severity = fuzzy_health_score(100.0, 0.0)
        self.assertGreaterEqual(score, 75.0)
        self.assertEqual(severity, "Sehat")

    def test_sugeno_handles_bounded_extremes_and_rejects_non_finite_values(self):
        healthy_score, _ = fuzzy_health_score(100.0, 100.0)
        dry_score, _ = fuzzy_health_score(0.0, 100.0)
        self.assertEqual(healthy_score, 48.0)
        self.assertEqual(dry_score, 12.0)
        self.assertEqual(fuzzy_health_score(-20.0, 200.0), (12.0, "Kritis"))
        with self.assertRaises(ValueError):
            fuzzy_health_score(float("nan"), 10.0)

    def test_blighter_score_reflects_warm_humid_weather(self):
        baseline = sugeno_health_score(35, 18, disease_name="Late blight")
        risky_weather = sugeno_health_score(
            35,
            18,
            temperature_c=28,
            humidity_pct=90,
            precipitation_mm=12,
            disease_name="Late blight",
        )
        self.assertLess(risky_weather[0], baseline[0])


class WeatherLookupTests(unittest.TestCase):
    def test_coordinates_are_required_as_a_pair(self):
        with self.assertRaisesRegex(ValueError, "berpasangan"):
            resolve_weather(-7.4, None)

    def test_open_meteo_failure_falls_back_to_nearest_station_history(self):
        historical = {
            "temperature_c": 27.1,
            "humidity_pct": 82.0,
            "precipitation_mm": 4.0,
            "source": "Rata-rata historis BMKG 2010–2020",
            "station_name": "Stasiun cuaca",
            "observation_date": "bulan-11",
        }
        with patch(
            "backend.weather._fetch_open_meteo", side_effect=OSError("offline")
        ), patch(
            "backend.weather._historical_weather", return_value=historical
        ) as fallback:
            weather, error = resolve_weather(-7.4, 112.7)
        self.assertEqual(weather, historical)
        self.assertIsNone(error)
        fallback.assert_called_once()

    def test_historical_bmkg_fallback_uses_nearby_station_and_monthly_data(self):
        with patch(
            "backend.weather._fetch_open_meteo", side_effect=OSError("offline")
        ):
            weather, error = resolve_weather(-7.45, 112.72)
        self.assertIsNone(error)
        self.assertIsNotNone(weather)
        self.assertIn("BMKG", weather["source"])
        self.assertIsNotNone(weather["station_name"])
        self.assertTrue(0 <= weather["humidity_pct"] <= 100)


class PlantIdValidationTests(unittest.TestCase):
    def test_valid_id_is_trimmed(self):
        self.assertEqual(_safe_plant_id(" P001-Leaf_2 "), "P001-Leaf_2")

    def test_path_components_are_rejected(self):
        with self.assertRaises(HTTPException):
            _safe_plant_id("../mask")

    def test_prediction_validation_rejects_ood_classes_and_low_confidence(self):
        self.assertEqual(OOD_CONFIDENCE_THRESHOLD, 0.70)
        self.assertIsNone(_validate_prediction("Tomato___healthy", 70))
        self.assertIsNone(_validate_prediction("Potato___Early_blight", 99))
        for prediction, confidence, message in (
            ("Potato___Early_blight", 69.99, LOW_CONFIDENCE_MESSAGE),
            (OOD_CLASS_NAME, 99, OOD_MESSAGE),
            ("Apple___healthy", 99, UNSUPPORTED_PLANT_MESSAGE),
            ("unknown-object", 99, OOD_MESSAGE),
            ("Corn_(maize)___healthy", float("nan"), LOW_CONFIDENCE_MESSAGE),
        ):
            with self.subTest(prediction=prediction, confidence=confidence):
                with self.assertRaises(HTTPException) as raised:
                    _validate_prediction(prediction, confidence)
                self.assertEqual(raised.exception.status_code, 422)
                self.assertEqual(raised.exception.detail["code"], "ood_image")
                self.assertEqual(raised.exception.detail["message"], message)

    def test_classifier_returns_top_class_and_softmax_confidence(self):
        import torch

        model = Mock(return_value=torch.tensor([[0.0, 2.0]]))
        transform = Mock(return_value=torch.zeros((3, 224, 224)))
        with patch(
            "backend.main._model_resources",
            return_value=(
                model,
                ["Tomato___healthy", "Potato___Early_blight"],
                transform,
                torch,
            ),
        ):
            prediction, confidence = _classify(
                np.zeros((8, 8, 3), dtype=np.uint8)
            )

        self.assertEqual(prediction, "Potato___Early_blight")
        self.assertAlmostEqual(confidence, 88.0797, places=3)


class DatasetPreparationTests(unittest.TestCase):
    def _dataset_roots(self, root: Path) -> tuple[Path, Path]:
        source = root / "DataSet"
        dataset = root / "PlantVillage"
        for path in (
            source / "Background_or_Invalid" / "training_set" / "training_set" / "cats",
            source / "Background_or_Invalid" / "test_set" / "test_set" / "dogs",
            source / "PlantDoc Classification" / "train" / "Corn_rust_leaf",
            source / "PlantDoc Classification" / "test" / "Tomato_leaf",
            dataset / "train" / "Apple___healthy",
            dataset / "train" / "Corn_(maize)___Common_rust_",
            dataset / "val" / "Apple___healthy",
            dataset / "val" / "Tomato___Unspecified_leaf",
        ):
            path.mkdir(parents=True, exist_ok=True)
        (source / "Background_or_Invalid" / "training_set" / "training_set" / "cats" / "cat.jpg").write_bytes(b"cat")
        (source / "Background_or_Invalid" / "test_set" / "test_set" / "dogs" / "dog.jpg").write_bytes(b"dog")
        (source / "PlantDoc Classification" / "train" / "Corn_rust_leaf" / "rust.jpg").write_bytes(b"rust")
        (source / "PlantDoc Classification" / "test" / "Tomato_leaf" / "leaf.jpg").write_bytes(b"leaf")
        return source, dataset

    def test_dataset_preparation_dry_run_does_not_change_any_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, dataset = self._dataset_roots(root)
            result = prepare_dataset(source, dataset)
            self.assertEqual(result["images_to_move"], 4)
            self.assertEqual(result["class_folders_to_remove"], 2)
            self.assertTrue(
                (source / "Background_or_Invalid" / "training_set" / "training_set" / "cats" / "cat.jpg").is_file()
            )
            self.assertTrue((dataset / "train" / "Apple___healthy").is_dir())

    def test_dataset_preparation_moves_sources_and_removes_other_classes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, dataset = self._dataset_roots(root)
            prepare_dataset(source, dataset, apply=True)
            self.assertEqual(
                (dataset / "train" / "Background_or_Invalid" / "training_set" / "training_set" / "cats" / "cat.jpg").read_bytes(),
                b"cat",
            )
            self.assertTrue(
                (dataset / "train" / "Corn_(maize)___Common_rust_" / "PlantDoc" / "Corn_rust_leaf" / "rust.jpg").is_file()
            )
            self.assertTrue(
                (dataset / "val" / "Tomato___Unspecified_leaf" / "PlantDoc" / "Tomato_leaf" / "leaf.jpg").is_file()
            )
            self.assertFalse((dataset / "train" / "Apple___healthy").exists())
            self.assertFalse((dataset / "val" / "Apple___healthy").exists())
            self.assertFalse(
                (source / "Background_or_Invalid" / "training_set" / "training_set" / "cats" / "cat.jpg").exists()
            )


class ValidationConfidenceTests(unittest.TestCase):
    def test_confidence_distribution_reports_ood_threshold_buckets(self):
        result = _confidence_distribution([0.3, 0.6, 0.75, 0.85, 0.99])
        self.assertEqual(result["threshold_percent"], 90.0)
        self.assertEqual(result["below_threshold_count"], 4)
        self.assertEqual(result["buckets"]["90_to_below_95_percent"]["count"], 0)
        self.assertEqual(result["buckets"]["95_to_below_99_percent"]["count"], 0)
        self.assertEqual(result["buckets"]["99_percent_or_higher"]["count"], 1)


class ApiAuthenticationTests(unittest.TestCase):
    def test_missing_bearer_token_is_rejected_when_auth_is_enabled(self):
        with patch.dict(os.environ, {"PLANT_REQUIRE_AUTH": "true"}):
            with self.assertRaises(HTTPException) as raised:
                verified_user(None)
        self.assertEqual(raised.exception.status_code, 401)

    def test_verified_email_token_returns_its_uid(self):
        fake_auth = type(
            "FakeAuth",
            (),
            {
                "verify_id_token": staticmethod(
                    lambda token, check_revoked: {
                        "uid": "firebase-user",
                        "email_verified": True,
                    }
                )
            },
        )
        with patch.dict(os.environ, {"PLANT_REQUIRE_AUTH": "true"}), patch(
            "backend.auth._firebase_auth", return_value=fake_auth
        ):
            self.assertEqual(verified_user("Bearer valid-token"), "firebase-user")


class SegmentationTests(unittest.TestCase):
    def test_kmeans_refined_hsv_masks_count_green_and_yellow_pixels(self):
        image = np.zeros((120, 160, 3), dtype=np.uint8)
        image[:, :80] = (35, 180, 35)
        image[:, 80:] = (25, 200, 220)
        green_ratio, yellow_ratio, mask_png = _segment(image, 25, 95, 35, 30, 3)
        self.assertGreater(green_ratio, 0)
        self.assertGreater(yellow_ratio, 0)
        mask = cv2.imdecode(np.frombuffer(mask_png, dtype=np.uint8), cv2.IMREAD_GRAYSCALE)
        self.assertEqual(set(np.unique(mask)) - {0, 150, 255}, set())

    def test_kmeans_ratios_match_uniform_half_green_half_dry_image(self):
        image = np.empty((120, 160, 3), dtype=np.uint8)
        image[:, :80] = (35, 180, 35)
        image[:, 80:] = (25, 200, 220)
        green_ratio, dry_ratio, _ = _segment(image, 25, 95, 35, 30, 3)
        self.assertAlmostEqual(green_ratio, 50.0, delta=0.1)
        self.assertAlmostEqual(dry_ratio, 50.0, delta=0.1)

    def test_kmeans_result_is_deterministic_for_same_image(self):
        image = np.zeros((96, 128, 3), dtype=np.uint8)
        image[:, :64] = (35, 180, 35)
        image[:, 64:] = (25, 200, 220)
        first = _segment(image, 25, 95, 35, 30, 3)
        second = _segment(image, 25, 95, 35, 30, 3)
        self.assertEqual(first, second)

    def test_numeric_feature_extraction_returns_bounded_hsv_values(self):
        image = np.zeros((16, 20, 3), dtype=np.uint8)
        image[:] = (20, 120, 35)
        features = numeric_image_features(image)
        self.assertEqual(
            set(features),
            {"mean_hue", "mean_saturation", "mean_value"},
        )
        self.assertTrue(0 <= features["mean_hue"] <= 179)
        self.assertTrue(0 <= features["mean_saturation"] <= 255)
        self.assertTrue(0 <= features["mean_value"] <= 255)


class SugenoAndContextTests(unittest.TestCase):
    def test_compact_ai_context_uses_short_json_keys(self):
        context = build_compact_ai_context(
            {
                "green_ratio": 24.36,
                "yellow_ratio": 5.41,
                "prediction": "Tomato___healthy",
                "plant_name": "Tomato",
                "disease_name": "healthy",
                "confidence": 96.22,
                "health_score": 88.4,
                "severity": "Sehat",
                "numeric_features": {
                    "mean_hue": 60.0,
                    "mean_saturation": 180.0,
                    "mean_value": 160.0,
                },
            }
        )
        payload = json.loads(context)
        self.assertEqual(
            set(payload), {"g", "d", "p", "x", "c", "h", "s", "a", "v"}
        )
        self.assertLess(len(context), 180)

    def test_plant_village_class_is_split_into_plant_and_disease(self):
        self.assertEqual(
            _plant_village_details("Apple___Apple_scab"),
            ("Apple", "Apple scab", False),
        )
        self.assertEqual(
            _plant_village_details("Corn_(maize)___Common_rust_"),
            ("Corn (maize)", "Common rust", False),
        )
        self.assertEqual(
            _plant_village_details("Potato___Early_blight"),
            ("Potato", "Early blight", False),
        )
        self.assertEqual(
            _plant_village_details("Tomato___healthy"),
            ("Tomato", "healthy", True),
        )

    def test_analysis_response_contains_compact_context_and_optional_ann(self):
        image = np.zeros((48, 48, 3), dtype=np.uint8)
        image[:, :24] = (35, 180, 35)
        image[:, 24:] = (25, 200, 220)
        success, encoded = cv2.imencode(".png", image)
        self.assertTrue(success)

        with patch(
            "backend.main._classify", return_value=("Tomato___healthy", 98.1)
        ), patch("backend.main._save_record"), patch(
            "backend.main._numeric_ann_model",
            return_value=(None, "No trained checkpoint"),
        ):
            result = _analyze(
                encoded.tobytes(),
                "test-user",
                "P001",
                "test",
                False,
                25,
                95,
                35,
                30,
                3,
            )

        context = json.loads(result["ai_context_json"])
        self.assertEqual(context["p"], "Tomato")
        self.assertEqual(context["x"], "healthy")
        self.assertIsNone(result["ann_prediction"])
        self.assertIn("mean_hue", result["numeric_features"])
        self.assertEqual(result["plant_name"], "Tomato")
        self.assertEqual(result["prediction"], "Tomato - healthy")
        self.assertTrue(result["is_healthy"])
        self.assertIn(
            result["care_recommendation"]["priority"], {"Rutin", "Sedang", "Pantau"}
        )

    def test_ood_class_prediction_is_rejected_before_segmentation(self):
        image = np.zeros((16, 16, 3), dtype=np.uint8)
        success, encoded = cv2.imencode(".png", image)
        self.assertTrue(success)

        with patch(
            "backend.main._classify",
            return_value=("Background_or_Invalid", 0.01),
        ), patch("backend.main._segment", side_effect=AssertionError), patch(
            "builtins.print"
        ) as print_prediction:
            with self.assertRaises(HTTPException) as raised:
                _analyze(
                    encoded.tobytes(),
                    "test-user",
                    "P001",
                    "test",
                    False,
                    25,
                    95,
                    35,
                    30,
                    3,
                )

        print_prediction.assert_called_once_with(
            "Hasil Prediksi: Background_or_Invalid, Confidence: 0.01",
            flush=True,
        )
        self.assertEqual(raised.exception.status_code, 422)
        self.assertEqual(raised.exception.detail["code"], "ood_image")

    def test_low_confidence_prediction_is_rejected_before_segmentation(self):
        image = np.zeros((16, 16, 3), dtype=np.uint8)
        success, encoded = cv2.imencode(".png", image)
        self.assertTrue(success)
        with patch(
            "backend.main._classify",
            return_value=("Tomato___Early_blight", 0.01),
        ), patch("backend.main._segment", side_effect=AssertionError), patch(
            "builtins.print"
        ) as print_prediction:
            with self.assertRaises(HTTPException) as raised:
                _analyze(
                    encoded.tobytes(),
                    "test-user",
                    "P001",
                    "test",
                    False,
                    25,
                    95,
                    35,
                    30,
                    3,
                )
        print_prediction.assert_called_once_with(
            "Hasil Prediksi: Tomato___Early_blight, Confidence: 0.01",
            flush=True,
        )
        self.assertEqual(raised.exception.status_code, 422)
        self.assertEqual(raised.exception.detail["code"], "ood_image")

    def test_virus_advice_does_not_claim_fertilizer_can_cure_the_plant(self):
        advice = recommend_care(
            plant_name="Tomato",
            disease_name="Tomato Yellow Leaf Curl Virus",
            is_healthy=False,
            confidence=95,
            health_score=35,
            dry_ratio=5,
        )
        self.assertEqual(advice["priority"], "Tinggi")
        self.assertIn("tidak menyembuhkan virus", advice["summary"])


class NumericAnnTests(unittest.TestCase):
    def test_api_uses_backend_checkpoint_path_without_environment_override(self):
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / "missing-ann.json"
            with (
                patch("backend.main.NUMERIC_ANN_PATH", checkpoint),
                patch("backend.main._numeric_ann", None),
                patch.dict(os.environ, {}, clear=True),
            ):
                model, error = _numeric_ann_model()
        self.assertIsNone(model)
        self.assertEqual(error, "Analisis kesehatan lanjutan belum tersedia.")

    def test_api_automatically_loads_default_numeric_checkpoint(self):
        features = np.zeros((3, len(FEATURE_COLUMNS)), dtype=np.float64)
        labels = np.asarray([0, 1, 2])
        model = NumericFeatureANN(input_size=len(FEATURE_COLUMNS)).fit(
            features, labels, epochs=2
        )
        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / "numeric-ann.json"
            model.save(checkpoint)
            with (
                patch("backend.main.NUMERIC_ANN_PATH", checkpoint),
                patch("backend.main._numeric_ann", None),
                patch.dict(os.environ, {}, clear=True),
            ):
                loaded, error = _numeric_ann_model()
        self.assertIsNone(error)
        self.assertIsNotNone(loaded)
        assert loaded is not None
        self.assertEqual(loaded.input_size, len(FEATURE_COLUMNS))

    def test_ann_trains_predicts_and_round_trips_checkpoint(self):
        features = np.asarray(
            [
                [80, 2, 95, 92, 60, 180, 160],
                [75, 4, 90, 85, 55, 170, 150],
                [4, 62, 70, 20, 24, 200, 190],
                [7, 55, 74, 25, 22, 185, 175],
            ],
            dtype=np.float64,
        )
        labels = np.asarray([0, 0, 1, 1])
        model = NumericFeatureANN(hidden_size=12).fit(
            features, labels, epochs=300
        )
        prediction = model.predict(features[0])
        self.assertIn(prediction[0]["label"], model.labels)
        self.assertGreaterEqual(prediction[0]["confidence"], 0)
        self.assertLessEqual(prediction[0]["confidence"], 100)

        with tempfile.TemporaryDirectory() as directory:
            checkpoint = Path(directory) / "ann.json"
            model.save(checkpoint)
            loaded = NumericFeatureANN.load(checkpoint)
            self.assertEqual(loaded.predict(features[0]), prediction)

    def test_ann_uses_training_only_normalization_and_validation_early_stopping(self):
        train_features = np.asarray(
            [
                [80, 2, 95, 92, 60, 180, 160],
                [75, 4, 90, 85, 55, 170, 150],
                [4, 62, 70, 20, 24, 200, 190],
                [7, 55, 74, 25, 22, 185, 175],
            ],
            dtype=np.float64,
        )
        train_labels = np.asarray([0, 0, 1, 1])
        validation_features = np.asarray(
            [[68, 8, 88, 78, 50, 165, 145], [10, 48, 73, 29, 28, 180, 170]],
            dtype=np.float64,
        )
        validation_labels = np.asarray([0, 1])
        model = NumericFeatureANN(seed=11).fit(
            train_features,
            train_labels,
            epochs=100,
            batch_size=2,
            validation_data=(validation_features, validation_labels),
            patience=10,
        )
        self.assertEqual(model._feature_mean.shape, (1, 7))
        self.assertEqual(
            [row["label"] for row in model.predict(validation_features)],
            ["healthy", "dry"],
        )

    def test_untrained_ann_refuses_to_make_predictions(self):
        with self.assertRaisesRegex(RuntimeError, "no trained weights"):
            NumericFeatureANN().predict(np.zeros(7))


class PlantModelMetricTests(unittest.TestCase):
    def test_aggregate_metrics_are_computed_from_confusion_matrix(self):
        result = _metrics(np.asarray([[1, 1], [0, 2]], dtype=np.int64))
        self.assertEqual(result["accuracy"], 0.75)
        self.assertAlmostEqual(result["precision_macro"], 5 / 6)
        self.assertAlmostEqual(result["recall_macro"], 0.75)
        self.assertEqual([row["support"] for row in result["per_class"]], [2, 2])

    def test_training_dataset_filter_keeps_only_crops_and_ood_class(self):
        class FakeImageFolder:
            def __init__(self):
                self.classes = [
                    "Apple___healthy",
                    "Background_or_Invalid",
                    "Corn_(maize)___healthy",
                    "Potato___healthy",
                    "Tomato___healthy",
                ]
                self.class_to_idx = {
                    name: index for index, name in enumerate(self.classes)
                }
                self.samples = [
                    (f"{name}/image.png", index)
                    for index, name in enumerate(self.classes)
                ]
                self.imgs = self.samples
                self.targets = list(range(len(self.classes)))

        dataset = FakeImageFolder()
        _filter_target_classes(dataset)
        self.assertEqual(
            dataset.classes,
            [
                "Background_or_Invalid",
                "Corn_(maize)___healthy",
                "Potato___healthy",
                "Tomato___healthy",
            ],
        )
        self.assertEqual(dataset.targets, [0, 1, 2, 3])

    def test_numeric_ann_training_csv_includes_weather_features(self):
        with tempfile.TemporaryDirectory() as directory:
            dataset = Path(directory) / "numeric.csv"
            columns = (*FEATURE_COLUMNS, "label")
            row = ["30", "5", "90", "80", "50", "160", "150", "28", "85", "6", "healthy"]
            dataset.write_text(
                ",".join(columns) + "\n" + ",".join(row) + "\n",
                encoding="utf-8",
            )
            features, labels = load_dataset(dataset)
        self.assertEqual(len(FEATURE_COLUMNS), 10)
        self.assertEqual(features.shape, (1, 10))
        self.assertEqual(labels.tolist(), [0])


class SplitIntegrityTests(unittest.TestCase):
    def test_exact_training_duplicates_are_excluded_from_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            train = root / "train.jpg"
            copied_validation = root / "validation-copy.jpg"
            unique_validation = root / "validation-unique.jpg"
            train.write_bytes(b"same leaf bytes")
            copied_validation.write_bytes(b"same leaf bytes")
            unique_validation.write_bytes(b"different leaf bytes")

            indexes = _validation_duplicate_indexes(
                [str(train)], [str(copied_validation), str(unique_validation)]
            )

        self.assertEqual(indexes, [0])


class BrowserCorsTests(unittest.TestCase):
    def test_local_web_origin_can_call_analysis_api(self):
        messages = []

        async def receive():
            return {"type": "http.request", "body": b"", "more_body": False}

        async def send(message):
            messages.append(message)

        scope = {
            "type": "http",
            "asgi": {"version": "3.0", "spec_version": "2.3"},
            "http_version": "1.1",
            "method": "OPTIONS",
            "scheme": "http",
            "path": "/api/v1/analyze-plant",
            "raw_path": b"/api/v1/analyze-plant",
            "query_string": b"",
            "headers": [
                (b"origin", b"http://localhost:54321"),
                (b"access-control-request-method", b"POST"),
            ],
            "client": ("test", 1234),
            "server": ("test", 80),
        }
        asyncio.run(app(scope, receive, send))
        response_headers = dict(
            (key.decode().lower(), value.decode())
            for key, value in messages[0]["headers"]
        )
        self.assertEqual(
            messages[0]["status"],
            200,
        )
        self.assertEqual(
            response_headers.get("access-control-allow-origin"),
            "http://localhost:54321",
        )


if __name__ == "__main__":
    unittest.main()
