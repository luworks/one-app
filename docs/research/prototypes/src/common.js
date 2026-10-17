// Shared by every prototype. Fictional demo: fixed clock, no network, nothing persisted.
const D0 = new Date(2026, 9, 15); // Thursday 15 Oct 2026 = day 0 of tests/fixtures/today-dataset.json
const NOW = 9 * 60 + 41;          // 09:41
const WD = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const mins = t => { const [h, m] = t.split(':').map(Number); return h * 60 + m; };
const hm = m => `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`;
const dayDate = d => { const x = new Date(D0); x.setDate(x.getDate() + d); return x; };
const dayLabel = d => d === 0 ? 'Today' : d === -1 ? 'Yesterday' : d === 1 ? 'Tomorrow' : `${WD[dayDate(d).getDay()]} ${dayDate(d).getDate()} Oct`;
const when = w => w ? `${dayLabel(w.day)}${w.time ? ' ' + w.time : ''}` : '';

// Fictional agents. Names are examples of what could connect; none of this exists yet.
const ACTORS = {
  you:      { name: 'You',         short: 'Y',  color: 'var(--ink)',  via: 'Today app' },
  today:    { name: 'Today AI',    short: 'AI', color: 'var(--ai)',   via: 'On-device model' },
  trip:     { name: 'Trip agent',  short: 'Tr', color: '#0E7C86',     via: 'Mac · MCP' },
  inbox:    { name: 'Inbox agent', short: 'In', color: '#B4572E',     via: 'Mac · MCP' },
  code:     { name: 'Coding agent',short: '</>',color: '#4A5BD0',     via: 'Mac · MCP' },
  shortcut: { name: 'Shortcuts',   short: 'Sc', color: '#6B7280',     via: 'App Intent' },
};
const INTENTS = {
  demo:  { title: 'Demo ready', detail: 'Prepare the demo · due Tomorrow 17:00' },
  tokyo: { title: 'Tokyo trip', detail: 'Flight Tue 08:15 · flights, passport' },
  mia:   { title: "Mia's birthday", detail: 'Dinner Sun 19:00 · gift due Sun 12:00' },
  pr:    { title: 'Ship PR #25', detail: 'Fix ListEditor Bool literals' },
  day:   { title: 'A good Thursday', detail: 'Today’s plan and what actually happened' },
};
// Autonomy tiers (see docs/research/ai-native-vision.md §4.3)
const TIERS = {
  0: { name: 'Observe', desc: 'Reads or notices. Logged, never asks.' },
  1: { name: 'Local', desc: 'Changes only Today’s own copy (planned time, links, notes in the ledger). Can be allowed per agent. One-tap undo.' },
  2: { name: 'Apple apps', desc: 'Writes to Apple Calendar, Reminders or alarms. Asks unless you granted this agent this kind of change, for a while.' },
  3: { name: 'Other people', desc: 'Notifies someone, deletes, sends or spends. Always asks. Cannot be pre-approved.' },
};
// The shared ledger: append-only records of intentions → actions → outcomes.
const LEDGER = [
  { id:'L01', at:{day:-1,time:'16:40'}, actor:'you', via:'Ask AI', intent:'tokyo', verb:'created', object:{type:'reminder',title:'Book flights to Tokyo'}, after:'Due Sun 17:00 · flagged', tier:2, state:'approved', writes:['Apple Reminders'] },
  { id:'L02', at:{day:-1,time:'17:00'}, actor:'today', via:'On-device', intent:'day', verb:'noticed', object:{type:'reminder',title:'Pay studio invoice'}, after:'Overdue. Stays visible; not moved.', tier:0, state:'auto' },
  { id:'L03', at:{day:-1,time:'18:02'}, actor:'you', via:'Today app', intent:'day', verb:'completed', object:{type:'reminder',title:'Call plumber'}, tier:2, state:'approved', writes:['Apple Reminders'] },
  { id:'L04', at:{day:-1,time:'19:10'}, actor:'trip', via:'MCP', intent:'tokyo', verb:'proposed', object:{type:'reminder',title:'Renew passport'}, before:'Due 29 Oct', after:'Delete (looks like a duplicate)', tier:3, state:'declined', by:'you · 19:12', writes:['Apple Reminders'], why:'Found “passport” in two places.' },
  { id:'L05', at:{day:-1,time:'21:30'}, actor:'today', via:'On-device', intent:'demo', verb:'moved', object:{type:'reminder',title:'Prepare the demo'}, before:'Unplanned', after:'Today 13:30 · 45 min', tier:1, state:'approved', by:'you · 21:31', writes:['Today only'], why:'Evening plan for tomorrow. Deadline unchanged.' },
  { id:'L06', at:{day:-1,time:'22:05'}, actor:'code', via:'MCP', intent:'pr', verb:'opened', object:{type:'outcome',title:'PR #25 · Fix ListEditor Bool literals'}, after:'Waiting for review', tier:0, state:'auto' },
  { id:'L07', at:{day:0,time:'06:30'}, actor:'you', via:'Alarm', intent:'day', verb:'stopped', object:{type:'alarm',title:'Wake up'}, after:'Stopped 06:34. Stopping an alarm is not finishing a task.', tier:0, state:'auto' },
  { id:'L08', at:{day:0,time:'07:00'}, actor:'today', via:'On-device', intent:'day', verb:'prepared', object:{type:'chat',title:'Morning brief'}, after:'5 events, 6 reminders, 1 overdue', tier:1, state:'auto', writes:['Today only'] },
  { id:'L09', at:{day:0,time:'07:58'}, actor:'inbox', via:'MCP', intent:'day', verb:'linked', object:{type:'reminder',title:'Reply to Sam'}, after:'Linked email “Notes by 5?”', tier:1, state:'auto', grant:'Inbox agent may link emails to reminders · until 14 Nov', writes:['Today only'] },
  { id:'L10', at:{day:0,time:'08:05'}, actor:'shortcut', via:'App Intent', intent:'day', verb:'reported', object:{type:'signal',title:'Left home'}, after:'Commute started', tier:0, state:'auto' },
  { id:'L11', at:{day:0,time:'08:30'}, actor:'trip', via:'MCP', intent:'tokyo', verb:'proposed', object:{type:'reminder',title:'Book flights to Tokyo'}, before:'No notes', after:'Add 2 fares to notes · cheapest JL 704, book by Sat', tier:2, state:'pending', writes:['Apple Reminders'], why:'Fare went up twice this week. Booking itself stays with you.' },
  { id:'L12', at:{day:0,time:'08:31'}, actor:'trip', via:'MCP', intent:'tokyo', verb:'proposed', object:{type:'event',title:'Leave for airport'}, before:'—', after:'New event Tue 06:15–06:55', tier:2, state:'pending', writes:['Apple Calendar'], why:'Flight 08:15; 40 min to the airport at that hour.' },
  { id:'L13', at:{day:0,time:'08:45'}, actor:'trip', via:'MCP', intent:'tokyo', verb:'failed', object:{type:'reminder',title:'Online check-in'}, after:'List “Travel” does not exist. Nothing written.', tier:2, state:'failed', writes:['Apple Reminders'] },
  { id:'L14', at:{day:0,time:'09:02'}, actor:'inbox', via:'MCP', intent:'day', verb:'proposed', object:{type:'event',title:'Weekly sync'}, before:'Tomorrow 11:00', after:'Tomorrow 11:30 (this occurrence)', tier:3, state:'pending', notifies:4, writes:['Apple Calendar'], why:'Priya asked by email to start 30 min later.' },
  { id:'L15', at:{day:0,time:'09:25'}, actor:'today', via:'Calendar', intent:'day', verb:'noticed', object:{type:'signal',title:'Product sync ended'}, after:'Ended 9:25, on time', tier:0, state:'auto' },
  { id:'L16', at:{day:0,time:'09:30'}, actor:'code', via:'MCP', intent:'pr', verb:'proposed', object:{type:'reminder',title:'Review PR #25'}, before:'—', after:'New reminder · Today 11:00 · 20 min', tier:2, state:'pending', writes:['Apple Reminders'], why:'CI is green and you are the requested reviewer.' },
  { id:'L17', at:{day:0,time:'09:35'}, actor:'inbox', via:'MCP', intent:'mia', verb:'proposed', object:{type:'reminder',title:'Order birthday gift'}, before:'No notes', after:'Add note: Mia’s wishlist link (from her email)', tier:2, state:'pending', writes:['Apple Reminders'], why:'Due Sun 12:00; delivery takes 2 days.' },
  { id:'L18', at:{day:0,time:'09:41'}, actor:'today', via:'On-device', intent:'demo', verb:'proposed', object:{type:'plan',title:'Re-plan today'}, before:'Demo 13:30', after:'4 changes · demo 10:00, leave 14:30, milk 15:45', tier:1, state:'pending', writes:['Today only','Alarm (1)'], why:'Morning is free after standup; rain from 17:30.' },
];
const pendingCount = () => LEDGER.filter(r => r.state === 'pending').length;
const ICONS = {
  menu:'<path d="M4 7h16M4 12h16M4 17h16"/>', spark:'<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>',
  check:'<path d="M5 12.5l4.5 4.5L19 7.5"/>', x:'<path d="M6 6l12 12M18 6L6 18"/>', undo:'<path d="M9 14L4 9l5-5"/><path d="M4 9h10a6 6 0 010 12h-2"/>',
  clock:'<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>', car:'<path d="M5 16V11l2-5h10l2 5v5M5 16h14M7.5 16v2M16.5 16v2"/><circle cx="8" cy="13" r=".8"/><circle cx="16" cy="13" r=".8"/>',
  rain:'<path d="M7 15a4 4 0 01.5-8 5 5 0 019.5 1.5A3.5 3.5 0 0117 15z"/><path d="M9 18l-1 2M13 18l-1 2M17 18l-1 2"/>',
  bed:'<path d="M3 18V8M3 14h18v4M21 14v-2a3 3 0 00-3-3h-7v5"/><circle cx="7" cy="11" r="1.6"/>', bolt:'<path d="M13 3L5 13h6l-1 8 8-10h-6z"/>',
  lock:'<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 018 0v3"/>', shield:'<path d="M12 3l7 3v6c0 4-3 7.5-7 9-4-1.5-7-5-7-9V6z"/>',
  people:'<circle cx="9" cy="9" r="3"/><circle cx="17" cy="10" r="2.4"/><path d="M3.5 19a5.5 5.5 0 0111 0M15 19a4 4 0 016 0"/>',
  chev:'<path d="M9 6l6 6-6 6"/>', mic:'<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0013 0M12 17.5V21"/>',
  graph:'<circle cx="6" cy="12" r="2.5"/><circle cx="18" cy="6" r="2.5"/><circle cx="18" cy="18" r="2.5"/><path d="M8.3 11l7.4-3.8M8.3 13l7.4 3.8"/>',
  inbox:'<path d="M4 13l2.5-7h11L20 13v6H4z"/><path d="M4 13h5l1 2h4l1-2h5"/>',
};
const ic = (n, c = '') => `<svg class="ic ${c}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[n] || ''}</svg>`;
const av = a => `<span class="av" style="background:${ACTORS[a].color};${a === 'you' ? 'color:var(--bg)' : ''}">${esc(ACTORS[a].short)}</span>`;
function chrome(active) {
  const tabs = ['Today','Calendar','Reminders','Alarms'];
  return `<div class="status"><span>9:41</span><span style="font-size:12px">●●● ▮</span></div>
  <div class="top"><button class="ibtn" aria-label="Menu" onclick="location.href='agent-board.html'">${ic('menu')}</button>
  <div class="pills">${tabs.map(t => `<span class="pill-t ${t === active ? 'on' : ''}">${t}</span>`).join('')}</div>
  <a class="ibtn" aria-label="Approvals" href="approval-inbox.html" style="position:relative;color:var(--ai)">${ic('inbox')}<span id="badge" style="position:absolute;top:4px;right:3px;min-width:16px;height:16px;border-radius:8px;background:var(--ai);color:#fff;font-size:10px;font-weight:700;display:grid;place-items:center;padding:0 3px">${pendingCount()}</span></a></div>`;
}
const dock = () => `<div class="dock"><div class="ask">${ic('spark')}<span style="flex:1">Ask AI or add anything</span>${ic('mic')}</div><div class="plus">+</div></div>`;
let toastTimer;
function toast(msg, undo) {
  const t = document.getElementById('toast');
  t.innerHTML = `<span>${esc(msg)}</span>${undo ? '<button id="t-undo">Undo</button>' : ''}`;
  t.classList.add('on');
  if (undo) document.getElementById('t-undo').onclick = () => { t.classList.remove('on'); undo(); };
  clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove('on'), 4000);
}
function openSheet(title, html) {
  document.getElementById('sh-title').textContent = title;
  document.getElementById('sh-body').innerHTML = html;
  document.getElementById('scrim').classList.add('on'); document.getElementById('sheet').classList.add('on');
}
function closeSheet() { document.getElementById('scrim').classList.remove('on'); document.getElementById('sheet').classList.remove('on'); }
const sheetHTML = () => `<div class="toast" id="toast"></div><div class="sheet-scrim" id="scrim" onclick="closeSheet()"></div>
<div class="sheet" id="sheet" role="dialog" aria-labelledby="sh-title"><div class="sh-h"><span id="sh-title"></span><button class="btn sec" onclick="closeSheet()">Done</button></div><div class="sh-b" id="sh-body"></div></div>`;
function recordJSON(r) {
  const o = { id: r.id, at: `${dayDate(r.at.day).toISOString().slice(0,10)}T${r.at.time}`, actor: r.actor, via: r.via, intent: r.intent, verb: r.verb, object: r.object };
  if (r.before) o.before = r.before; if (r.after) o.after = r.after;
  o.tier = r.tier; o.approval = { state: r.state, ...(r.by ? { by: r.by } : {}), ...(r.grant ? { grant: r.grant } : {}) };
  o.effects = { writes: r.writes || [], notifies: r.notifies || 0, undo: r.tier < 3 ? 'one tap' : (r.notifies ? 'sends a second update' : 'restore from ledger') };
  if (r.why) o.why = r.why;
  return JSON.stringify(o, null, 2);
}
