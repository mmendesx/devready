## Required JEV decision helper

All AI coding assistants working under these instructions MUST use the JEV
(`laya-jev`) MCP tools whenever a task needs a structured decision: choosing
between concrete alternatives, classifying or routing work, assigning an ordinal
score, or assessing a boolean condition. Consult JEV before acting on each such
decision; do not skip it merely because you already prefer an answer.

- Discover the connected `laya-jev` tools (the client may expose them with a
  `laya_jev` prefix). Use `laya_decide` for a known output schema,
  `laya_predict` for typed questions, or `laya_preset` for a matching workflow.
- Supply relevant observed facts, explicit alternatives, and decision criteria.
  Use `laya_shortlist` before choosing among more than 20 options.
- Treat JEV as a decision helper. Check its confidence and any null or
  low-confidence result. Verify recommendations against the code, requirements,
  and tests; gather more evidence when the result is uncertain. JEV does not
  override user instructions, permissions, or verification requirements.
- Keep code generation, open-ended explanations, and multi-step reasoning in the
  coding assistant. Use JEV for the supported decisions within that work.
- If JEV is unavailable or a call fails, attempt available tool discovery or
  connection checks, report the limitation, and explicitly identify any decision
  made without its help. Never claim JEV was consulted when no call succeeded.
