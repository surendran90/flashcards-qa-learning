# FlashCards QA Learning

A question study and practice app that runs on your computer. It loads the Q/A tabs from your OneDrive workbook on launch; you can also import another workbook, study questions and answers, practice by category, and retry questions you missed.

[How it works](#how-it-works) · [Use cases](#use-cases) · [Quick start](#quick-start) · [Features](#features) · [Import questions](#import-questions) · [Data storage](#data-storage) · [Mac app](#mac-app)

<img width="1046" height="652" alt="Screenshot 2026-11-18 at 10 49 15 PM" src="https://github.com/user-attachments/assets/b7500171-dc94-483a-aee9-c339e4a7fd5b" />

## What it does

FlashCards QA Learning turns your interview Q&A workbook into a focused flashcard practice session. Choose one category or the full bank, decide whether to shuffle, and work through questions at your own pace.

## How it works

1. When the app starts, its local service looks for `InterviewPrepare.xlsx` in the configured OneDrive interview folder. It also recognizes the filename `Interview Prepare.xlsx`.
2. The app reads only worksheets whose A1 cell contains `QA`. Each accepted worksheet becomes a category named exactly after its tab.
3. Questions and answers are read from the worksheet rows below the A1 marker. Write each question in column A and its answer in column B, leaving the marker in A1. Repeated question text is skipped so the same question does not appear more than once in the bank.
4. Choose a category and optionally select a question range. Select **Study** to see each question with its answer, or **Start Practice** to reveal answers and mark whether you knew them.
5. The app tracks results for the session and lets you retry the questions you missed. Cards are read-only in the app; it never writes changes to the OneDrive workbook.
6. Use **Refresh** after changing the workbook in Excel to load its latest tabs and content. A manually imported workbook replaces the current in-app bank for that session; its edits are not written back to the configured OneDrive workbook.

## Use cases

- **Prepare for a specific interview topic:** Select a category such as `Resume QA` or `Embedded QA` and practice only the questions you need.
- **Focus on a smaller set:** Set a range such as 10 through 20 to review those questions from the selected category.
- **Review weak areas:** Mark difficult cards **Practice again**, then retry only the missed questions at the end of the session.
- **Study at your own pace:** Open a category in **Study** mode to read each question with its answer and move back and forth through the selected cards.
- **Keep practice aligned with workbook updates:** Add or remove questions, mark a worksheet with `QA` in A1, or rename a tab in Excel, then select **Refresh** in the app.

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
| Study | Show the question and answer together, with Previous and Next navigation through the selected cards. |
| Read-only workbook | The app reads the configured workbook and does not write to it. |
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

## Study workflow

1. Choose **All** or select a category.
2. For a category, optionally choose an inclusive **From** and **To** range.
3. Select **Study** to read each question and answer together. Use **Previous** and **Next** to navigate; select **Back to categories** to leave study mode.

## Data storage

The workbook remains the source of truth. On launch and when you select **Refresh**, the app reads the configured local OneDrive file through its local-only service. Cards cannot be edited in the app, and neither OneDrive-loaded nor manually imported workbook data is written back to any workbook.

## Mac app

A native SwiftUI version lives in [`mac/`](mac/). It reads the same OneDrive workbook directly, so there is no Node server, no Terminal window and no browser.

Build it and install it into `/Applications` (needs Xcode):

```bash
cd mac && ./build-app.sh --install
```

Then open **FlashCards QA** from Launchpad or Spotlight. It has the same features as the web app, plus:

- **⌘R** refreshes the workbook, and **⌘O** imports another one.
- **Settings (⌘,)** changes the workbook folder if your OneDrive path moves.
- In practice mode, **Space** reveals the answer, **K** marks it known, **P** marks it to practice again, **S** skips, and **Esc** ends the session. In study mode, use **←/→**.
- It follows the system light or dark theme.

Notes:

- Only `.xlsx` workbooks are supported. Save older `.xls` files as `.xlsx` first.
- The build is signed ad hoc for your Mac only. It is not notarized for sharing.
- Run the parser tests with `cd mac && swift test`. To work on the code in Xcode, open `mac/Package.swift`.

## Build for production

To create an optimized production build, run:

```bash
npm run build
```
