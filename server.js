const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const XLSX = require('xlsx');
const { parseExcelWorkbook, hasQAMarker } = require('./src/excelImport');

const PORT = Number(process.env.QA_API_PORT || 3101);
const WORKBOOK_DIR = path.join(
  os.homedir(),
  'Library', 'CloudStorage', 'OneDrive-Personal', 'Interview', 'Interview Preparation'
);

function normalizeFileName(name) {
  return String(name).toLowerCase().replace(/[^a-z0-9]/g, '');
}

function findWorkbookPath() {
  const files = fs.readdirSync(WORKBOOK_DIR);
  const expectedName = normalizeFileName('InterviewPrepare.xlsx');
  const candidate = files.find(name => normalizeFileName(name) === expectedName);
  if (!candidate) {
    throw new Error(`Could not find InterviewPrepare.xlsx in ${WORKBOOK_DIR}.`);
  }
  return path.join(WORKBOOK_DIR, candidate);
}

function readWorkbookData() {
  const workbookPath = findWorkbookPath();
  const workbook = XLSX.readFile(workbookPath, { cellDates: true });
  const parsed = parseExcelWorkbook(XLSX, workbook);
  const stat = fs.statSync(workbookPath);
  return {
    cards: parsed.additions.map(card => ({ ...card, sourceFile: 'onedrive' })),
    loadedSheets: parsed.loadedSheets,
    duplicatesSkipped: parsed.duplicatesSkipped,
    fileName: path.basename(workbookPath),
    updatedAt: stat.mtime.toISOString(),
  };
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
      if (body.length > 1024 * 1024) reject(new Error('Request is too large.'));
    });
    req.on('end', () => {
      try { resolve(JSON.parse(body || '{}')); }
      catch { reject(new Error('Invalid JSON request.')); }
    });
    req.on('error', reject);
  });
}

function updateWorkbookCard(data, workbookPath = findWorkbookPath()) {
  const workbook = XLSX.readFile(workbookPath, { cellDates: true, cellStyles: true });
  const { sheetName, sourceRow, questionColumn, answerColumn, originalQuestion, originalAnswer } = data;
  const question = String(data.question ?? '').trim();
  const answer = String(data.answer ?? '');
  if (!question) throw Object.assign(new Error('Question cannot be empty.'), { statusCode: 400 });
  if (!Number.isInteger(sourceRow) || sourceRow < 2 || !Number.isInteger(questionColumn) || questionColumn < 0 || !Number.isInteger(answerColumn) || answerColumn < 0) {
    throw Object.assign(new Error('Invalid Excel cell coordinates.'), { statusCode: 400 });
  }
  const worksheet = workbook.Sheets[sheetName];
  if (!worksheet || !hasQAMarker(worksheet.A1?.v ?? worksheet.A1?.w ?? '')) {
    throw Object.assign(new Error('That worksheet is no longer marked as a Q/A tab.'), { statusCode: 409 });
  }
  const questionAddress = XLSX.utils.encode_cell({ r: sourceRow - 1, c: questionColumn });
  const answerAddress = XLSX.utils.encode_cell({ r: sourceRow - 1, c: answerColumn });
  const cellText = address => String(worksheet[address]?.v ?? worksheet[address]?.w ?? '').trim();
  if (cellText(questionAddress) !== String(originalQuestion ?? '').trim() || cellText(answerAddress) !== String(originalAnswer ?? '').trim()) {
    throw Object.assign(new Error('This row changed in Excel after it was loaded. Refresh the workbook and try again.'), { statusCode: 409 });
  }
  const setTextCell = (address, value) => {
    const previous = worksheet[address] || {};
    worksheet[address] = { ...previous, t: 's', v: value };
    delete worksheet[address].w;
  };
  setTextCell(questionAddress, question);
  setTextCell(answerAddress, answer);

  // Write beside the original and atomically replace it to avoid a partial workbook on interruption.
  const tempPath = path.join(path.dirname(workbookPath), `.${path.basename(workbookPath)}.${process.pid}.tmp`);
  try {
    fs.writeFileSync(tempPath, XLSX.write(workbook, { bookType: 'xlsx', type: 'buffer', cellStyles: true }));
    fs.renameSync(tempPath, workbookPath);
  } catch (error) {
    try { fs.unlinkSync(tempPath); } catch {}
    throw error;
  }
  const stat = fs.statSync(workbookPath);
  return { fileName: path.basename(workbookPath), updatedAt: stat.mtime.toISOString(), sheetName, sourceRow, question, answer };
}

function sendJson(res, status, data) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify(data));
}

const server = http.createServer((req, res) => {
  const pathname = new URL(req.url, `http://${req.headers.host || 'localhost'}`).pathname;
  if (req.method === 'GET' && pathname === '/api/health') {
    return sendJson(res, 200, { ok: true });
  }
  if (req.method === 'GET' && pathname === '/api/qa') {
    try {
      return sendJson(res, 200, readWorkbookData());
    } catch (error) {
      console.error('OneDrive workbook read failed:', error.message);
      return sendJson(res, 503, { error: error.message });
    }
  }
  if (req.method === 'POST' && pathname === '/api/qa/update') {
    readJsonBody(req).then(data => {
      try { return sendJson(res, 200, updateWorkbookCard(data)); }
      catch (error) {
        console.error('OneDrive workbook update failed:', error.message);
        return sendJson(res, error.statusCode || 500, { error: error.message });
      }
    }).catch(error => sendJson(res, 400, { error: error.message }));
    return;
  }
  return sendJson(res, 404, { error: 'Not found' });
});

if (require.main === module) {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`✅ FlashCards OneDrive service listening on 127.0.0.1:${PORT}`);
    console.log(`   Workbook folder: ${WORKBOOK_DIR}`);
  });
}

module.exports = { updateWorkbookCard };
