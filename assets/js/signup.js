/* Volunteer signup UI, backed by the parish Google Sheet via the self-hosted
   signup API. Three ways to help, all on this page:
   - "Chair a Booth": full-day chair slots per booth per day (modal -> /api/chairs)
   - "Setup & Teardown": join the Friday/Monday crew lists (modal -> /api/crew)
   - Booth shift grids: 2-hour slots grouped by day; each slot can need
     multiple volunteers — chips show everyone signed up and how many spots
     remain (modal -> /api/signups, clicked time = start, "until" select).
   Degrades to the organizers' email if the API is unreachable. */
(function () {
  "use strict";

  var root = document.getElementById("signup-app");
  if (!root) return;

  var API = (root.dataset.api || "").replace(/\/$/, "");
  var FALLBACK_EMAIL = root.dataset.fallbackEmail || "";

  var state = {
    days: [], booths: [], grid: {}, chairs: [], crew: {}, slotMin: 120,
    expanded: { __chairs__: true, __crew__: true }
  };

  function el(tag, attrs, children) {
    var node = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "class") node.className = attrs[k];
      else if (k === "text") node.textContent = attrs[k];
      else if (k.indexOf("on") === 0) node.addEventListener(k.slice(2), attrs[k]);
      else node.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { node.appendChild(c); });
    return node;
  }

  function toMinutes(label) {
    var m = /^(\d{1,2}):(\d{2})\s*(AM|PM)$/i.exec((label || "").trim());
    if (!m) return null;
    var h = parseInt(m[1], 10) % 12;
    if (/pm/i.test(m[3])) h += 12;
    return h * 60 + parseInt(m[2], 10);
  }

  function toLabel(minutes) {
    var h24 = Math.floor(minutes / 60) % 24;
    var period = h24 >= 12 ? "PM" : "AM";
    var h = h24 % 12 || 12;
    var mm = String(minutes % 60);
    if (mm.length < 2) mm = "0" + mm;
    return h + ":" + mm + " " + period;
  }

  function shortLabel(minutes) {
    var h24 = Math.floor(minutes / 60) % 24;
    var h = h24 % 12 || 12;
    var mm = minutes % 60;
    return mm ? h + ":" + mm : String(h);
  }

  function rangeLabel(startMin) {
    return shortLabel(startMin) + "–" + shortLabel(startMin + state.slotMin);
  }

  function showError() {
    root.innerHTML = "";
    root.appendChild(el("div", { class: "signup-error" }, [
      el("p", { text: "The online sign-up is taking a break right now." }),
      el("p", {}, [
        document.createTextNode("You can still volunteer! Email the organizers at "),
        el("a", { href: "mailto:" + FALLBACK_EMAIL, text: FALLBACK_EMAIL }),
        document.createTextNode(" and they'll get you on the schedule.")
      ])
    ]));
  }

  function load() {
    fetch(API + "/api/slots")
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (data) {
        if (!data.days || !data.days.length || !data.booths || !data.booths.length) throw new Error("empty");
        state.days = data.days;
        state.booths = data.booths;
        state.grid = data.grid;
        state.chairs = data.chairs || [];
        state.crew = data.crew || {};
        state.slotMin = data.slotMinutes || 120;
        render();
      })
      .catch(showError);
  }

  function cellsFor(day, booth) {
    return ((state.grid[day] || {})[booth] || []).map(function (r) {
      return { min: toMinutes(r.time), names: r.names || [], need: r.need || 0, open: r.open || 0 };
    }).filter(function (c) { return c.min !== null; });
  }

  function render() {
    root.innerHTML = "";
    if (state.chairs.length) root.appendChild(renderChairCard());
    if (state.crew.Setup || state.crew.Teardown) root.appendChild(renderCrewCard());
    state.booths.forEach(function (booth) {
      root.appendChild(renderBooth(booth));
    });
  }

  function collapsibleCard(key, title, badgeText, badgeOpen, body) {
    if (!state.expanded[key]) body.setAttribute("hidden", "");
    var header = el("button", {
      class: "booth-header",
      type: "button",
      "aria-expanded": String(!!state.expanded[key]),
      "data-booth": key,
      onclick: function () {
        state.expanded[key] = body.hasAttribute("hidden");
        if (state.expanded[key]) body.removeAttribute("hidden");
        else body.setAttribute("hidden", "");
        header.setAttribute("aria-expanded", String(state.expanded[key]));
      }
    }, [
      el("span", { text: title }),
      el("span", { class: "booth-open" + (badgeOpen ? "" : " full"), text: badgeText })
    ]);
    return el("div", { class: "booth" }, [header, body]);
  }

  // ---- Chair a booth ----

  function renderChairCard() {
    var open = state.chairs.filter(function (c) { return !c.chair; });

    var body = el("div", { class: "booth-body" });
    body.appendChild(el("p", { class: "chair-intro" }, [
      document.createTextNode("Every booth needs a captain! Chairing is a "),
      el("strong", { text: "full-day commitment" }),
      document.createTextNode(" — you run the booth and make it great. Chairs get the opportunity to purchase a 1-day ride bracelet or drink badge.")
    ]));

    state.days.forEach(function (day) {
      var dayChairs = state.chairs.filter(function (c) { return c.day === day; });
      if (!dayChairs.length) return;
      body.appendChild(el("p", { class: "day-label", text: day }));
      var grid = el("div", { class: "time-grid chair-grid" });
      dayChairs.forEach(function (c) {
        if (c.chair) {
          grid.appendChild(el("div", { class: "time-chip taken", title: c.chair }, [
            el("span", { class: "chip-time", text: c.booth }),
            el("span", { class: "chip-name", text: c.chair })
          ]));
        } else {
          grid.appendChild(el("button", {
            class: "time-chip open",
            type: "button",
            "aria-label": "Chair the " + c.booth + " booth on " + day,
            onclick: function () { openChairModal(c.day, c.booth); }
          }, [
            el("span", { class: "chip-time", text: c.booth }),
            el("span", { class: "chip-name", text: "Open — all day" })
          ]));
        }
      });
      body.appendChild(grid);
    });

    return collapsibleCard(
      "__chairs__",
      "🌟 Chair a Booth",
      open.length ? open.length + (open.length === 1 ? " booth needs a chair" : " booths need chairs") : "All booths chaired — thank you!",
      open.length,
      body
    );
  }

  // ---- Setup & teardown crew ----

  function renderCrewCard() {
    var crews = [
      { key: "Setup", icon: "🔨", when: "Friday, the day before Homecoming", blurb: "Build the midway: tents, booths, tables, lights." },
      { key: "Teardown", icon: "📦", when: "Monday, the day after Homecoming", blurb: "Pack it all away and put the campus back together." }
    ];
    var total = crews.reduce(function (n, c) { return n + (state.crew[c.key] || []).length; }, 0);

    var cols = el("div", { class: "crew-cols" });
    crews.forEach(function (c) {
      var names = state.crew[c.key] || [];
      cols.appendChild(el("div", { class: "crew-col" }, [
        el("p", { class: "crew-title", text: c.icon + " " + c.key + " Crew" }),
        el("p", { class: "crew-when", text: c.when }),
        el("p", { class: "crew-blurb", text: c.blurb }),
        el("p", { class: "crew-names" }, [
          names.length
            ? el("span", { text: "On the crew: " + names.join(", ") })
            : el("span", { class: "empty", text: "Be the first on the list!" })
        ]),
        el("button", {
          class: "btn",
          type: "button",
          text: "Join the " + c.key + " Crew",
          onclick: function () { openCrewModal(c.key, c.when); }
        })
      ]));
    });

    var body = el("div", { class: "booth-body" }, [cols]);
    return collapsibleCard(
      "__crew__",
      "🔧 Setup & Teardown",
      total ? total + " on the crew — room for more!" : "Join the crew!",
      1,
      body
    );
  }

  // ---- Shift signups ----

  function renderBooth(booth) {
    var openSpots = 0;
    state.days.forEach(function (day) {
      cellsFor(day, booth).forEach(function (c) { openSpots += c.open; });
    });

    var body = el("div", { class: "booth-body" });
    state.days.forEach(function (day) {
      var cells = cellsFor(day, booth);
      if (!cells.length) return;
      body.appendChild(el("p", { class: "day-label", text: day }));
      var grid = el("div", { class: "time-grid slot-grid" });
      cells.forEach(function (cell) {
        var nameText = cell.names.length
          ? cell.names.join(", ") + (cell.open > 0 ? " · +" + cell.open + " more" : "")
          : "Open · " + cell.need + " needed";
        if (cell.open > 0) {
          grid.appendChild(el("button", {
            class: "time-chip open",
            type: "button",
            title: nameText,
            "aria-label": "Sign up for " + booth + ", " + day + " at " + toLabel(cell.min),
            onclick: function () { openShiftModal(booth, day, cell.min); }
          }, [
            el("span", { class: "chip-time", text: rangeLabel(cell.min) }),
            el("span", { class: "chip-name", text: nameText })
          ]));
        } else {
          grid.appendChild(el("div", { class: "time-chip taken", title: cell.names.join(", ") }, [
            el("span", { class: "chip-time", text: rangeLabel(cell.min) }),
            el("span", { class: "chip-name", text: cell.names.join(", ") || "—" })
          ]));
        }
      });
      body.appendChild(grid);
    });

    return collapsibleCard(
      booth,
      booth,
      openSpots ? openSpots + (openSpots === 1 ? " slot open" : " slots open") : "Full — thank you!",
      openSpots,
      body
    );
  }

  // ---- Modal ----

  function closeModal() {
    var backdrop = document.querySelector(".modal-backdrop");
    if (backdrop) backdrop.remove();
    document.removeEventListener("keydown", escHandler);
  }

  function escHandler(e) {
    if (e.key === "Escape") closeModal();
  }

  function personFields() {
    return [
      el("label", { for: "su-first", text: "First name" }),
      el("input", { id: "su-first", name: "first_name", type: "text", required: "", autocomplete: "given-name", maxlength: "60" }),
      el("label", { for: "su-last", text: "Last name (shown to others as an initial: “Mike M.”)" }),
      el("input", { id: "su-last", name: "last_name", type: "text", required: "", autocomplete: "family-name", maxlength: "60" }),
      el("label", { for: "su-email", text: "Email" }),
      el("input", { id: "su-email", name: "email", type: "email", required: "", autocomplete: "email", maxlength: "120" }),
      el("label", { for: "su-phone", text: "Phone (optional)" }),
      el("input", { id: "su-phone", name: "phone", type: "tel", autocomplete: "tel", maxlength: "30" }),
      el("div", { class: "hp-field", "aria-hidden": "true" }, [
        el("label", { for: "su-website", text: "Leave this field empty" }),
        el("input", { id: "su-website", name: "website", type: "text", tabindex: "-1", autocomplete: "off" })
      ])
    ];
  }

  // opts: { title, sub, endpoint, leadNodes, payload(formData) }
  function showModal(opts) {
    closeModal();

    var errorLine = el("p", { class: "form-error", hidden: "" });
    var formChildren = (opts.leadNodes || []).concat(personFields()).concat([
      el("div", { class: "form-actions" }, [
        el("button", { class: "btn", type: "submit", text: "Confirm Sign-Up" }),
        el("button", { class: "btn btn-ghost", type: "button", text: "Cancel", onclick: closeModal }),
        errorLine
      ])
    ]);

    var form = el("form", {
      class: "signup-form modal-form",
      onsubmit: function (e) {
        e.preventDefault();
        var data = new FormData(form);
        var btn = form.querySelector("button[type=submit]");
        btn.disabled = true;
        errorLine.setAttribute("hidden", "");

        fetch(API + opts.endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(opts.payload(data))
        })
          .then(function (res) { return res.json().then(function (j) { return { ok: res.ok, body: j }; }); })
          .then(function (r) {
            if (!r.ok) throw new Error(r.body.error || "Something went wrong.");
            form.innerHTML = "";
            form.appendChild(el("p", { class: "form-success", text: "You're on the schedule — thank you! 🎉" }));
            setTimeout(function () { closeModal(); load(); }, 1400);
          })
          .catch(function (err) {
            btn.disabled = false;
            errorLine.textContent = err.message;
            errorLine.removeAttribute("hidden");
          });
      }
    }, formChildren);

    var modal = el("div", { class: "modal", role: "dialog", "aria-modal": "true", "aria-label": "Volunteer sign-up" }, [
      el("div", { class: "modal-head" }, [
        el("p", { class: "modal-title", text: opts.title }),
        el("p", { class: "modal-sub", text: opts.sub }),
        el("button", { class: "modal-close", type: "button", "aria-label": "Close", text: "✕", onclick: closeModal })
      ]),
      form
    ]);

    var backdrop = el("div", {
      class: "modal-backdrop",
      onclick: function (e) { if (e.target === backdrop) closeModal(); }
    }, [modal]);

    document.body.appendChild(backdrop);
    document.addEventListener("keydown", escHandler);
    form.querySelector("input[name=first_name]").focus();
  }

  function untilOptions(day, booth, startMin) {
    var openMins = cellsFor(day, booth).filter(function (c) { return c.open > 0; })
      .map(function (c) { return c.min; });
    var options = [];
    var t = startMin;
    while (openMins.indexOf(t) !== -1) {
      options.push(t + state.slotMin);
      t += state.slotMin;
    }
    return options;
  }

  function openShiftModal(booth, day, startMin) {
    var opts = untilOptions(day, booth, startMin);
    var endSelect = el("select", { id: "su-end", name: "end", required: "" });
    opts.forEach(function (t) {
      endSelect.appendChild(el("option", { value: toLabel(t), text: toLabel(t) }));
    });
    endSelect.selectedIndex = 0; // default: one slot

    showModal({
      title: booth,
      sub: day + " · starting " + toLabel(startMin),
      endpoint: "/api/signups",
      leadNodes: [
        el("div", { class: "form-times" }, [
          el("span", {}, [
            el("label", { text: "From" }),
            el("p", { class: "modal-start", text: toLabel(startMin) })
          ]),
          el("span", {}, [el("label", { for: "su-end", text: "Until" }), endSelect])
        ])
      ],
      payload: function (data) {
        return {
          day: day,
          booth: booth,
          start: toLabel(startMin),
          end: data.get("end"),
          first_name: data.get("first_name"),
          last_name: data.get("last_name"),
          email: data.get("email"),
          phone: data.get("phone"),
          website: data.get("website")
        };
      }
    });
  }

  function openChairModal(day, booth) {
    showModal({
      title: "Chair: " + booth,
      sub: day + " · full-day commitment",
      endpoint: "/api/chairs",
      leadNodes: [],
      payload: function (data) {
        return {
          day: day,
          booth: booth,
          first_name: data.get("first_name"),
          last_name: data.get("last_name"),
          email: data.get("email"),
          phone: data.get("phone"),
          website: data.get("website")
        };
      }
    });
  }

  function openCrewModal(crew, when) {
    showModal({
      title: crew + " Crew",
      sub: when,
      endpoint: "/api/crew",
      leadNodes: [],
      payload: function (data) {
        return {
          crew: crew,
          first_name: data.get("first_name"),
          last_name: data.get("last_name"),
          email: data.get("email"),
          phone: data.get("phone"),
          website: data.get("website")
        };
      }
    });
  }

  load();
})();
