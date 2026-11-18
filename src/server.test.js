const fs = require('fs');
const os = require('os');
const path = require('path');
const XLSX = require('xlsx');
const { updateWorkbookCard } = require('../server');

test('updates only the selected Q/A row and keeps other sheets intact', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'flashcard-workbook-'));
  const workbookPath = path.join(directory, 'InterviewPrepare.xlsx');
  try {
    const workbook = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(workbook, XLSX.utils.aoa_to_sheet([
      ['QA'], ['Question', 'Answer'], ['Original question', 'Original answer'], ['Keep this row', 'Keep this answer'],
    ]), 'Resume QA');
    XLSX.utils.book_append_sheet(workbook, XLSX.utils.aoa_to_sheet([['Other tab content']]), 'Notes');
    XLSX.writeFile(workbook, workbookPath);

    updateWorkbookCard({
      sheetName: 'Resume QA', sourceRow: 3, questionColumn: 0, answerColumn: 1,
      originalQuestion: 'Original question', originalAnswer: 'Original answer',
      question: 'Edited question', answer: 'Edited answer',
    }, workbookPath);

    const saved = XLSX.readFile(workbookPath);
    expect(saved.Sheets['Resume QA'].A3.v).toBe('Edited question');
    expect(saved.Sheets['Resume QA'].B3.v).toBe('Edited answer');
    expect(saved.Sheets['Resume QA'].A4.v).toBe('Keep this row');
    expect(saved.Sheets.Notes.A1.v).toBe('Other tab content');
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
