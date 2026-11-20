// Sync the repository's role instructions to the local Pokpok Paperclip instance.
// Preview by default. --apply uses revision checks and verifies every readback.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const api = 'http://127.0.0.1:3100/api';
const companyId = '696941b8-3918-40a1-868e-f81178444a60';
const roles = {
  CTO: 'cto',
  'Engineer – App': 'engineer-app',
  'Engineer – Web': 'engineer-web',
  'Reviewer / QA': 'reviewer-qa',
  'Release Coordinator': 'release-coordinator',
  'CMO / Growth': 'cmo-growth',
  'Content Marketer': 'content-marketer',
  'COO / Field Ops': 'coo-field-ops',
  'Support Desk': 'support-desk',
  'CFO / Finance': 'cfo-finance',
  'Security & Data': 'security-data',
  Researcher: 'researcher',
};
const apply = process.argv.includes('--apply');

async function request(route, options) {
  const response = await fetch(api + route, options);
  assert.ok(response.ok, `${route}: HTTP ${response.status}`);
  return response.json();
}

const agents = await request(`/companies/${companyId}/agents`);
assert.equal(agents.length, 13, 'Review the roster before syncing changed roles');
const changes = [];
for (const agent of agents) {
  let content;
  if (agent.name === 'CEO') {
    const doc = await readFile(new URL('../../docs/paperclip-ceo-role.md', import.meta.url), 'utf8');
    content = doc.match(/```markdown\r?\n(# CEO[\s\S]*?)\r?\n```/)?.[1];
    assert.ok(content, 'CEO instruction block missing');
  } else {
    assert.ok(roles[agent.name], `Unmapped agent ${agent.name}`);
    content = await readFile(new URL(`../../docs/paperclip-agents/${roles[agent.name]}.md`, import.meta.url), 'utf8');
  }
  content = content.replaceAll('\r\n', '\n').trimEnd() + '\n';
  const route = `/agents/${agent.id}/instructions-bundle/file`;
  const current = await request(route + '?path=AGENTS.md');
  if (current.content.replaceAll('\r\n', '\n').trimEnd() === content.trimEnd()) {
    console.log(`${agent.name}: matches`);
    continue;
  }
  assert.ok(current.revision?.id, `${agent.name}: missing instruction revision`);
  changes.push({ name: agent.name, route, content, revision: current.revision.id });
}
for (const change of changes) {
  if (!apply) {
    console.log(`${change.name}: update pending`);
    continue;
  }
  await request(change.route, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ path: 'AGENTS.md', content: change.content, baseRevisionId: change.revision }),
  });
  const saved = await request(change.route + '?path=AGENTS.md');
  assert.equal(saved.content, change.content, `${change.name}: readback mismatch`);
  console.log(`${change.name}: saved and verified`);
}
