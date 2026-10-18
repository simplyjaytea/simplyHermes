# REST answers from the pinned testbed (Fixtures/rest)

Recorded by testbed/tools/record_rest.py from upstream d97007c32d6340f7ba79ac1dfb5773cc00846448 (testbed/hermes/Dockerfile). Source: rest-fixtures artifact of CI run 39098439801 (commit cf354222, testbed job 117589595645). One file per request plus index.json. These are the only answer shapes, since the OpenAPI spec has no response schemas.

Refresh: CI regenerates them on every testbed run. Let a testbed job pass on a PR, download its rest-fixtures, copy the files here (keep this README), and run the Swift checks.

Files without a GET_/POST_ prefix (21) predate the recorder and are hand-copied; tests read them by name (restFixture).

Redaction: only non-empty strings under secret names are replaced with "<redacted>". Secret names, case-insensitive: api key, secret, token, password, passwd, credential, cookie, authorization, private key. Numbers, booleans and null keep their type. An env-style "value" is hidden only when its entry's "key" or "name" is a secret name.

index.json has 173 entries: 127 with a file, and 46 skipped with a reason and no file.

Error answers (10) are real server answers and our only error-envelope evidence:
- POST_api_webhooks.json, 400: webhook create. Known gap: the webhook platform is not enabled on the testbed, so there are no webhook success shapes.
- DELETE_api_webhooks_recorder-hook.json, 404: webhook cleanup of that failed create.
- DELETE_api_credentials_pool_recorder_0.json, 404: credential pool cleanup. Known gap: the seeded credential entry stays in the testbed for that run. This was the run's last request, so no recorded file was captured after it and none shows the leftover entry.
- GET_api_learning_node.json (422) and GET_api_skills_content.json (422): the recorder did not send the required query params (id, name). Requests not changed in this commit.
- GET_api_skills_hub_preview.json (400) and GET_api_skills_hub_scan.json (400): the recorder did not send the required identifier. Requests not changed in this commit.
- GET_api_hermes_update_receipt.json, GET_api_memory_providers_byterover_oauth_status.json, GET_api_ssh_ownership.json (404): testbed state, no seed involved.
