import { useMemo, useRef, useState } from "react";
import * as XLSX from "xlsx";

const STORAGE_KEY = "qa_bank_standalone_v1";
const TOPICS = ["Resume Q A", "Embedded Q A", "General Interview QA", "C (100-200)", "C Programs", "C++ (Top 100)", "C++ Programs", "Networking & Protocols"];
const TOPIC_ICONS = ["📄", "⚙️", "💬", "💻", "🖥️", "🔷", "🔹", "🌐"];
const SHEET_TOPIC_MAP = {
  "Resume Q A": "Resume Q A", "Embedded Q A (100-200)": "Embedded Q A",
  "General Interview QA (Top 100)": "General Interview QA", "C(100- 200)": "C (100-200)",
  "C Programs(Top 20)": "C Programs", "C++(Top 100)": "C++ (Top 100)",
  "C++ Programs(Top 20)": "C++ Programs", "Networking & Protocols": "Networking & Protocols",
  "HR Question": null,
};
const readCards = () => {
  try { const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "[]"); return Array.isArray(saved) ? saved : []; }
  catch { return []; }
};
const colors = { ink: "#20211f", muted: "#777970", border: "#e6e1d8", card: "#fff", accent: "#4b9479", red: "#d95f59", bg: "#f7f5f0" };

