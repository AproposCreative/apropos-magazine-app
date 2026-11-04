const {test} = require("node:test");
const assert = require("node:assert/strict");
const {EventEmitter} = require("node:events");
const {runBoundedProcess} = require("./boundedProcess");
function fixture() {
  const child = new EventEmitter();child.stderr = new EventEmitter();child.kills = [];
  child.kill = (signal) => {child.kills.push(signal);child.emit("close", null);};
  let fire, cancelled = 0;
  const task = runBoundedProcess({spawn: () => child, executable: "never-executed", args: [],
    schedule: (callback) => {fire = callback;return 1;}, cancel: () => {cancelled += 1;}});
  return {child, task, deadline: () => fire(), cancelled: () => cancelled};
}
test("successful child clears deadline and settles only once", async () => {
  const f = fixture();f.child.emit("close", 0);f.child.emit("error", new Error("late"));await f.task;
  assert.equal(f.cancelled(), 1);
});
test("deadline kills the owned child and reports failure", async () => {
  const f = fixture();f.deadline();await assert.rejects(f.task, /deadline/);assert.deepEqual(f.child.kills, ["SIGKILL"]);
});
test("stderr retention is bounded and launch errors propagate", async () => {
  const f = fixture();f.child.stderr.emit("data", "PRIVATE-START" + "x".repeat(5000) + "TAIL");
  f.child.emit("close", 1);await assert.rejects(f.task, (error) => !error.message.includes("PRIVATE-START") && error.message.endsWith("TAIL") && error.message.length < 900);
  await assert.rejects(runBoundedProcess({spawn: () => {throw new Error("spawn failed");}}), /spawn failed/);
});

test("deadline settles even if the child never acknowledges close", async () => {
  const f = fixture();f.child.kill = (signal) => {f.child.kills.push(signal);};
  f.deadline();await assert.rejects(f.task, /deadline/);
  assert.deepEqual(f.child.kills, ["SIGKILL"]);
});

test("an already completed child is not killed by a late timer callback", async () => {
  const f = fixture();f.child.emit("close", 0);await f.task;f.deadline();assert.deepEqual(f.child.kills, []);
});

test("missing media runtime is rejected before provider work", () => {
  const {assertMediaRuntime} = require("./boundedProcess");
  assert.throws(() => assertMediaRuntime([null, "probe"], () => true), /runtime unavailable/);
  assert.throws(() => assertMediaRuntime(["encoder", "probe"], () => false), /runtime unavailable/);
  assert.doesNotThrow(() => assertMediaRuntime(["fixture-encoder", "fixture-probe"], () => true));
});
