# REST answers from the pinned testbed (Fixtures/rest)
Recorded by testbed/tools/record_rest.py from upstream d97007c32d6340f7ba79ac1dfb5773cc00846448 (testbed/hermes/Dockerfile): one file per request plus index.json, the only source of answer shapes (the OpenAPI spec has no response schemas).
CI regenerates them on every run as the rest-fixtures artifact of the testbed job.
Refresh: let that job pass on a PR, download rest-fixtures, copy its files here (keep this README), and run the Swift checks.
Files without a GET_/POST_ prefix predate the recorder; tests read them by name (restFixture).
