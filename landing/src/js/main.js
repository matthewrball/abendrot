/* ============================================================================
   Abendrot landing — interaction layer
   - scroll-driven page warming (the page embodies the product)
   - interactive cool<->warm demo slider (pointer + keyboard, a11y)
   - reveal-true-color hold interaction
   - nav scroll state + intersection-observer scroll reveals
   All motion respects prefers-reduced-motion / prefers-reduced-transparency.
   ============================================================================ */

const prefersReducedMotion = window.matchMedia(
  "(prefers-reduced-motion: reduce)"
).matches;

/* ---------------------------------------------------------------------------
   1. Scroll-driven warming
   The fixed .warmfield reads a --warm (0..1) custom property. As the reader
   descends, warmth ramps from twilight toward ember — embodying the promise.
--------------------------------------------------------------------------- */
function initScrollWarming() {
  const field = document.querySelector(".warmfield");
  if (!field) return;

  let ticking = false;
  const update = () => {
    const max = document.documentElement.scrollHeight - window.innerHeight;
    const progress = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
    // ease the curve so the first viewport stays cool/cinematic, then warms.
    const warm = Math.pow(progress, 0.85);
    field.style.setProperty("--warm", warm.toFixed(4));
    ticking = false;
  };

  const onScroll = () => {
    if (!ticking) {
      window.requestAnimationFrame(update);
      ticking = true;
    }
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll, { passive: true });
  update();
}

/* ---------------------------------------------------------------------------
   2. Nav scrolled state
--------------------------------------------------------------------------- */
function initNav() {
  const nav = document.querySelector(".nav");
  if (!nav) return;
  const onScroll = () => nav.classList.toggle("scrolled", window.scrollY > 40);
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();
}

/* ---------------------------------------------------------------------------
   3. Interactive cool<->warm demo
   Dragging (or arrow keys on the focusable window) moves the split. Left of the
   split is "warmed" (multiply veil + glow); right stays true/cool. The popover
   slider knob and Kelvin readout track the split.
--------------------------------------------------------------------------- */
function initDemo() {
  const win = document.querySelector(".demo-window");
  if (!win) return;

  const state = document.querySelector(".demo-state-k");
  const live = document.getElementById("demo-live");
  // map split (0..100, % warmed) -> a plausible Kelvin readout (neutral->warm)
  const NEUTRAL_K = 6500;
  const WARM_K = 2700;

  let split = 62; // start mostly-warm so the "aha" is visible immediately

  const kelvinFor = (pct) =>
    Math.round(NEUTRAL_K - (pct / 100) * (NEUTRAL_K - WARM_K));

  // Debounce the spoken update so dragging/holding an arrow key doesn't flood
  // the live region; screen readers announce only once the value settles.
  let liveTimer = 0;
  const announce = () => {
    if (!live) return;
    clearTimeout(liveTimer);
    liveTimer = window.setTimeout(() => {
      const pct = Math.round(split);
      const k = kelvinFor(split).toLocaleString("en-US");
      live.textContent =
        pct === 0
          ? "True color — no warmth. About 6,500 Kelvin, the cool reference."
          : pct === 100
          ? "Fully warmed — about 2,700 Kelvin, deep candlelight."
          : pct + "% warmed — about " + k + " Kelvin.";
    }, 280);
  };

  const apply = () => {
    win.style.setProperty("--split", split + "%");
    const pct = Math.round(split);
    const k = kelvinFor(split);
    // keep the slider's accessible value + description in sync (drag + keys)
    win.setAttribute("aria-valuenow", pct);
    win.setAttribute(
      "aria-valuetext",
      pct + "% warmed — about " + k.toLocaleString("en-US") + " Kelvin"
    );
    if (state) {
      state.textContent = k.toLocaleString("en-US") + "K";
    }
  };

  const setFromClientX = (clientX) => {
    const rect = win.getBoundingClientRect();
    const pct = ((clientX - rect.left) / rect.width) * 100;
    split = Math.min(100, Math.max(0, pct));
    apply();
    announce();
  };

  let dragging = false;
  win.addEventListener("pointerdown", (e) => {
    if (win.classList.contains("revealing")) return;
    dragging = true;
    win.setPointerCapture(e.pointerId);
    setFromClientX(e.clientX);
  });
  win.addEventListener("pointermove", (e) => {
    if (dragging) setFromClientX(e.clientX);
  });
  const endDrag = (e) => {
    if (dragging) {
      dragging = false;
      try { win.releasePointerCapture(e.pointerId); } catch (_) {}
    }
  };
  win.addEventListener("pointerup", endDrag);
  win.addEventListener("pointercancel", endDrag);

  // keyboard a11y on the focusable demo window
  win.addEventListener("keydown", (e) => {
    const step = e.shiftKey ? 10 : 4;
    let handled = true;
    if (e.key === "ArrowLeft" || e.key === "ArrowDown") {
      split = Math.max(0, split - step);
    } else if (e.key === "ArrowRight" || e.key === "ArrowUp") {
      split = Math.min(100, split + step);
    } else if (e.key === "Home") {
      split = 0;
    } else if (e.key === "End") {
      split = 100;
    } else {
      handled = false;
    }
    if (handled) {
      apply();
      announce();
      e.preventDefault();
    }
  });

  apply();

  // --- Reveal True Color: hold to lift the veil ---------------------------
  const btn = document.querySelector(".demo-reveal-btn");
  if (btn) {
    const sayReveal = (msg) => {
      if (!live) return;
      clearTimeout(liveTimer);
      live.textContent = msg;
    };
    const begin = () => {
      if (win.classList.contains("revealing")) return;
      win.classList.add("revealing");
      btn.classList.add("revealing");
      btn.setAttribute("aria-pressed", "true");
      sayReveal("Revealing true color — warmth lifted across the demo. Release to ease the warmth back.");
    };
    const end = () => {
      if (!win.classList.contains("revealing")) return;
      win.classList.remove("revealing");
      btn.classList.remove("revealing");
      btn.setAttribute("aria-pressed", "false");
      sayReveal("Warmth restored — back to " + Math.round(split) + "% warmed.");
    };
    btn.addEventListener("pointerdown", (e) => { e.preventDefault(); begin(); });
    window.addEventListener("pointerup", end);
    btn.addEventListener("pointercancel", end);
    // keyboard: Space/Enter hold semantics (keydown begins, keyup ends)
    btn.addEventListener("keydown", (e) => {
      if (e.key === " " || e.key === "Enter") { e.preventDefault(); begin(); }
    });
    btn.addEventListener("keyup", (e) => {
      if (e.key === " " || e.key === "Enter") { e.preventDefault(); end(); }
    });
    btn.addEventListener("blur", end);
  }
}

