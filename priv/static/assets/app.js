import {Socket} from "/vendor/phoenix/phoenix.mjs";
import {LiveSocket} from "/vendor/live_view/phoenix_live_view.esm.js";

// Copies the support note. Clipboard access needs a user gesture, hence a hook on the button.
const Hooks = {
  // Bring a new triage result into view and move focus to its heading.
  Reveal: {
    mounted() {
      this.el.scrollIntoView({block: "start"});
      const heading = this.el.querySelector("#result-h");
      if (heading) heading.focus({preventScroll: true});
    }
  },
  CopyNote: {
    mounted() {
      this.el.addEventListener("click", () => {
        const text = document.getElementById(this.el.dataset.target).textContent;
        navigator.clipboard.writeText(text).then(
          () => { this.el.textContent = "Copied"; },
          () => { this.el.textContent = "Copy failed, select the text instead"; }
        );
      });
    }
  }
};

// The access key arrives once in the address (?key=…). Keep it in sessionStorage, which
// belongs to this origin and port only (cookies are shared by all ports on localhost),
// take it out of the address bar, and send it when the socket connects.
const KEY = "sprite-triage-key";
const here = new URL(window.location.href);
let key = here.searchParams.get("key") || "";
if (key) {
  try { sessionStorage.setItem(KEY, key); } catch (_e) { /* storage blocked: works until reload */ }
  here.searchParams.delete("key");
  history.replaceState(null, "", here.pathname + here.search + here.hash);
} else {
  try { key = sessionStorage.getItem(KEY) || ""; } catch (_e) { /* storage blocked */ }
}

const token = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: token, key}, hooks: Hooks});
liveSocket.disableDebug();
liveSocket.connect();
