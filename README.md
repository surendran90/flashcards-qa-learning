# Q/A Bank

Standalone question practice app. It includes category filters, Excel import, shuffled flashcard practice, scoring, and retrying missed questions. Cards are saved in this browser under a separate storage key from the Study Plan app.

## Run

From this directory:

```bash
npm install
npm start
```

To build for deployment:

```bash
npm run build
```

Import an `.xlsx` or `.xls` workbook using **Import Excel**. Each sheet name becomes a category. Put each question in column A and its answer in column B. The known workbook sheet names are mapped to the categories shown in the app; other sheets are imported under their own names. Questions with matching text are skipped.