/* ---------------------------------------------------------------------------
   4. Specular tracking on glass surfaces (cursor-aware glint, §21.3)
--------------------------------------------------------------------------- */
function initSpecular() {
  if (prefersReducedMotion) return;
  const cards = document.querySelectorAll(".glass");
  cards.forEach((card) => {
    if (!card.querySelector(".spec")) {
      const spec = document.createElement("span");
      spec.className = "spec";
      card.prepend(spec);
    }
    card.addEventListener("pointermove", (e) => {
      const rect = card.getBoundingClientRect();
      const mx = ((e.clientX - rect.left) / rect.width) * 100;
      const my = ((e.clientY - rect.top) / rect.height) * 100;
      card.style.setProperty("--mx", mx + "%");
      card.style.setProperty("--my", my + "%");
    });
  });
}

/* ---------------------------------------------------------------------------
   5. Scroll reveals (Jakub recipe applied via IntersectionObserver)
--------------------------------------------------------------------------- */
function initReveals() {
  const items = document.querySelectorAll(".reveal");
  if (!items.length) return;
  if (prefersReducedMotion || !("IntersectionObserver" in window)) {
    items.forEach((el) => el.classList.add("in"));
    return;
  }
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
      });
    },
    { rootMargin: "0px 0px -10% 0px", threshold: 0.12 }
  );
  items.forEach((el) => io.observe(el));
}

/* ---------------------------------------------------------------------------
   6. Live year in footer
--------------------------------------------------------------------------- */
function initYear() {
  const y = document.querySelector("[data-year]");
  if (y) y.textContent = new Date().getFullYear();
}

document.addEventListener("DOMContentLoaded", () => {
  initScrollWarming();
  initNav();
  initDemo();
  initSpecular();
  initReveals();
  initYear();
});
