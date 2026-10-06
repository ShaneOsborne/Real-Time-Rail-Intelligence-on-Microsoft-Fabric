"""Exponential backoff helper (1, 2, 4, 8, 16 ... seconds, capped)."""

from __future__ import annotations

import random
from dataclasses import dataclass, field


@dataclass
class ExponentialBackoff:
    initial: float = 1.0
    maximum: float = 60.0
    factor: float = 2.0
    jitter: float = 0.0  # fraction of the delay, e.g. 0.1 = +/-10 %
    _attempt: int = field(default=0, init=False)

    def __post_init__(self) -> None:
        if self.initial <= 0:
            raise ValueError("initial must be > 0")
        if self.maximum < self.initial:
            raise ValueError("maximum must be >= initial")
        if self.factor < 1:
            raise ValueError("factor must be >= 1")
        if not 0 <= self.jitter < 1:
            raise ValueError("jitter must be in [0, 1)")

    @property
    def attempt(self) -> int:
        return self._attempt

    def peek(self) -> float:
        """Base delay for the current attempt, without jitter and without advancing."""
        return min(self.initial * (self.factor ** self._attempt), self.maximum)

    def next_delay(self) -> float:
        delay = self.peek()
        self._attempt += 1
        if self.jitter:
            delay = delay * (1 + random.uniform(-self.jitter, self.jitter))
            delay = max(0.0, min(delay, self.maximum))
        return delay

    def reset(self) -> None:
        self._attempt = 0