export default function App() {
  const [cards, setCards] = useState(readCards);
  const [topic, setTopic] = useState("All");
  const [shuffle, setShuffle] = useState(true);
  const [mode, setMode] = useState("start");
  const [deck, setDeck] = useState([]);
  const [index, setIndex] = useState(0);
  const [flipped, setFlipped] = useState(false);
  const [results, setResults] = useState({});
  const [status, setStatus] = useState("");
  const inputRef = useRef(null);
  const filtered = useMemo(() => cards.filter(card => topic === "All" || card.topic === topic), [cards, topic]);

  const storeCards = next => { setCards(next); localStorage.setItem(STORAGE_KEY, JSON.stringify(next)); };
  const reset = () => { setMode("start"); setDeck([]); setIndex(0); setFlipped(false); setResults({}); };
  const setFilter = value => { setTopic(value); reset(); };
  const importExcel = event => {
    const file = event.target.files?.[0];
    if (!file) return;
    setStatus("Reading workbook…");
    const reader = new FileReader();
    reader.onload = e => {
      try {
        const workbook = XLSX.read(e.target.result, { type: "array" });
        const existing = new Set(cards.map(card => card.question.trim().toLowerCase()));
        const additions = [];
        workbook.SheetNames.forEach(sheetName => {
          if (/effort/i.test(sheetName)) return;
          const mapped = SHEET_TOPIC_MAP[sheetName];
          if (mapped === null) return;
          const category = mapped || sheetName;
          const rows = XLSX.utils.sheet_to_json(workbook.Sheets[sheetName], { header: 1, defval: "" });
          rows.forEach(row => {
            const question = String(row[0] || "").trim();
            const answer = String(row[1] || "").trim();
            const key = question.toLowerCase();
            if (question.length > 4 && !/^question$/i.test(question) && !existing.has(key)) {
              additions.push({ id: `${Date.now()}-${Math.random()}`, topic: category, question, answer });
              existing.add(key);
            }
          });
        });
        storeCards([...cards, ...additions]);
        setStatus(`Imported ${additions.length} question${additions.length === 1 ? "" : "s"}.`);
      } catch { setStatus("Could not read this workbook. Check that it has questions in column A and answers in column B."); }
      window.setTimeout(() => setStatus(""), 5000);
    };
    reader.readAsArrayBuffer(file);
    event.target.value = "";
  };
  const start = retryWrong => {
    const pool = retryWrong ? deck.filter(card => results[card.id] === false) : filtered;
    if (!pool.length) return;
    setDeck(shuffle ? [...pool].sort(() => Math.random() - 0.5) : [...pool]);
    setIndex(0); setFlipped(false);
    if (!retryWrong) setResults({});
    setMode("running");
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
      <div><div style={{ color: colors.muted, fontSize: 11, letterSpacing: 2, textTransform: "uppercase", marginBottom: 5 }}>Focused practice</div><h1 style={{ margin: 0, fontSize: 30 }}>💬 Q/A Bank</h1><p style={{ color: colors.muted, margin: "7px 0 0", fontSize: 14 }}>Review questions, reveal answers, and track what needs practice.</p></div>
      <div style={{ display: "flex", alignItems: "center", gap: 9, flexWrap: "wrap" }}>
        <span style={{ color: colors.muted, fontSize: 13 }}>{cards.length} questions saved</span>
        <button onClick={() => inputRef.current?.click()} style={{ ...buttonStyle(colors.ink), background: "#fff", color: colors.ink, border: `1px solid ${colors.border}` }}>📂 Import Excel</button>
        <input ref={inputRef} type="file" accept=".xlsx,.xls" onChange={importExcel} hidden />
      </div>
    </header>

    <nav aria-label="Question categories" style={{ display: "flex", gap: 7, flexWrap: "wrap", marginBottom: 20 }}>
      {["All", ...new Set([...TOPICS, ...cards.map(card => card.topic).filter(t => !TOPICS.includes(t))])].map(item => {
        const count = item === "All" ? cards.length : cards.filter(card => card.topic === item).length;
        const active = topic === item;
        return <button key={item} onClick={() => setFilter(item)} style={{ border: `1px solid ${active ? colors.accent : colors.border}`, borderRadius: 22, padding: "7px 13px", background: active ? colors.accent : "white", color: active ? "white" : colors.muted, fontSize: 12, fontWeight: 650 }}>{item}{item !== "All" && ` · ${count}`}</button>;
      })}
    </nav>
    {status && <div role="status" style={{ padding: "10px 14px", background: "#e9f5ef", borderRadius: 10, color: colors.accent, marginBottom: 16, fontSize: 13 }}>{status}</div>}

    {mode === "start" && <>
      {topic === "All" && <section style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(165px, 1fr))", gap: 12, marginBottom: 18 }}>
        {TOPICS.map((item, i) => <button key={item} onClick={() => setFilter(item)} style={{ textAlign: "left", background: "white", border: `1px solid ${colors.border}`, borderRadius: 14, padding: "16px 17px", color: colors.ink }}><div style={{ fontSize: 24 }}>{TOPIC_ICONS[i]}</div><div style={{ fontSize: 13, fontWeight: 700, margin: "9px 0 5px" }}>{item}</div><div style={{ fontSize: 21, color: colors.accent, fontWeight: 800 }}>{cards.filter(card => card.topic === item).length}</div><div style={{ fontSize: 11, color: colors.muted }}>questions</div></button>)}
      </section>}
      <section style={{ background: "white", border: `1px solid ${colors.border}`, borderRadius: 16, padding: "24px", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 18, flexWrap: "wrap" }}>
        <div><strong style={{ fontSize: 17 }}>{topic === "All" ? "All Categories" : topic}</strong><div style={{ color: colors.muted, marginTop: 7 }}><b style={{ color: colors.accent }}>{filtered.length}</b> questions ready</div></div>
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}><label style={{ color: colors.muted, fontSize: 13 }}><input type="checkbox" checked={shuffle} onChange={e => setShuffle(e.target.checked)} /> 🔀 Shuffle</label><button disabled={!filtered.length} onClick={() => start(false)} style={{ ...buttonStyle(colors.accent), opacity: filtered.length ? 1 : .45 }}>▶ Start Practice</button></div>
      </section>
      {!cards.length && <p style={{ textAlign: "center", color: colors.muted, marginTop: 24, fontSize: 14 }}>Import an Excel workbook to add questions. Put each question in column A and its answer in column B; sheet names become categories.</p>}
    </>}

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
