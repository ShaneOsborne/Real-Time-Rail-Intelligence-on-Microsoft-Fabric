// Lab 11 – one shared poller for the train snapshot, so the KPI strip and the map make ONE query per refresh
// (each query runs DirectQuery DAX → KQL on your Fabric capacity). Components subscribe with useSnapshot().
import { useEffect, useState } from 'react';
import { loadSnapshot, type TrainPosition } from './loadSnapshot';

export type SnapshotState = {
  trains: TrainPosition[];
  updatedAt: Date | null;
  loading: boolean;
  error: string | null;
};

const REFRESH_MS = 30_000; // change to 60_000 on a small capacity with many viewers
const LOOKBACK_MINUTES = 60;

let state: SnapshotState = { trains: [], updatedAt: null, loading: true, error: null };
const listeners = new Set<(s: SnapshotState) => void>();
let timer: ReturnType<typeof setInterval> | undefined;
let inFlight = false;

function publish(next: Partial<SnapshotState>) {
  state = { ...state, ...next };
  listeners.forEach((l) => l(state));
}

async function refresh() {
  if (inFlight) return;
  inFlight = true;
  try {
    const trains = await loadSnapshot(LOOKBACK_MINUTES);
    publish({ trains, updatedAt: new Date(), loading: false, error: null });
  } catch (e) {
    publish({ loading: false, error: e instanceof Error ? e.message : String(e) });
  } finally {
    inFlight = false;
  }
}

export function useSnapshot(): SnapshotState {
  const [s, setS] = useState(state);
  useEffect(() => {
    listeners.add(setS);
    if (!timer) {
      void refresh();
      timer = setInterval(() => void refresh(), REFRESH_MS);
    }
    return () => {
      listeners.delete(setS);
      if (listeners.size === 0 && timer) {
        clearInterval(timer);
        timer = undefined;
      }
    };
  }, []);
  return s;
}

export const SNAPSHOT_REFRESH_SECONDS = REFRESH_MS / 1000;
