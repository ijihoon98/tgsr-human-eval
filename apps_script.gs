/**
 * Google Apps Script backend for the TGSR human evaluation.
 *
 * Setup (see README.md for the full walkthrough):
 *   1. Create a Google Sheet, note its URL.
 *   2. sheets.google.com에서 만든 시트에서 확장 프로그램 > Apps Script 열기.
 *   3. Paste this file's content into Code.gs.
 *   4. Deploy > New deployment > type: Web app
 *        - Execute as: Me
 *        - Who has access: Anyone
 *   5. Copy the web app URL into config.js (ENDPOINT_URL).
 *
 * Each POST appends one row:
 *   server_time | study_id | annotator | age | education | item_id | source_id |
 *   referent_accuracy | helpfulness | answer_supportiveness | duration_ms | submitted_at
 */

var SHEET_NAME = 'responses';

function getSheet_() {
  var ss = SpreadsheetApp.getActiveSpreadsheet();
  var sheet = ss.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = ss.insertSheet(SHEET_NAME);
    sheet.appendRow([
      'server_time', 'study_id', 'annotator', 'age', 'education', 'item_id', 'source_id',
      'referent_accuracy', 'helpfulness', 'answer_supportiveness',
      'duration_ms', 'submitted_at',
    ]);
  }
  return sheet;
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(10000); // serialize concurrent submissions
  try {
    var rec = JSON.parse(e.postData.contents);
    getSheet_().appendRow([
      new Date(),
      rec.study_id || '',
      rec.annotator || '',
      rec.age || '',
      rec.education || '',
      rec.item_id || '',
      rec.source_id || '',
      rec.referent_accuracy || '',
      rec.helpfulness || '',
      rec.answer_supportiveness || '',
      rec.duration_ms || '',
      rec.submitted_at || '',
    ]);
    return ContentService
      .createTextOutput(JSON.stringify({ ok: true }))
      .setMimeType(ContentService.MimeType.JSON);
  } catch (err) {
    return ContentService
      .createTextOutput(JSON.stringify({ ok: false, error: String(err) }))
      .setMimeType(ContentService.MimeType.JSON);
  } finally {
    lock.releaseLock();
  }
}

// Health check: open the web app URL in a browser to verify deployment.
function doGet() {
  return ContentService
    .createTextOutput(JSON.stringify({ ok: true, service: 'tgsr-human-eval' }))
    .setMimeType(ContentService.MimeType.JSON);
}
