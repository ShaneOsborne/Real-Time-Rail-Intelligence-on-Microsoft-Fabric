// Lab 11 – "Ask the network": chat with the Foundry agent from Lab 10 through the askRailAgent Rayfin function.
import { Fragment, useEffect, useRef, useState, type ReactNode } from 'react';
import { railFunctions } from '../../services/railClient';

type Turn = { role: 'user' | 'agent'; text: string; error?: boolean };

const SUGGESTIONS = [
  'Which trains are more than 15 minutes late right now?',
  'Which operators had the worst average delay in the last 3 hours?',
  'How many cancellations in the last hour, by reason?',
  'Show the latest departures and arrivals at Leeds.',
];

// Minimal, safe rendering of the agent's answer: **bold** and Markdown tables. No HTML is injected.
function renderInline(text: string): ReactNode[] {
  return text.split(/(\*\*[^*]+\*\*)/g).map((part, i) =>
    part.startsWith('**') && part.endsWith('**') ? <strong key={i}>{part.slice(2, -2)}</strong> : <Fragment key={i}>{part}</Fragment>,
  );
}

function renderAnswer(text: string): ReactNode[] {
  const lines = text.split('\n');
  const out: ReactNode[] = [];
  let i = 0;
  while (i < lines.length) {
    if (lines[i].trim().startsWith('|')) {
      const block: string[] = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) block.push(lines[i++].trim());
      const rows = block
        .filter((l) => !/^\|\s*:?-{2,}/.test(l))
        .map((l) => l.replace(/^\||\|$/g, '').split('|').map((c) => c.trim()));
      const [head, ...body] = rows;
      out.push(
        <table key={`t${i}`}>
          <thead><tr>{head.map((c, j) => <th key={j}>{renderInline(c)}</th>)}</tr></thead>
          <tbody>{body.map((r, k) => <tr key={k}>{r.map((c, j) => <td key={j}>{renderInline(c)}</td>)}</tr>)}</tbody>
        </table>,
      );
    } else {
      out.push(<Fragment key={`l${i}`}>{renderInline(lines[i])}{i < lines.length - 1 ? '\n' : ''}</Fragment>);
      i++;
    }
  }
  return out;
}

export function ChatPanel() {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [question, setQuestion] = useState('');
  const [busy, setBusy] = useState(false);
  const logRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    logRef.current?.scrollTo({ top: logRef.current.scrollHeight, behavior: 'smooth' });
  }, [turns, busy]);

  async function send(text?: string) {
    const q = (text ?? question).trim();
    if (!q || busy) return;
    setTurns((t) => [...t, { role: 'user', text: q }]);
    setQuestion('');
    setBusy(true);
    try {
      const functions = await railFunctions();
      const answer = await functions.askRailAgent.invoke({ question: q }, { timeoutMs: 120_000 });
      setTurns((t) => [...t, { role: 'agent', text: answer, error: answer.startsWith('Agent error') }]);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      setTurns((t) => [...t, { role: 'agent', text: `Sorry – ${msg}`, error: true }]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="rp-card rp-chat">
      <div className="rp-card-head">
        <h2>Ask the network</h2>
        <span className="rp-sub">Foundry agent · Fabric data agent</span>
      </div>
      <div className="rp-chat-log" ref={logRef} aria-live="polite">
        {turns.length === 0 && !busy && (
          <p className="rp-empty">Ask about delays, cancellations, operators or a station. Answers come from the live data in Fabric.</p>
        )}
        {turns.map((t, i) => (
          <div key={i} className={`rp-msg ${t.role}${t.error ? ' error' : ''}`}>
            {t.role === 'agent' ? renderAnswer(t.text) : t.text}
          </div>
        ))}
        {busy && (
          <div className="rp-typing" aria-label="The agent is working">
            <i /><i /><i />
          </div>
        )}
      </div>
      {turns.length === 0 && (
        <div className="rp-chips">
          {SUGGESTIONS.map((s) => (
            <button key={s} type="button" className="rp-chip" onClick={() => void send(s)} disabled={busy}>
              {s}
            </button>
          ))}
        </div>
      )}
      <form
        className="rp-compose"
        onSubmit={(e) => {
          e.preventDefault();
          void send();
        }}
      >
        <input
          value={question}
          onChange={(e) => setQuestion(e.target.value)}
          placeholder="e.g. Which trains are more than 15 minutes late near Leeds?"
          disabled={busy}
          aria-label="Question"
        />
        <button className="rp-button" type="submit" disabled={busy || !question.trim()}>
          Ask
        </button>
      </form>
      <div className="rp-hint">Data agent questions can take up to a minute. Near-real-time open data – not an official source.</div>
    </section>
  );
}
