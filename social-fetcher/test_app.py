import unittest

from app import (
    _facebook_target,
    _parse_linkedin_jobs_html,
    _threads_username,
    _validate_public_url,
)


class SocialFetcherTests(unittest.TestCase):
    def test_facebook_group_url(self):
        self.assertEqual(
            _facebook_target('https://www.facebook.com/groups/123456789/'),
            {'kind': 'group', 'value': '123456789'},
        )

    def test_facebook_page_slug(self):
        self.assertEqual(
            _facebook_target('some.public.page'),
            {'kind': 'page', 'value': 'some.public.page'},
        )

    def test_threads_username_validation(self):
        self.assertEqual(_threads_username('@white.love'), 'white.love')
        with self.assertRaises(ValueError):
            _threads_username('../bad')

    def test_public_url_blocks_other_hosts(self):
        with self.assertRaises(ValueError):
            _validate_public_url('http://127.0.0.1:8080/private', {'linkedin.com'})
        self.assertEqual(
            _validate_public_url(
                'https://www.linkedin.com/jobs/view/123',
                {'linkedin.com'},
            ),
            'https://www.linkedin.com/jobs/view/123',
        )

    def test_linkedin_guest_card_parser(self):
        html = '''
        <ul>
          <li>
            <div data-entity-urn="urn:li:jobPosting:424242">
              <a class="base-card__full-link" href="https://www.linkedin.com/jobs/view/frontend-developer-424242"></a>
              <h3 class="base-search-card__title">Frontend Developer</h3>
              <h4 class="base-search-card__subtitle">Example LLC</h4>
              <span class="job-search-card__location">Tashkent, Uzbekistan</span>
              <time datetime="2026-08-22"></time>
            </div>
          </li>
        </ul>
        '''
        jobs = _parse_linkedin_jobs_html(html)
        self.assertEqual(len(jobs), 1)
        self.assertEqual(jobs[0]['id'], '424242')
        self.assertEqual(jobs[0]['title'], 'Frontend Developer')
        self.assertEqual(jobs[0]['company'], 'Example LLC')
        self.assertEqual(jobs[0]['location'], 'Tashkent, Uzbekistan')


if __name__ == '__main__':
    unittest.main()
