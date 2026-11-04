// Injectable child runner: tests use an EventEmitter, never a binary.
function runBoundedProcess({spawn, executable, args, timeoutMs = 120000, schedule = setTimeout, cancel = clearTimeout}) {
  return new Promise((resolve, reject) => {
    let child;
    try {child = spawn(executable, args, {stdio: ["ignore", "ignore", "pipe"]});} catch (error) {reject(error);return;}
    let stderr = "", settled = false, timer;
    const finish = (error) => {
      if (settled) return;
      settled = true;
      if (timer !== undefined) cancel(timer);
      if (error) reject(error);else resolve();
    };
    child.stderr?.on("data", (chunk) => {if (!settled) stderr = (stderr + String(chunk)).slice(-1600);});
    child.on("error", (error) => finish(error));
    child.on("close", (code) => finish(code === 0 ? null : new Error(`Media process exit ${code}: ${stderr.slice(-800)}`)));
    timer = schedule(() => {
      if (settled) return;
      finish(new Error("Media process deadline exceeded"));
      try {child.kill("SIGKILL");} catch { /* deadline remains authoritative */ }
    }, timeoutMs);
    if (settled) cancel(timer); // Also supports a synchronous injected deadline.
  });
}
function assertMediaRuntime(paths, exists) {
  if (!paths.every((path) => typeof path === "string" && !!path && exists(path))) throw new Error("Media runtime unavailable before synthesis");
}
module.exports = {runBoundedProcess, assertMediaRuntime};
