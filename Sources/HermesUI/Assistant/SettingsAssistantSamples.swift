#if canImport(UIKit)
    import HermesKit

    /// Answers for the previews. Each is one recorded run from Fixtures/rest, or a trimmed copy that drops whole keys
    /// or list items. Values vary between runs, so the screens decode types, not these values.
    enum SettingsAssistantSamples {
        /// From `GET_api_memory.json`, without each provider's `description` and `setup`.
        static let memory: JSONValue = [
            "active": "",
            "builtin_files": ["memory": 0, "user": 0],
            "providers": [
                ["available": false, "configured": true, "name": "byterover", "status": "unavailable"],
                ["available": false, "configured": false, "name": "retaindb", "status": "needs_config"],
            ],
        ]

        /// From `GET_api_audio_voice-config.json`.
        static let voiceConfig: JSONValue = [
            "ok": true,
            "stt": ["mode": "relay", "reason": "command/plugin provider", "streaming": false],
            "tts": ["mode": "relay", "reason": "provider 'edge' has no client wire"],
        ]

        /// From `GET_api_audio_elevenlabs_voices.json`. The recorded run listed no voice.
        static let voices: JSONValue = ["available": false, "voices": []]

        /// From `GET_api_curator.json`.
        static let curator: JSONValue = [
            "archive_after_days": 30,
            "enabled": true,
            "interval_hours": 168,
            "last_run_at": nil,
            "min_idle_hours": 2.0,
            "paused": false,
            "stale_after_days": 14,
        ]

        /// From `GET_api_chat_workspaces.json`.
        static let workspaces: JSONValue = [
            "default_cwd": "/opt/hermes",
            "home": "/root",
            "projects": [],
            "repos": [
                ["label": "hermes", "last_active": 1792299062.1441207, "root": "/opt/hermes", "sessions": 1]
            ],
            "scan_enabled": true,
        ]

        /// From `GET_api_dashboard_themes.json`, with two of its eight themes.
        static let themes: JSONValue = [
            "active": "default",
            "themes": [
                [
                    "description": "Classic dark teal — the canonical Hermes look",
                    "label": "Hermes Teal", "name": "default",
                ],
                [
                    "description": "Light mode — vivid Nous-blue accents on cream canvas",
                    "label": "Nous Blue", "name": "nous-blue",
                ],
            ],
        ]

        /// From `GET_api_dashboard_font.json`.
        static let font: JSONValue = ["font": "theme"]

        /// From `GET_api_egress_status.json`, with the first lines of its text.
        static let egress: JSONValue = [
            "text": "Egress proxy status\n\nEnabled: no\nBinary: (missing)\nBinary version: (unknown)"
        ]

        /// From `GET_api_shared-metrics_consent.json`.
        static let consent: JSONValue = [
            "decided": false, "enabled": false, "managed": false, "reask": false, "send": false,
        ]
    }
#endif
