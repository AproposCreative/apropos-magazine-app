const {test} = require("node:test");
const assert = require("node:assert/strict");
const fixture = require("./fixtures/reader-ledger-cleanup-wire-v1.json");
const parentFixture = require("./fixtures/reader-account-deletion-wire-v1.json");
const {LEDGER_SCOPE, LEDGER_UNRESOLVED} = require("./readerAccountDeletion");
const {generateReaderLedgerCleanupWire} = require("./fixtures/reader-ledger-cleanup-wire-generator");

test("native ledger wire fixture exactly matches actual mutation, parent and child worker results", async () => {
  assert.deepEqual(await generateReaderLedgerCleanupWire(), fixture);
});

test("ledger wire extends the original completed parent without changing its existing v1 fixture", () => {
  assert.deepEqual(fixture.parentReceipt, parentFixture.receipts.partial);
  assert.equal(fixture.request.parentRequestID, parentFixture.receipts.partial.requestID);
  assert.notEqual(fixture.receipts.complete.requestID, fixture.request.parentRequestID);
  assert.equal(fixture.receipts.complete.scope, LEDGER_SCOPE);
  assert.deepEqual(fixture.receipts.complete.unresolved, LEDGER_UNRESOLVED);
  assert.equal(fixture.receipts.complete.accountDeletionComplete, false);
});

test("wire retains full admission/progress and bounded worker forms without inventing absent parent or counters", () => {
  const {admissionPending, boundedPending, progressPending, paused, complete} = fixture.receipts;
  for (const value of [admissionPending, progressPending, complete]) {
    assert.equal(value.parentRequestID, fixture.request.parentRequestID);
    assert.ok(Number.isSafeInteger(value.removedReceiptDocuments));
    assert.ok(Number.isSafeInteger(value.removedRevisionDocuments));
  }
  for (const value of [boundedPending, paused]) {
    assert.equal(Object.hasOwn(value, "parentRequestID"), false);
    assert.equal(Object.hasOwn(value, "removedReceiptDocuments"), false);
    assert.equal(Object.hasOwn(value, "removedRevisionDocuments"), false);
  }
  assert.equal(admissionPending.removedReceiptDocuments, 0);
  assert.equal(progressPending.removedReceiptDocuments, 3);
  assert.equal(progressPending.removedRevisionDocuments, 0);
  assert.equal(complete.removedReceiptDocuments, 3);
  assert.equal(complete.removedRevisionDocuments, 3);
});
