import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import * as XLSX from "xlsx";
import { parseExcelWorkbook } from "./excelImport";

const CATEGORY_ICONS = { "Resume QA": "📄", "Embedded QA": "⚙️" };
const colors = { ink: "#20211f", muted: "#777970", border: "#e6e1d8", card: "#fff", accent: "#4b9479", red: "#d95f59", bg: "#f7f5f0" };

export default function App() {
  const [cards, setCards] = useState([]);
  const [loading, setLoading] = useState(true);
  const [topic, setTopic] = useState("All");
  const [categories, setCategories] = useState([]);
  const [shuffle, setShuffle] = useState(true);
  const [rangeFrom, setRangeFrom] = useState("1");
  const [rangeTo, setRangeTo] = useState("");
  const [mode, setMode] = useState("start");
  const [deck, setDeck] = useState([]);
  const [index, setIndex] = useState(0);
  const [flipped, setFlipped] = useState(false);
  const [results, setResults] = useState({});
  const [status, setStatus] = useState("");
  const inputRef = useRef(null);
  const filtered = useMemo(() => cards.filter(card => topic === "All" || card.topic === topic), [cards, topic]);

  const refreshFromOneDrive = useCallback(async () => {
    setLoading(true);
    setStatus("Loading the latest workbook from OneDrive…");
    try {
      const response = await fetch("/api/qa", { cache: "no-store" });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Could not read the workbook.");
      setCards(data.cards || []);
      setCategories(data.loadedSheets || []);
      setTopic("All");
      setRangeFrom("1"); setRangeTo("");
      setMode("start"); setDeck([]); setIndex(0); setFlipped(false); setResults({});
      const sheets = data.loadedSheets?.length ? ` from ${data.loadedSheets.join(", ")}` : " (no tabs with QA in cell A1 were found)";
      const duplicateNote = data.duplicatesSkipped ? ` ${data.duplicatesSkipped} repeated questions were skipped.` : "";
      setStatus(`Loaded ${data.cards?.length || 0} questions from ${data.fileName}${sheets}.${duplicateNote}`);
    } catch (error) {
      setStatus(`Could not load the OneDrive workbook: ${error.message}`);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { refreshFromOneDrive(); }, [refreshFromOneDrive]);
  const reset = () => { setMode("start"); setDeck([]); setIndex(0); setFlipped(false); setResults({}); };
  const setFilter = value => {
    setTopic(value);
    setRangeFrom("1");
    setRangeTo(String(Math.max(1, cards.filter(card => value === "All" || card.topic === value).length)));
    reset();
  };
  const importExcel = event => {
    const file = event.target.files?.[0];
    if (!file) return;
    setStatus("Reading uploaded workbook…");
    const reader = new FileReader();
    reader.onerror = () => setStatus("Could not read this file. Try saving it as .xlsx and importing it again.");
    reader.onload = e => {
      try {
        const workbook = XLSX.read(e.target.result, { type: "array", cellDates: true });
        const { additions, loadedSheets, duplicatesSkipped } = parseExcelWorkbook(XLSX, workbook);
        if (!loadedSheets.length) {
          const tabs = workbook.SheetNames.length ? workbook.SheetNames.join(", ") : "none";
          setStatus(`No tabs with QA in cell A1 were found. Workbook tabs detected: ${tabs}.`);
        } else {
          setCards(additions.map(card => ({ ...card, sourceFile: "manual" })));
          setCategories(loadedSheets);
          setTopic("All");
          setRangeFrom("1"); setRangeTo("");
          reset();
          const duplicateNote = duplicatesSkipped ? ` ${duplicatesSkipped} repeated questions were skipped.` : "";
          setStatus(`Loaded ${additions.length} questions from ${file.name} (${loadedSheets.join(", ")}).${duplicateNote}`);
        }
      } catch (error) {
        console.error("Excel import failed:", error);
        setStatus("Could not read this workbook. Try saving it as .xlsx and check its file format.");
      }
      window.setTimeout(() => setStatus(""), 8000);
    };
    reader.readAsArrayBuffer(file);
    event.target.value = "";
  };
  const rangeStart = Number(rangeFrom);
  const rangeEnd = rangeTo === "" ? filtered.length : Number(rangeTo);
  const rangeValid = topic === "All" || (
    Number.isInteger(rangeStart) && Number.isInteger(rangeEnd) &&
    rangeStart >= 1 && rangeEnd >= rangeStart && rangeEnd <= filtered.length
  );
  const practiceCount = topic === "All" ? filtered.length : (rangeValid ? rangeEnd - rangeStart + 1 : 0);

  const start = retryWrong => {
    const pool = retryWrong
      ? deck.filter(card => results[card.id] === false)
      : (topic === "All" ? filtered : filtered.slice(rangeStart - 1, rangeEnd));
    if (!pool.length) return;
    setDeck(shuffle ? [...pool].sort(() => Math.random() - 0.5) : [...pool]);
    setIndex(0); setFlipped(false);
    if (!retryWrong) setResults({});
    setMode("running");
  };
  const startStudy = () => {
    const pool = topic === "All" ? filtered : filtered.slice(rangeStart - 1, rangeEnd);
    if (!pool.length || !rangeValid) return;
    setDeck([...pool]);
    setIndex(0);
    setMode("study");
  };
  const answer = correct => {
    const next = { ...results, [deck[index].id]: correct };
    setResults(next);
    if (index + 1 >= deck.length) setMode("done");
    else { setIndex(index + 1); setFlipped(false); }
  };
  const buttonStyle = (background, extra = {}) => ({ border: 0, borderRadius: 10, padding: "11px 18px", color: "white", background, fontWeight: 700, ...extra });

  return <main style={{ maxWidth: 1000, margin: "0 auto", padding: "34px 22px 70px" }}>
    <header style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 16, flexWrap: "wrap", marginBottom: 26 }}>
      <div><div style={{ color: colors.muted, fontSize: 11, letterSpacing: 2, textTransform: "uppercase", marginBottom: 5 }}>Study and practice</div><h1 style={{ margin: 0, fontSize: 30 }}>💬 FlashCard Q/A Bank</h1><p style={{ color: colors.muted, margin: "7px 0 0", fontSize: 14 }}>Study questions and answers, or practice with flashcards.</p></div>
      <div style={{ display: "flex", alignItems: "center", gap: 9, flexWrap: "wrap" }}>
        <span style={{ color: colors.muted, fontSize: 13 }}>{loading ? "Loading workbook…" : `${cards.length} questions loaded`}</span>
        <button onClick={() => inputRef.current?.click()} style={{ ...buttonStyle(colors.ink), background: "#fff", color: colors.ink, border: `1px solid ${colors.border}` }}>📂 Import Excel</button>
        <button onClick={refreshFromOneDrive} disabled={loading} style={{ ...buttonStyle(colors.ink), background: "#fff", color: colors.ink, border: `1px solid ${colors.border}`, opacity: loading ? .55 : 1 }}>↻ {loading ? "Refreshing…" : "Refresh"}</button>
        <input ref={inputRef} type="file" accept=".xlsx,.xls" onChange={importExcel} hidden />
      </div>
    </header>

    <nav aria-label="Question categories" style={{ display: "flex", gap: 7, flexWrap: "wrap", marginBottom: 20 }}>
      {["All", ...categories].map(item => {
        const count = item === "All" ? cards.length : cards.filter(card => card.topic === item).length;
        const active = topic === item;
        return <button key={item} onClick={() => setFilter(item)} style={{ border: `1px solid ${active ? colors.accent : colors.border}`, borderRadius: 22, padding: "7px 13px", background: active ? colors.accent : "white", color: active ? "white" : colors.muted, fontSize: 12, fontWeight: 650 }}>{item}{item !== "All" && ` · ${count}`}</button>;
      })}
    </nav>
    {status && <div role="status" style={{ padding: "10px 14px", background: status.startsWith("Could not") || status.startsWith("No tabs") ? "#fff0ef" : "#e9f5ef", borderRadius: 10, color: status.startsWith("Could not") || status.startsWith("No tabs") ? colors.red : colors.accent, marginBottom: 16, fontSize: 13 }}>{status}</div>}

    {mode === "start" && <>
      {topic === "All" && <section style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(165px, 1fr))", gap: 12, marginBottom: 18 }}>
        {categories.map(item => <button key={item} onClick={() => setFilter(item)} style={{ textAlign: "left", background: "white", border: `1px solid ${colors.border}`, borderRadius: 14, padding: "16px 17px", color: colors.ink }}><div style={{ fontSize: 24 }}>{CATEGORY_ICONS[item] || "📚"}</div><div style={{ fontSize: 13, fontWeight: 700, margin: "9px 0 5px" }}>{item}</div><div style={{ fontSize: 21, color: colors.accent, fontWeight: 800 }}>{cards.filter(card => card.topic === item).length}</div><div style={{ fontSize: 11, color: colors.muted }}>questions</div></button>)}
      </section>}
      <section style={{ background: "white", border: `1px solid ${colors.border}`, borderRadius: 16, padding: "24px", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 18, flexWrap: "wrap" }}>
        <div><strong style={{ fontSize: 17 }}>{topic === "All" ? "All Categories" : topic}</strong><div style={{ color: colors.muted, marginTop: 7 }}><b style={{ color: colors.accent }}>{topic === "All" ? filtered.length : practiceCount}</b> questions ready{topic !== "All" && ` · ${filtered.length} available`}</div></div>
        <div style={{ display: "flex", alignItems: "center", gap: 14, flexWrap: "wrap" }}>
          {topic !== "All" && <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
            <span style={{ color: colors.muted, fontSize: 12, fontWeight: 650 }}>Question range</span>
            <label style={{ display: "flex", alignItems: "center", gap: 5, color: colors.muted, fontSize: 12 }}>From
              <input aria-label="From question number" type="number" min="1" max={filtered.length || 1} step="1" value={rangeFrom} onChange={e => setRangeFrom(e.target.value)} style={{ width: 66, border: `1px solid ${colors.border}`, borderRadius: 8, padding: "7px 8px", color: colors.ink, background: "#fff" }} />
            </label>
            <label style={{ display: "flex", alignItems: "center", gap: 5, color: colors.muted, fontSize: 12 }}>To
              <input aria-label="To question number" type="number" min="1" max={filtered.length || 1} step="1" value={rangeTo || filtered.length || 1} onChange={e => setRangeTo(e.target.value)} style={{ width: 66, border: `1px solid ${colors.border}`, borderRadius: 8, padding: "7px 8px", color: colors.ink, background: "#fff" }} />
            </label>
            <span style={{ fontSize: 11, color: rangeValid ? colors.muted : colors.red }}>{rangeValid ? "Inclusive" : `Enter 1–${filtered.length}, with From ≤ To`}</span>
          </div>}
          <label style={{ color: colors.muted, fontSize: 13 }}><input type="checkbox" checked={shuffle} onChange={e => setShuffle(e.target.checked)} /> 🔀 Shuffle</label>
          <button disabled={loading || !filtered.length || !rangeValid} onClick={startStudy} style={{ ...buttonStyle(colors.ink), opacity: !loading && filtered.length && rangeValid ? 1 : .45 }}>📖 Study</button>
          <button disabled={loading || !filtered.length || !rangeValid} onClick={() => start(false)} style={{ ...buttonStyle(colors.accent), opacity: !loading && filtered.length && rangeValid ? 1 : .45 }}>▶ Start Practice</button>
        </div>
      </section>
      {!cards.length && !loading && <p style={{ textAlign: "center", color: colors.muted, marginTop: 24, fontSize: 14 }}>The app loads the configured OneDrive workbook on launch. It imports tabs whose cell A1 contains “QA”; use Refresh after editing that workbook.</p>}
    </>}

    {mode === "study" && deck[index] && <section style={{ maxWidth: 720, margin: "0 auto" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10, color: colors.muted, fontSize: 13 }}><span>Card {index + 1} / {deck.length}</span><button onClick={reset} style={{ border: 0, background: "none", color: colors.muted }}>Back to categories</button></div>
      <div style={{ height: 6, borderRadius: 9, background: colors.border, marginBottom: 18 }}><div style={{ height: "100%", width: `${(index + 1) / deck.length * 100}%`, borderRadius: 9, background: colors.accent, transition: "width .2s" }} /></div>
      <article style={{ minHeight: 235, background: "white", border: `1px solid ${colors.border}`, borderRadius: 18, padding: "30px", boxShadow: "0 8px 28px #24251a0b" }}>
        <span style={{ display: "inline-block", color: colors.accent, background: "#e9f5ef", borderRadius: 20, padding: "5px 11px", fontSize: 11, fontWeight: 700, marginBottom: 18 }}>{deck[index].topic}</span>
        <div style={{ fontSize: 19, lineHeight: 1.6, fontWeight: 700 }}>{deck[index].question}</div>
        <div style={{ borderTop: `1px dashed ${colors.border}`, marginTop: 22, paddingTop: 19 }}><div style={{ color: colors.muted, fontSize: 11, fontWeight: 700, letterSpacing: 1, marginBottom: 8 }}>ANSWER</div><div style={{ lineHeight: 1.75, whiteSpace: "pre-wrap" }}>{deck[index].answer || <i style={{ color: colors.muted }}>No answer provided.</i>}</div></div>
      </article>
      <div style={{ display: "flex", justifyContent: "space-between", gap: 10, marginTop: 17 }}><button disabled={index === 0} onClick={() => setIndex(i => Math.max(0, i - 1))} style={{ ...buttonStyle(colors.ink), opacity: index === 0 ? .45 : 1 }}>← Previous</button><button disabled={index === deck.length - 1} onClick={() => setIndex(i => Math.min(deck.length - 1, i + 1))} style={{ ...buttonStyle(colors.accent), opacity: index === deck.length - 1 ? .45 : 1 }}>Next →</button></div>
    </section>}

    {mode === "running" && deck[index] && <section style={{ maxWidth: 720, margin: "0 auto" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10, color: colors.muted, fontSize: 13 }}><span>Question {index + 1} / {deck.length}</span><span>✅ {Object.values(results).filter(Boolean).length}　❌ {Object.values(results).filter(v => v === false).length}</span><button onClick={reset} style={{ border: 0, background: "none", color: colors.muted }}>End practice</button></div>
      <div style={{ height: 6, borderRadius: 9, background: colors.border, marginBottom: 18 }}><div style={{ height: "100%", width: `${index / deck.length * 100}%`, borderRadius: 9, background: colors.accent, transition: "width .2s" }} /></div>
      <article style={{ minHeight: 235, background: "white", border: `1px solid ${colors.border}`, borderRadius: 18, padding: "30px", textAlign: "center", boxShadow: "0 8px 28px #24251a0b" }}>
        <span style={{ display: "inline-block", color: colors.accent, background: "#e9f5ef", borderRadius: 20, padding: "5px 11px", fontSize: 11, fontWeight: 700, marginBottom: 18 }}>{deck[index].topic}</span>
        <div style={{ fontSize: 19, lineHeight: 1.6, fontWeight: 700 }}>{deck[index].question}</div>
        {flipped && <div style={{ borderTop: `1px dashed ${colors.border}`, marginTop: 22, paddingTop: 19, textAlign: "left" }}><div style={{ color: colors.muted, fontSize: 11, fontWeight: 700, letterSpacing: 1, marginBottom: 8 }}>ANSWER</div><div style={{ lineHeight: 1.75, whiteSpace: "pre-wrap" }}>{deck[index].answer || <i style={{ color: colors.muted }}>No answer provided.</i>}</div></div>}
      </article>
      <div style={{ display: "flex", justifyContent: "center", gap: 10, marginTop: 17, flexWrap: "wrap" }}>{!flipped ? <button onClick={() => setFlipped(true)} style={buttonStyle(colors.accent, { padding: "12px 24px" })}>👁 Reveal Answer</button> : <><button onClick={() => answer(true)} style={buttonStyle(colors.accent)}>✅ I knew it</button><button onClick={() => answer(false)} style={buttonStyle(colors.red)}>❌ Practice again</button></>}</div>
      {!flipped && <div style={{ textAlign: "center", marginTop: 12 }}><button onClick={() => index + 1 >= deck.length ? setMode("done") : setIndex(index + 1)} style={{ border: 0, background: "none", color: colors.muted, textDecoration: "underline" }}>Skip</button></div>}
    </section>}

    {mode === "done" && (() => {
      const correct = Object.values(results).filter(Boolean).length;
      const wrong = deck.filter(card => results[card.id] === false);
      const score = Math.round(correct / (deck.length || 1) * 100);
      return <section style={{ maxWidth: 700, margin: "0 auto" }}><div style={{ textAlign: "center", background: "white", border: `1px solid ${colors.border}`, borderRadius: 18, padding: 30, marginBottom: 18 }}><div style={{ fontSize: 40 }}>{score >= 80 ? "🏆" : score >= 60 ? "💪" : "📚"}</div><div style={{ fontSize: 34, color: colors.accent, fontWeight: 800 }}>{score}%</div><p style={{ color: colors.muted }}>{correct} knew · {wrong.length} to practice · {deck.length} total</p><div style={{ display: "flex", justifyContent: "center", gap: 9, flexWrap: "wrap" }}>{wrong.length > 0 && <button onClick={() => start(true)} style={buttonStyle(colors.red)}>🔁 Retry missed ({wrong.length})</button>}<button onClick={() => start(false)} style={buttonStyle(colors.accent)}>↻ Restart</button><button onClick={reset} style={{ ...buttonStyle(colors.ink), background: "#f1efe9", color: colors.muted }}>Back to categories</button></div></div>{wrong.map(card => <article key={card.id} style={{ background: "white", border: `1px solid ${colors.border}`, borderRadius: 12, padding: 15, marginBottom: 9 }}><small style={{ color: colors.red, fontWeight: 700 }}>{card.topic}</small><div style={{ fontWeight: 700, margin: "7px 0" }}>{card.question}</div><div style={{ color: colors.muted, whiteSpace: "pre-wrap", lineHeight: 1.6 }}>{card.answer || "No answer provided."}</div></article>)}</section>;
    })()}
  </main>;
}
