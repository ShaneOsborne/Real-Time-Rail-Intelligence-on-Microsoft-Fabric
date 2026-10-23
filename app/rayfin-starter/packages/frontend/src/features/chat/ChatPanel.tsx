// "Chat with the network": calls the askRailAgent Rayfin function (EXPERIMENTAL), which forwards
// the question to the Foundry agent from Lab 10 on behalf of the signed-in user.
import { useState } from 'react';
import { railFunctions } from '../../services/railClient';

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
      const functions = await railFunctions();
      const answer = await functions.askRailAgent.invoke({ question: q }, { timeoutMs: 120_000 });
      setTurns((t) => [...t, { role: 'agent', text: answer }]);
    } catch (error) {
      // Function failures arrive as FunctionsError (code FUNCTION_EXECUTION_ERROR); its message is enough here.
      const msg = error instanceof Error ? error.message : String(error);
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
