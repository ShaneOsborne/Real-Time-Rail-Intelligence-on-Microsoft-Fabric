import pytest

from rail_bridge.backoff import ExponentialBackoff


def test_sequence_doubles_and_caps():
    b = ExponentialBackoff(initial=1, maximum=16)
    assert [b.next_delay() for _ in range(7)] == [1, 2, 4, 8, 16, 16, 16]


def test_reset_restarts_sequence():
    b = ExponentialBackoff(initial=1, maximum=60)
    b.next_delay()
    b.next_delay()
    assert b.attempt == 2
    b.reset()
    assert b.attempt == 0
    assert b.next_delay() == 1


def test_jitter_stays_within_bounds():
    b = ExponentialBackoff(initial=4, maximum=4, jitter=0.25)
    for _ in range(100):
        assert 3.0 <= b.next_delay() <= 4.0


@pytest.mark.parametrize("kwargs", [{"initial": 0}, {"initial": 5, "maximum": 1}, {"factor": 0.5}, {"jitter": 1.5}])
def test_invalid_arguments(kwargs):
    with pytest.raises(ValueError):
        ExponentialBackoff(**kwargs)
