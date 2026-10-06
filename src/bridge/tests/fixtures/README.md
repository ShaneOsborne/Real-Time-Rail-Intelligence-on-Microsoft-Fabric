# Test fixtures

These messages are **synthetic**. They follow the structure documented on the Open Rail Data wiki
(Train Movements, TD and RTPPM pages) but they aren't captured from the live feeds. Train IDs, times and codes are illustrative.

| File | Content |
|---|---|
| `trust_batch.json` | One TRUST STOMP frame: a JSON array with 0001 activation, two 0003 movements (one LATE by 17 min, one ON TIME) and 0002 cancellation |
| `td_batch.json` | TD C-class messages (CA, CC) |
| `rtppm.json` | Minimal RTPPM national page message (field names to verify against the RTPPM wiki page) |
| `replay_frames.json` | The three frames above in replay format `[{"topic": ..., "body": ...}]`, used by `--source replay` |

To capture real samples for your own tests, run `python -m rail_bridge --sink file` and copy a few lines from
`out/messages.jsonl`. Remove anything you aren't allowed to redistribute.
