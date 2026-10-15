// Exercise the actual QML colour functions against light/dark palettes and usage fills.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const qml = fs.readFileSync(path.join(__dirname, '../plugin/Switcher.qml'), 'utf8');
const source = qml.slice(qml.indexOf('  function luminance('), qml.indexOf('  function open('));
const rgb = value => typeof value === 'string' ? {r:parseInt(value.slice(1,3),16)/255,g:parseInt(value.slice(3,5),16)/255,b:parseInt(value.slice(5,7),16)/255} : value;
const context = {Qt: {rgba:(r,g,b,a) => ({r,g,b,a})}, bg: null};
vm.createContext(context);
vm.runInContext(source, context);
const themes = [
  ['dark','#1f1f28','#dcd7ba','#dcd7ba'],
  ['light','#fafafa','#202020','#305080'],
  ['dark accent','#182030','#eeeeee','#223249'],
  ['bright accent','#101315','#cacccc','#f0e060'],
  ['poor roles','#333333','#383838','#777777'],
];
let checks = 0;
for (const [name, surface, text, accent] of themes) {
  context.bg = rgb(surface);
  for (const base of [rgb(surface), rgb(accent)]) {
    const ink = rgb(context.readableText(base, rgb(text)));
    assert.ok(context.contrast(base, ink) >= 4.5, name);
    if (context.contrast(base, rgb(text)) >= 4.5) assert.equal(context.readableText(base,rgb(text)).r, rgb(text).r, name+' preserves text role');
    for (const fill of ['#E5534B','#E3A23B',accent]) {
      const colour = rgb(fill);
      const alpha = context.readableFillOpacity(base, ink, colour, 0.45);
      assert.ok(alpha >= 0 && alpha <= 0.45);
      const mixed = {r:base.r*(1-alpha)+colour.r*alpha,g:base.g*(1-alpha)+colour.g*alpha,b:base.b*(1-alpha)+colour.b*alpha};
      assert.ok(context.contrast(mixed,ink) >= 4.5, name+' usage fill');
      checks++;
    }
  }
}
console.log(`Theme roles and usage fills: ${checks} contrast scenarios passed.`);
