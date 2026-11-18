# FlashCards QA Learning

A question practice app that runs on your computer. It loads the Q/A tabs from your OneDrive workbook on launch; you can also import another workbook, practice by category, reveal answers, and retry questions you missed.

[Quick start](#quick-start) · [Features](#features) · [Import questions](#import-questions) · [Data storage](#data-storage)

## What it does

FlashCards QA Learning turns your interview Q&A workbook into a focused flashcard practice session. Choose one category or the full bank, decide whether to shuffle, and work through questions at your own pace.

## Quick start

### What you need

- [Node.js](https://nodejs.org/) with npm
- Your question workbook in `.xlsx` or `.xls` format (optional; you can import it after launching the app)

### Install and run

Open Terminal in the project folder and run:

```bash
npm install
npm start
```

This starts both the local OneDrive reader and the React app. On this computer, you can enter the folder with:

```bash
cd "/Users/suren/FlashCards QA Learning"
```

Then open the local address printed in Terminal, usually [http://localhost:3002](http://localhost:3002). Keep the terminal window open while you use the app. Press **Ctrl+C** in that window to stop it.

You only need to run `npm install` once for this folder. Later, run `npm start` to launch the app.

## Features

| Feature | What it does |
| --- | --- |
| Categories | The app lists only tabs marked `QA` in A1, and displays each category using the exact worksheet name. |
| OneDrive loading | Load `InterviewPrepare.xlsx` from the configured OneDrive folder when the app launches. Both `InterviewPrepare.xlsx` and `Interview Prepare.xlsx` filenames are recognized. |
| QA tabs | Load every workbook tab whose cell A1 contains the `QA` marker. Other tabs are ignored. |
| Manual import | Select another `.xlsx` or `.xls` workbook. It uses the same A1 marker rule and replaces the current Q/A bank. |
| Refresh | Re-read the configured OneDrive workbook so Excel edits and removals appear in the app. |
| Flashcards | Show a question first, reveal its answer when ready, then mark whether you knew it or need more practice. |
| Edit during practice | Edit a OneDrive-loaded question or answer. The app saves the revised cells to the workbook when you choose **I knew it** or **Practice again**. |
| Question range | In a category, choose inclusive **From** and **To** question numbers to practice only that slice. |
| Shuffle | Randomize question order within the selected practice set. |
| Results | See your score and review the questions marked for more practice. |
| Retry | Start a new session containing only questions you marked for more practice. |

## Import questions

For automatic loading, keep the workbook in `~/Library/CloudStorage/OneDrive-Personal/Interview/Interview Preparation` and name it `InterviewPrepare.xlsx` or `Interview Prepare.xlsx`. On launch, the app checks every tab and imports only those whose A1 cell contains `QA` (case-insensitive). The category name in the app matches the worksheet name exactly; rename a marked tab and use **Refresh** to update the category. Put each question in column A and its answer in column B, starting below the A1 marker. Optional `Question` and `Answer` headers are supported.

Use **Refresh** to re-read the OneDrive workbook after editing it. Use **Import Excel** to load another local workbook with the same A1 marker rule. Each successful load replaces the current bank, so additions, edits, and deletions are reflected. Repeated question text across marked tabs is skipped.

## Practice workflow

1. Choose **All** or select a category.
2. For a category, optionally set **From** and **To** to practice an inclusive range (for example, 10 through 20). Leave **Shuffle** enabled to randomize within that range, or turn it off to keep workbook order.
3. Select **Start Practice**.
4. Read the question, choose **Reveal Answer**, and mark **I knew it** or **Practice again**. You can also skip a question.
5. At the end, review missed questions and retry them, restart the session, or return to the categories.

## Data storage

The workbook remains the source of truth. On launch and when you select **Refresh**, the app reads the configured local OneDrive file through its local-only service. During practice, edits to cards loaded from that workbook are saved to their original worksheet row when you choose **I knew it** or **Practice again**. If the row has changed in Excel since it was loaded, the app asks you to refresh instead of overwriting the newer workbook data. Manual imports replace the in-memory bank; their cards cannot be written back to Excel.

## Build for production

To create an optimized production build, run:

```bash
npm run build
```
