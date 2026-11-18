const QUESTION_HEADERS = new Set([
  "question", "questions", "questiontext", "interviewquestion", "prompt", "problem", "problemstatement",
]);
const ANSWER_HEADERS = new Set([
  "answer", "answers", "answertext", "suggestedanswer", "solution", "explanation", "response",
]);

function normalizeHeader(value) {
  return String(value ?? "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]/g, "");
}

function normalizeSheetName(value) {
  return String(value ?? "")
    .normalize("NFKD")
    .replace(/[\u00a0\u2007\u202f]/g, " ")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

function hasQAMarker(value) {
  return /\bq\s*(?:&|\/)?\s*a\b/i.test(String(value ?? "").trim());
}

function getTopic(sheetName) {
  return String(sheetName).trim();
}

function parseExcelWorkbook(XLSX, workbook) {
  const seenQuestions = new Set();
  const additions = [];
  const loadedSheets = [];
  let duplicatesSkipped = 0;

  workbook.SheetNames.forEach(sheetName => {
    const worksheet = workbook.Sheets[sheetName];
    const marker = worksheet?.A1?.v ?? worksheet?.A1?.w ?? "";
    if (!hasQAMarker(marker)) return;

    const rows = XLSX.utils.sheet_to_json(worksheet, {
      header: 1,
      defval: "",
      raw: false,
      blankrows: false,
    });
    loadedSheets.push(sheetName);

    // A1 is the QA marker. Look for optional column labels starting on row 2.
    let headerIndex = -1;
    let questionColumn = 0;
    let answerColumn = 1;
    for (let i = 1; i < Math.min(rows.length, 16); i += 1) {
      const headers = rows[i].map(normalizeHeader);
      const questionIndex = headers.findIndex(name => QUESTION_HEADERS.has(name));
      const answerIndex = headers.findIndex(name => ANSWER_HEADERS.has(name));
      if (questionIndex >= 0 && answerIndex >= 0) {
        headerIndex = i;
        questionColumn = questionIndex;
        answerColumn = answerIndex;
        break;
      }
    }

    const defaultTopic = getTopic(sheetName);
    const firstDataRowIndex = headerIndex >= 0 ? headerIndex + 1 : 1;
    rows.slice(firstDataRowIndex).forEach((row, rowOffset) => {
      const question = String(row?.[questionColumn] ?? "").trim();
      const primaryAnswer = String(row?.[answerColumn] ?? "").trim();
      let resolvedAnswerColumn = answerColumn;
      let answer = primaryAnswer;
      if (!answer && headerIndex < 0) {
        const offset = row?.slice(answerColumn + 1).findIndex(value => String(value ?? "").trim()) ?? -1;
        if (offset >= 0) {
          resolvedAnswerColumn = answerColumn + 1 + offset;
          answer = String(row[resolvedAnswerColumn] ?? "").trim();
        }
      }
      if (!question || /^question$/i.test(question)) return;

      const key = question.toLowerCase();
      if (seenQuestions.has(key)) {
        duplicatesSkipped += 1;
        return;
      }
      additions.push({
        id: `${normalizeSheetName(sheetName)}-${firstDataRowIndex + rowOffset + 1}`,
        topic: defaultTopic,
        question,
        answer,
        sourceSheet: sheetName,
        sourceRow: firstDataRowIndex + rowOffset + 1,
        questionColumn,
        answerColumn: resolvedAnswerColumn,
      });
      seenQuestions.add(key);
    });
  });

  return { additions, loadedSheets, duplicatesSkipped };
}

module.exports = { parseExcelWorkbook, hasQAMarker };
