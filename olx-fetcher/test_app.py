import unittest

from app import classify_offer_response, _valid_offer_url, PORTALS


class AvailabilityClassifierTests(unittest.TestCase):
    def test_not_found_is_inactive(self):
        self.assertEqual(
            classify_offer_response(404, "", "65813684", "https://www.olx.uz/"),
            ("inactive", "http_404"),
        )

    def test_waf_response_is_unknown(self):
        self.assertEqual(
            classify_offer_response(403, "", "65813684", "https://www.olx.uz/"),
            ("unknown", "http_403"),
        )

    def test_visible_inactive_message_wins(self):
        status, reason = classify_offer_response(
            200,
            "<main>Это объявление больше не доступно</main>",
            "65813684",
            "https://www.olx.uz/d/obyavlenie/test-65813684.html",
        )
        self.assertEqual((status, reason), ("inactive", "inactive_page"))

    def test_script_translation_does_not_create_false_inactive(self):
        status, reason = classify_offer_response(
            200,
            "<script>window.copy='Объявление не активно'</script><main>Квартира в аренду</main>",
            "65813684",
            "https://www.olx.uz/d/obyavlenie/test-65813684.html",
        )
        self.assertEqual((status, reason), ("active", "offer_page"))

    def test_generic_error_shell_is_not_active_even_when_url_keeps_offer_id(self):
        status, reason = classify_offer_response(
            200,
            "<main><h1>Ой, что-то пошло не так</h1><p>Попробуйте позже</p></main>",
            "ID4kiib",
            "https://www.olx.uz/d/obyavlenie/assalom-sohil-3-4-10-ID4kiib.html",
        )
        self.assertEqual((status, reason), ("unknown", "generic_error_page"))

    def test_generic_redirect_is_unknown(self):
        self.assertEqual(
            classify_offer_response(200, "<main>OLX</main>", "65813684", "https://www.olx.uz/"),
            ("unknown", "unrecognized_page"),
        )

    def test_offer_url_is_restricted_to_country_portal(self):
        self.assertTrue(
            _valid_offer_url(PORTALS["UZ"], "https://www.olx.uz/d/obyavlenie/test-65813684.html")
        )
        self.assertFalse(
            _valid_offer_url(PORTALS["UZ"], "https://example.com/d/obyavlenie/test-65813684.html")
        )
        self.assertFalse(
            _valid_offer_url(PORTALS["UZ"], "http://www.olx.uz/d/obyavlenie/test-65813684.html")
        )


if __name__ == "__main__":
    unittest.main()
