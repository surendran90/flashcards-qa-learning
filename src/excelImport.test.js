import * as XLSX from "xlsx";
import { parseExcelWorkbook } from "./excelImport";

function makeWorkbook(sheets) {
  const workbook = { SheetNames: Object.keys(sheets), Sheets: {}, utils: XLSX.utils };
  Object.entries(sheets).forEach(([name, rows]) => {
    workbook.Sheets[name] = XLSX.utils.aoa_to_sheet(rows);
  });
  return workbook;
}

test("imports every tab marked QA in A1 and skips unmarked tabs", () => {
  const workbook = makeWorkbook({
    "Resume QA": [["QA"], ["Tell me about yourself", "A concise introduction." ]],
    "Embedded QA": [["QA"], ["What is volatile?", "A qualifier for externally changing values." ]],
    Planner: [["Tasks"], ["Not a Q&A tab", "Should not be imported." ]],
  });
  const result = parseExcelWorkbook(XLSX, workbook);
  expect(result.loadedSheets).toEqual(["Resume QA", "Embedded QA"]);
  expect(result.additions).toHaveLength(2);
  expect(result.additions[0]).toMatchObject({
    topic: "Resume QA",
    question: "Tell me about yourself",
    answer: "A concise introduction.",
  });
  expect(result.additions[1].topic).toBe("Embedded QA");
});

test("supports optional headers after the A1 QA marker and deduplicates within the workbook", () => {
  const workbook = makeWorkbook({
    "Resume QA": [
      ["Q&A"],
      ["ID", "Category", "Answer", "Question"],
      ["1", "Resume", "Reliable delivery.", "What does TCP provide?"],
      ["2", "Resume", "Repeated answer.", "What does TCP provide?"],
    ],
  });
  const result = parseExcelWorkbook(XLSX, workbook);
  expect(result.additions).toHaveLength(1);
  expect(result.additions[0]).toMatchObject({
    topic: "Resume QA",
    question: "What does TCP provide?",
    answer: "Reliable delivery.",
  });
  expect(result.duplicatesSkipped).toBe(1);
});

test("does not import a tab unless A1 contains a QA marker", () => {
  const workbook = makeWorkbook({
    "Resume QA": [["Question"], ["A question", "An answer"]],
  });
  expect(parseExcelWorkbook(XLSX, workbook).additions).toHaveLength(0);
});

test("uses a renamed QA tab name as the category", () => {
  const workbook = makeWorkbook({
    "CV Preparation": [["QA"], ["What does a resume summary do?", "It introduces relevant qualifications."]],
  });
  const result = parseExcelWorkbook(XLSX, workbook);
  expect(result.loadedSheets).toEqual(["CV Preparation"]);
  expect(result.additions[0].topic).toBe("CV Preparation");
});
