const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { transformSync } = require('../../web-tools/node_modules/esbuild');

/** Runs real non-UI ArkTS modules; platform boundaries and decorators are explicit stubs. */
module.exports = function createLoader(kits, globals = {}) {
  const cache = new Map();
  function load(file) {
    file = path.resolve(file.endsWith('.ets') ? file : `${file}.ets`);
    if (cache.has(file)) return cache.get(file).exports;
    const module = { exports: {} }; cache.set(file, module);
    const code = transformSync(fs.readFileSync(file, 'utf8'), { loader: 'ts', format: 'cjs', target: 'es2022' }).code;
    const req = name => kits[name] || (name.startsWith('.') ? load(path.resolve(path.dirname(file), name)) : require(name));
    const keys = Object.keys(globals);
    vm.runInThisContext(`(function(require,module,exports,${keys.join(',')}){${code}\n})`, { filename: file })
      (req, module, module.exports, ...Object.values(globals));
    return module.exports;
  }
  return load;
};
