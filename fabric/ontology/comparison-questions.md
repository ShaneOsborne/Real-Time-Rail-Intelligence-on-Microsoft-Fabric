# Before and after: comparison questions (Lab 09b)

Ask each question to **both** data agents, in a new chat each time:

* **A** – `Rail Network Analyst` (Lab 09: KQL database, instructions and example queries)
* **B** – `Rail Network Analyst (ontology)` (Lab 09b: the ontology)

Record the time each takes, whether the answer is right, and what the agent did (expand the steps to see the query and
its language: KQL, GQL or other). Check "right" with the KQL in the last column, run in a KQL queryset on `RailKQL`.

| # | Question | What a good answer does | Check with |
|---|---|---|---|
| 1 | What are the busiest stations in London in the last 30 minutes? | Counts movements across **all** timing points of each station; names stations, not STANOX codes; says which area it used | Example 9 in [`example-queries.md`](../data-agent/example-queries.md) |
| 2 | How many trains are running right now? | Uses the *Active train* rule (last report within 2 hours, not terminated) and says so | `TrainLatest \| where event_time > ago(2h) and coalesce(train_terminated, false) == false \| count` |
| 3 | Which trains are significantly late at the moment? | 15+ minutes, active trains only, shows **headcodes** and where each train was last seen | Example 1 |
| 4 | Where is 1A21? | Treats 1A21 as a headcode (characters 3–6 of `train_id`), may find more than one train | Example 8 |
| 5 | Which operator has the most late trains now? | Groups by operator **name** (through `is_run_by`), not just the code | `TrainLatest \| where event_time > ago(2h) and delay_minutes > 0 \| summarize late = dcount(train_id) by toc_id \| top 5 by late` |
| 6 | How many timing points does Leeds have, and which are they? | Uses `has_timing_point`; lists the STANOX codes and names for CRS LDS | `OntTimingPoints \| where point_crs == "LDS"` |
| 7 | What time was the latest train movement? | **Freshness check.** Should be within a minute or two of the KQL result. If B is much older, it's reading a copy (see the lab's watch-out) | `TrainLatest \| summarize max(event_time)` |
| 8 | Where does train 1A21 go? | Explains that TRUST has **no destination**, then offers what it does have | – |

## Scorecard

| # | A: time (s) | A: right? | B: time (s) | B: right? | Notes (query language, rules used, wrong turns) |
|---|---|---|---|---|---|
| 1 | | | | | |
| 2 | | | | | |
| 3 | | | | | |
| 4 | | | | | |
| 5 | | | | | |
| 6 | | | | | |
| 7 | | | | | |
| 8 | | | | | |

**What to look for.** The ontology should win on *meaning*: stations rather than STANOX codes, operator names, headcodes,
"active" and "late" used consistently, without you writing an example query for each. It won't usually be faster. If A
and B are equally good, that tells you the Lab 09 instructions and examples already carry the meaning, and the
ontology's value is that **other** agents (Foundry, Copilot Studio, operations agents) get the same definitions for free.
