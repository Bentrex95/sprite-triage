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

// The key is only needed once, for the session; take it out of the address bar.
const here = new URL(window.location.href);
if (here.searchParams.has("key")) {
  here.searchParams.delete("key");
  history.replaceState(null, "", here.pathname + here.search + here.hash);
}

const token = document.querySelector("meta[name='csrf-token']").getAttribute("content");
const liveSocket = new LiveSocket("/live", Socket, {params: {_csrf_token: token}, hooks: Hooks});
liveSocket.disableDebug();
liveSocket.connect();
