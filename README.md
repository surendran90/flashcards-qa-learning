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
5. The app tracks results for the session and lets you retry the questions you missed. Cards are read-only in the web app; it never writes changes to the OneDrive workbook. (The Mac app can edit questions; see [Editing questions](#editing-questions).)
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
| Read-only workbook | The web app reads the configured workbook and does not write to it. The Mac app can edit it. |
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
4. Read the question, choose **Reveal Answer**, and mark **I knew it** or **Practice again** (in the Mac app: rate **Again / Hard / Good / Easy**). You can also skip a question.
5. At the end, review missed questions and retry them, restart the session, or return to the categories.

## Study workflow

1. Choose **All** or select a category.
2. For a category, optionally choose an inclusive **From** and **To** range.
3. Select **Study** to read each question and answer together. Use **Previous** and **Next** to navigate; select **Back to categories** to leave study mode.

## Data storage

The workbook remains the source of truth. On launch and when you select **Refresh**, the app reads the configured local OneDrive file through its local-only service. Cards cannot be edited in the web app, and neither OneDrive-loaded nor manually imported workbook data is written back to any workbook.

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

### Card timer

Each card in Study and Practice mode has a timer in its top-right corner. It's ready at **5 minutes for Q&A cards** and **20 minutes for C Programs** (any category with "program" in its name). You can change the time for each category in **Settings (⌘,)**.

- Select ▶ (or press **⌥Space**) to start it and ⏸ to pause it. Moving to another card stops the timer, and the next card's timer is ready but not started.
- When the time runs out, a sound plays and the timer turns red and counts overtime (for example `+1:20`). Move on when you're ready.
- Time counts as **Studying** in Study mode and **Revising** in Practice, and it is recorded per category and per card. Time while the Mac is asleep isn't counted.
- After 50 minutes of timed work without a 5-minute pause, the app suggests a 10-minute break.
- Time is kept after Refresh, Import Excel and quitting. If you quit mid-card, that card's timer continues from the same point when you open it again that day.

### Study plan

Open it with **🗓 Study Plan** or **⌘L**. The plan doesn't use a target date. It sizes each day to the study sessions you set and estimates when you'll finish.

| Session | Default time | Focus |
|---|---|---|
| 🌅 Morning | 9:30–12:00 | Learn new cards: read them, then **Test yourself** |
| 💼 Job search | 12:00–14:30 | Applications and lunch (not counted as study) |
| ☀️ Afternoon | 14:30–16:30 | Review due cards |
| 🌙 Evening | 19:30–20:30 | Review due cards the afternoon didn't fit |

You can change times, turn sessions on or off, and set each session's focus in **Settings › Daily sessions**.

- **Targets:** each session gets a target when the day starts, for example "Learn 8 new: C Programs ×2, C QA ×6 · ~70 min". A new card costs its time box. A review costs a fifth of that (1 minute for Q&A, 4 for C programs). Once a category has 10 timed cards, the plan uses your real average time instead. New cards rotate across categories, so C programs don't all pile up at the end.
- **Missed work carries over:** when a session ends with work left, the rest moves to the next session (or to tomorrow's first session) and is marked "↪ carried". **Busy today (interview / applications)** moves everything left today to tomorrow.
- **Finish estimate:** **All cards learned by** and **Mastered (3-week memory) by** dates, worked out from your sessions. If you fall behind, the page shows how many days later the date is than it was this morning.
- **Progress:** overall Learned and Mastered bars, and a New / Learning / Mastered bar for each category.
- **Next 14 days:** new and review counts for each session, estimated time, and carried work.
- **Reminders:** a notification arrives 10 minutes before each session (you can change this in Settings), for example "☀️ Afternoon session at 14:30 — revise 14 (C QA 8, Resume QA 6)". Allow notifications for FlashCardsQA when macOS asks, or later in System Settings › Notifications.
- **Study time:** totals for today, the last 7 days and all time, a 14-day chart, the average time per card by category, and your slowest cards.

### Memory algorithm (FSRS) and ratings

In the Mac app, the plan schedules reviews with **FSRS-5** (Free Spaced Repetition Scheduler), which Anki has used by default since 2023. FSRS tracks each card's **stability** (how long the memory lasts), its **difficulty**, and your **chance of recalling it today**. It schedules the next review for when that chance falls to your target recall (90% by default, adjustable from 80% to 97% in **Settings › Memory**). Easy cards wait longer and hard cards come back sooner. In public benchmarks it predicts recall better than SM-2 (the older Anki/SuperMemo algorithm) and needs fewer reviews for the same recall.

After **Reveal Answer** in Practice, rate how well you recalled the card. Each button shows when you'll see the card next:

| Button | Key | Meaning |
|---|---|---|
| ❌ Again | 1 | Forgot. Comes back tomorrow and counts as missed for **Retry missed**. |
| 😬 Hard | 2 | Recalled with effort. A shorter gap; listed as "shaky" on the results screen. |
| ✅ Good | 3 | Recalled. (**K** still works.) |
| ⭐ Easy | 4 | Instant recall. A much longer gap. |

On a first review, the gaps are about 1, 1, 3 and 16 days. A card counts as **Mastered** once FSRS expects you to still recall it three weeks later. It counts as **Weak** after 2 or more lapses, or once FSRS rates it as very difficult; the category progress shows how many weak cards each category has. FSRS already brings weak cards back sooner, so the plan has no separate weak-card practice. Reviews saved before FSRS are converted automatically, and their due dates stay the same.

**What updates the schedule:** only answers to **new** cards, cards that are **due**, or cards already reviewed **today** (such as **Retry missed** and **Quick recall**) change a card's schedule. If you practise a card that isn't due yet, for example from a category on the start screen, it's **practice only**: the time still counts as revising, but its due date doesn't change, and the card says so after you reveal the answer. A new card counts toward a session only after you rate it in **Test yourself**; reading it in Study mode isn't enough.

For C Programs, Practice reminds you to write the code yourself before revealing the answer, because producing an answer from memory helps it stick. The plan page has a short explanation and job-hunt tips under "Why this plan works".

Progress is saved in `~/Library/Application Support/FlashCardsQA/progress.json`, separate from your workbook. Cards are matched by their question text, so their history survives Refresh, Import, reordered rows and renamed tabs. If you edit a question's text in the app, its history moves with it.

### Already studied

In Study mode, cards you haven't practised yet have a **✓ Already studied** button (key **A**). Use it for cards you already know from before. The card counts as done for today's session, gets an FSRS **Easy** first review (it comes back in about 16 days), and is left out of the **Test yourself** round.

### Editing questions

Select a category on the main page. Below **Study / Start Practice**, a **Questions (N)** section lists that category's questions. It is collapsed by default; select it to expand it.

- **Reorder:** drag a question by its ≡ handle onto another position. The rows move in Excel, including any extra columns such as an ID.
- **View and edit:** select a question to see its answer, then **✏️ Edit**. Changes save automatically about 1.5 seconds after you stop typing, and when you select **Done**.
- **Add:** **＋ Add question** adds a new row at the end of that category's sheet.
- **Delete:** **🗑 Delete** asks for confirmation, then removes the row and moves the rows below it up.

Changes are written straight to the workbook the questions came from: the OneDrive file, or a workbook you imported. The study plan updates straight away: new questions become new cards, deleted ones drop out, and edited ones keep their review history. Duplicate questions aren't allowed.

**Safety:**
- **Backups:** before saving, the app copies the workbook to `~/Library/Application Support/FlashCardsQA/backups/` (at most one copy every 5 minutes; the last 30 are kept).
- **Workbook open in Excel:** the app doesn't save while the workbook is open in Excel. It shows a message and saves automatically once you close the file there.
- **What changes:** only the edited sheet's question and answer cells change. Edited cells are saved as plain text; other sheets and formatting are kept.
- **File type:** only `.xlsx` files can be edited.

C Programs questions and answers are shown in a code font everywhere in the Mac app.

Notes:

- Only `.xlsx` workbooks are supported. Save older `.xls` files as `.xlsx` first.
- The build is signed ad hoc for your Mac only. It is not notarized for sharing.
- Run the parser tests with `cd mac && swift test`. To work on the code in Xcode, open `mac/Package.swift`.

## Build for production

To create an optimized production build, run:

```bash
npm run build
```
