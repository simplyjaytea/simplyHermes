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

## Varies per run

Values change between runs of the same testbed. Structure does not: between runs 39098439801 and 39099239491, 127 of 128 files have the same paths, keys and JSON types. The exception is GET_api_hermes_update_check.json.

- ids: kanban task ids, session ids, message uids, the credential entry id, install_id
- timestamps: created_at, started_at, last_active, lastActive, last_activity_at, timestamp, now, checked_at, generated_at, expires_at, finished_at, snapshot_generated_at, last_used_at, created_age_seconds
- host stats: GET_api_system_stats (cpu, load, memory, disk, process, uptime, hostname) and GET_api_status (disk free)
- logs: GET_api_logs (line count and text; event order changes)
- GET_api_tools_toolsets_web_config: active_extract_backend and active_search_backend are "parallel" or "keenable"
- GET_api_hermes_update_check: depends on whether the update source is reachable

The committed GET_api_hermes_update_check.json is the success shape from run 39098439801 (update_available true, behind -1, commits []). Run 39099239491 returned this error shape, with status 200:

```json
{
  "behind": null,
  "can_apply": true,
  "current_version": "git.d97007c",
  "install_method": "git",
  "message": "Couldn't reach the update source — try again later.",
  "update_available": false,
  "update_command": "hermes update"
}
```

Compared with the success shape, the error shape has no commits key, behind is null, message is a string, and update_available is false.
