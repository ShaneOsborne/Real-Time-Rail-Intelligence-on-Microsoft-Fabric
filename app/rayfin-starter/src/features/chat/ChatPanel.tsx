// "Chat with the network": calls the askRailAgent Rayfin function (EXPERIMENTAL), which forwards
// the question to the Foundry agent from Lab 10 on behalf of the signed-in user.
import { useState } from 'react';
import { FunctionsError } from '@microsoft/rayfin-functions';
import { client } from '../../services/rayfinClient';

type Turn = { role: 'user' | 'agent'; text: string };

export function ChatPanel() {
  const [turns, setTurns] = useState<Turn[]>([]);
  const [question, setQuestion] = useState('');
  const [busy, setBusy] = useState(false);

  async function send() {
    const q = question.trim();
    if (!q) return;
    setTurns((t) => [...t, { role: 'user', text: q }]);
    setQuestion('');
    setBusy(true);
    try {
      const answer = await client.functions.askRailAgent.invoke({ question: q });
      setTurns((t) => [...t, { role: 'agent', text: answer }]);
    } catch (error) {
      const msg = error instanceof FunctionsError ? `${error.message} (${error.code})` : String(error);
      setTurns((t) => [...t, { role: 'agent', text: `Sorry – ${msg}` }]);
    } finally {
      setBusy(false);
    }
  }

  return (
    <section>
      <h2>Chat with the network</h2>
      <div style={{ maxHeight: 480, overflowY: 'auto' }}>
        {turns.map((t, i) => (
          <p key={i}>
            <strong>{t.role === 'user' ? 'You' : 'Agent'}:</strong> {t.text}
          </p>
        ))}
      </div>
      <input
        value={question}
        onChange={(e) => setQuestion(e.target.value)}
        onKeyDown={(e) => e.key === 'Enter' && send()}
        placeholder="e.g. Which trains are more than 15 minutes late near Leeds?"
        disabled={busy}
        style={{ width: '100%' }}
      />
    </section>
  );
}
