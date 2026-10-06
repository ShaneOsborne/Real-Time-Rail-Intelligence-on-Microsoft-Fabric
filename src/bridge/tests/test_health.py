import time

from rail_bridge.health import BridgeState


def test_ready_requires_connection_and_fresh_messages():
    s = BridgeState(stale_after_s=60)
    assert s.ready() is False
    s.update(connected=True)
    assert s.ready() is True  # grace period
    s.update(last_message_at=time.time() - 120)
    assert s.ready() is False
    s.update(last_message_at=time.time())
    assert s.ready() is True
    snap = s.snapshot()
    assert snap["connected"] is True and "events_sent" in snap
