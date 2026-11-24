enum StudioPhonePage {
    static let html = """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Light Show Studio Remote</title><link rel="stylesheet" href="/remote.css"><script src="/remote.js" defer></script></head>
    <body><main><header><p>Light Show Studio</p><h1 id="name">Phone Remote</h1><p id="notice" role="status"></p></header>
    <section id="controls" hidden><div class="transport"><output id="time">0:00.00</output><span id="mode">Simulation</span></div>
    <div class="buttons"><button id="play" data-action="play">Play</button><button data-action="stop">Stop</button></div>
    <div class="cue"><label for="next">Next cue</label><select id="next"><option value="">Continue cue list</option></select>
    <button id="go" data-action="go">GO</button></div>
    <button id="blackout" data-action="blackout">Blackout</button>
    <h2>Fixtures</h2><ul id="fixtures"></ul></section></main></body></html>
    """

    static let css = """
    :root{color-scheme:dark;font:16px -apple-system,system-ui;background:#0e121a;color:#f5f8fc}
    *{box-sizing:border-box}main{max-width:520px;margin:auto;padding:24px}h1{margin:6px 0 10px;font-size:1.9rem}
    header>p:first-child{color:#77dfef;margin:0;font-weight:650}#notice,li span,#mode{color:#b7c4d3}
    .transport,.buttons,li{display:flex;justify-content:space-between;gap:12px}.transport{padding:13px 0;font-variant-numeric:tabular-nums}
    output{font-size:1.6rem;font-weight:650}button,select{font:inherit;min-height:48px;border-radius:10px;border:1px solid #465568;
    padding:10px 14px;color:inherit;background:#202b39}button:focus-visible,select:focus-visible{outline:2px solid #8eeaff}
    button:disabled{opacity:.55}.buttons button{flex:1}#play,#go{background:#9be8f3;color:#0c2730;font-weight:700}#blackout{width:100%;margin-top:12px;border-color:#db9058}
    .cue{display:grid;grid-template-columns:1fr auto;gap:8px;margin-top:16px}.cue label{grid-column:1/-1}select{width:100%;min-width:0}
    h2{font-size:1.12rem;margin-top:22px}ul{list-style:none;padding:0}li{padding:12px 0;border-bottom:1px solid #293645}li span{text-align:right}
    """

    static let script = #"""
    "use strict";
    const byID = id => document.getElementById(id);
    const notice = byID("notice"), controls = byID("controls"), next = byID("next");
    let token = sessionStorage.getItem("studio.remote") || "", busy = false, sequence = 0, cueList = "";
    async function post(path, payload) {
      const headers = {"Content-Type":"application/json"};
      if (token) headers.Authorization = "Bearer " + token;
      const response = await fetch(path, {method:"POST", headers, body:JSON.stringify(payload), cache:"no-store"});
      const state = await response.json();
      if (!response.ok) {
        if (response.status === 403) {
          token = ""; sessionStorage.removeItem("studio.remote"); controls.hidden = true;
        }
        throw new Error(state.error || "Mac unavailable.");
      }
      return state;
    }
    function update(state) {
      if (state.pending) { notice.textContent = "Approve this phone on the Mac."; return; }
      controls.hidden = false; notice.textContent = ""; byID("name").textContent = state.name;
      const t = Math.round(state.position * 100);
      byID("time").textContent = Math.floor(t/6000) + ":" + (Math.floor(t/100)%60).toString().padStart(2,"0") + "." + (t%100).toString().padStart(2,"0");
      byID("mode").textContent = state.recording ? "Recording" : "Simulation";
      byID("play").dataset.action = state.playing ? "pause" : "play";
      byID("play").textContent = state.playing ? "Pause" : "Play";
      byID("play").disabled = !state.ready || state.recording;
      document.querySelector('[data-action="stop"]').disabled = state.recording;
      byID("go").disabled = state.cues.length === 0;
      byID("blackout").dataset.action = state.blackout ? "restore" : "blackout";
      byID("blackout").textContent = state.blackout ? "Restore Lights" : "Blackout";
      sequence = Math.max(sequence, state.sequence);
      const signature = JSON.stringify(state.cues);
      if (signature !== cueList) {
        cueList = signature;
        next.replaceChildren(new Option("Continue cue list", ""), ...state.cues.map(cue => new Option(cue.name,cue.id)));
      }
      const fixtures = state.fixtures.map(fixture => {
        const row = document.createElement("li"), title = document.createElement("strong"), stateLabel = document.createElement("span");
        title.textContent = fixture.name; stateLabel.textContent = fixture.state; row.append(title, stateLabel);
        return row;
      });
      byID("fixtures").replaceChildren(...fixtures);
    }
    async function poll() {
      if (!token || busy) return;
      busy = true;
      try { update(await post("/state", {})); }
      catch (e) { notice.textContent = e.message; }
      finally { busy = false; }
    }
    controls.addEventListener("click", async event => {
      const button = event.target.closest("button[data-action]");
      if (!button || busy || !token) return;
      const action = button.dataset.action;
      busy = true;
      try {
        const state = await post("/command", {action, sequence:++sequence, ...(action === "go" && next.value ? {cue:next.value} : {})});
        if (action === "go") next.value = "";
        update(state);
      } catch (e) { notice.textContent = e.message; }
      finally { busy = false; }
    });
    async function start() {
      const code = location.hash.slice(1);
      if (code) {
        history.replaceState(null, "", "/");
        token = "";
        sessionStorage.removeItem("studio.remote");
        try {
          const pair = await post("/pair", {code});
          token = pair.token; sessionStorage.setItem("studio.remote", token);
        } catch (e) { notice.textContent = e.message; return; }
      }
      if (!token) { notice.textContent = "Scan the pairing code shown on the Mac."; return; }
      await poll();
      setInterval(poll, 1400);
    }
    start();
    """#
}
