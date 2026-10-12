// Exercise the actual QML controller logic without account or desktop access.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const qml = fs.readFileSync(path.join(__dirname, '../plugin/Switcher.qml'), 'utf8');
function extract(name) {
  const start = qml.indexOf(`  function ${name}(`);
  assert.ok(start >= 0, name);
  if (name === 'close') return qml.slice(start, qml.indexOf('\n', start));
  const end = qml.indexOf('\n  }\n', start);
  assert.ok(end > start, name);
  return qml.slice(start, end + 5);
}
const writes = [], signals = [], actions = [];
const c = {
  opened: true, controlMode: 'add', menuFor: '', sheet: false,
  desktopBlocked: false, loginCancelled: false, loginVisible: false,
  loginPresented: false, loginAgent: 'A', pendingLoginAction: '', controlError: '',
  loginProc: {running:true, write:s=>writes.push(s), signal:s=>signals.push(s)},
  endArrange() {}, loadCatalog() {}, run:a=>actions.push(a),
  beginLogin() { throw new Error('The active session must be reused'); },
};
c.root = c;
vm.createContext(c);
vm.runInContext(['close','loginAction','resumeSignin','handleLoginResult'].map(extract).join('\n'), c);
let scenarios = 0;
function test(name, check) { check(); scenarios++; }
test('decision dialog hides the strip', () => {
  c.handleLoginResult({name:'A',state:'confirmation_needed'});
  assert.equal(c.loginVisible, true); assert.equal(c.opened, false);
  assert.equal(signals.length, 0);
});
test('opening hides the controller immediately', () => {
  c.loginAction('open'); assert.equal(c.loginVisible, false);
  assert.equal(writes.at(-1), 'open\n');
});
test('opening and awaiting login do not retain the controller', () => {
  c.handleLoginResult({name:'A',state:'opening'});
  c.handleLoginResult({name:'A',state:'awaiting_login'});
  assert.equal(c.loginVisible, false);
});
test('overlay hide preserves a tucked-away sign-in session', () => {
  c.close(); assert.equal(signals.length, 0); assert.equal(c.loginPresented, true);
});
test('shortcut resumes and toggles the same controller', () => {
  assert.equal(c.resumeSignin('show'), 'handled'); assert.equal(c.loginVisible, true);
  assert.equal(c.resumeSignin('toggle'), 'handled'); assert.equal(c.loginVisible, false);
});
test('an explicit resume survives a slow agent launch', () => {
  c.resumeSignin('show'); c.handleLoginResult({name:'A',state:'awaiting_login'});
  assert.equal(c.loginVisible, true);
});
test('hide does not cancel; check again shows progress', () => {
  c.loginAction('hide'); assert.equal(signals.length, 0);
  c.resumeSignin('show'); c.loginAction('check');
  assert.equal(c.loginResult.state, 'checking'); assert.equal(writes.at(-1), 'check\n');
});
test('unsupported recheck allows an explicit confirmation', () => {
  c.handleLoginResult({name:'A',state:'confirmation_needed'});
  assert.equal(c.loginVisible, true);
});
test('completion removes the controller and returns to the picker', () => {
  c.handleLoginResult({name:'A',state:'added'});
  assert.equal(c.loginVisible, false); assert.equal(c.loginPresented, false);
  assert.equal(actions.at(-1)[0], 'configure');
});
test('cancel clears pending state and discards late completion', () => {
  c.loginPresented = true; c.loginVisible = true;
  const count = actions.length;
  c.loginAction('cancel'); c.handleLoginResult({name:'A',state:'added'});
  assert.equal(signals.at(-1), 15); assert.equal(c.loginPresented, false);
  assert.equal(actions.length, count); assert.equal(c.resumeSignin('show'), 'none');
});
test('idle and locked desktop cannot resume a controller', () => {
  c.loginCancelled = false; c.loginPresented = true; c.desktopBlocked = true;
  assert.equal(c.resumeSignin('show'), 'none'); assert.equal(c.loginVisible, false);
});
console.log(`Sign-in controller: ${scenarios} state scenarios passed.`);
