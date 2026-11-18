const { spawn } = require('child_process');
const http = require('http');
const path = require('path');

const api = spawn(process.execPath, [path.join(__dirname, 'server.js')], {
  cwd: __dirname,
  stdio: 'inherit',
  env: process.env,
});
let web;
let stopping = false;

function waitForApi(attempt = 0) {
  return new Promise(resolve => {
    const req = http.get('http://127.0.0.1:3101/api/health', res => {
      res.resume();
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.setTimeout(400, () => { req.destroy(); resolve(false); });
  }).then(ready => {
    if (ready || attempt >= 30) return ready;
    return new Promise(resolve => setTimeout(resolve, 200)).then(() => waitForApi(attempt + 1));
  });
}

function stop() {
  if (stopping) return;
  stopping = true;
  if (web && !web.killed) web.kill('SIGTERM');
  if (api && !api.killed) api.kill('SIGTERM');
}

process.on('SIGINT', stop);
process.on('SIGTERM', stop);
api.on('exit', code => {
  if (!stopping && code !== 0) {
    console.error(`OneDrive reader exited with code ${code}.`);
    if (web && !web.killed) web.kill('SIGTERM');
    process.exitCode = code || 1;
  }
});

waitForApi().then(ready => {
  if (!ready) console.warn('OneDrive reader did not become ready; the app will show a load error if unavailable.');
  const env = { ...process.env, PORT: process.env.PORT || '3002' };
  const reactScripts = path.join(__dirname, 'node_modules', 'react-scripts', 'scripts', 'start.js');
  web = spawn(process.execPath, [reactScripts], { cwd: __dirname, stdio: 'inherit', env });
  web.on('exit', code => {
    if (!stopping) {
      if (api && !api.killed) api.kill('SIGTERM');
      process.exitCode = code || 0;
    }
  });
});
