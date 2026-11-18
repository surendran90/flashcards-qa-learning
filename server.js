const http = require('http');
const fs = require('fs');
const os = require('os');
const path = require('path');
const XLSX = require('xlsx');
const { parseExcelWorkbook } = require('./src/excelImport');

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
  return sendJson(res, 404, { error: 'Not found' });
});

if (require.main === module) {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`✅ FlashCards OneDrive service listening on 127.0.0.1:${PORT}`);
    console.log(`   Workbook folder: ${WORKBOOK_DIR}`);
  });
}
