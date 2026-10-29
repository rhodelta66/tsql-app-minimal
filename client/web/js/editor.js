// Monaco for a max field named sql. The editor is vendored. SQL highlighting
// runs on the main thread. Models are disposed on each repaint.

const BASE = "/vendor/monaco/vs";
const live = [];
let generation = 0;
let loading = null;

export function disposeSqlEditors() {
  generation += 1;
  while (live.length) {
    const item = live.pop();
    try {
      item.editor.dispose();
    } catch {
      /* already gone */
    }
    try {
      item.model.dispose();
    } catch {
      /* already gone */
    }
  }
}

function ensureCss() {
  if (document.querySelector("link[data-monaco='1']")) return;
  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = BASE + "/editor/editor.main.css";
  link.dataset.monaco = "1";
  document.head.append(link);
}

function loadMonaco() {
  if (window.monaco && window.monaco.editor) return Promise.resolve(window.monaco);
  if (loading) return loading;
  ensureCss();
  loading = new Promise((resolve, reject) => {
    window.MonacoEnvironment = {
      getWorkerUrl() {
        return BASE + "/base/worker/workerMain.js";
      },
    };
    const script = document.createElement("script");
    script.src = BASE + "/loader.js";
    script.onload = () => {
      const amd = window.require;
      if (typeof amd !== "function") {
        reject(new Error("Monaco loader did not start"));
        return;
      }
      amd.config({ paths: { vs: BASE } });
      amd(["vs/editor/editor.main"], () => {
        const monaco = window.monaco;
        monaco.editor.defineTheme("tsql-paper", {
          base: "vs",
          inherit: true,
          rules: [],
          colors: {
            "editor.background": "#fffdf9",
            "editor.foreground": "#1c1915",
            "editorLineNumber.foreground": "#5c564e",
            "editor.selectionBackground": "#efe4c6",
            "editorCursor.foreground": "#1c1915",
          },
        });
        resolve(monaco);
      });
    };
    script.onerror = () => reject(new Error("Monaco failed to load"));
    document.head.append(script);
  });
  loading.catch(() => {
    loading = null;
  });
  return loading;
}

export function mountSqlEditor(host, value, handlers) {
  const gen = generation;
  const text = value == null ? "" : String(value);
  host.replaceChildren();
  host.addEventListener("keydown", (event) => {
    if ((event.ctrlKey || event.metaKey) && String(event.key || "").toLowerCase() === "s") {
      event.preventDefault();
    }
  }, true);
  loadMonaco().then((monaco) => {
    if (gen !== generation || !host.isConnected) return;
    const model = monaco.editor.createModel(text, "sql");
    const editor = monaco.editor.create(host, {
      model,
      theme: "tsql-paper",
      minimap: { enabled: false },
      fontSize: 13,
      fontFamily: 'ui-monospace, "Cascadia Mono", monospace',
      scrollBeyondLastLine: false,
      wordWrap: "on",
      automaticLayout: true,
      tabSize: 4,
      padding: { top: 8, bottom: 8 },
      overviewRulerLanes: 0,
      hideCursorInOverviewRuler: true,
      scrollbar: { verticalScrollbarSize: 8, horizontalScrollbarSize: 8 },
    });
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => {
      handlers.save();
    });
    editor.onDidChangeModelContent(() => {
      handlers.input(editor.getValue());
    });
    live.push({ editor, model });
  }).catch(() => {
    if (gen !== generation || !host.isConnected) return;
    const area = document.createElement("textarea");
    area.className = "sql-fallback";
    area.value = text;
    area.addEventListener("input", () => handlers.input(area.value));
    host.append(area);
  });
}
