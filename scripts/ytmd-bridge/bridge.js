#!/usr/bin/env node
// YouTube Music (ytmdesktop) realtime bridge for Quickshell.
// Connects to the companion server's socket.io realtime namespace and prints a
// compact JSON line to stdout on every state change. Quickshell reads stdout.
// Token is read from the keyring (never passed on argv/env).
"use strict";
const http = require("http");
const { execSync } = require("child_process");
const { io } = require("socket.io-client");

const BASE = "http://127.0.0.1:9863";
const NS = "/api/v1/realtime";

let token = "";
try { token = execSync("secret-tool lookup service ytmd-companion key token").toString().trim(); }
catch (e) { process.stderr.write("no token\n"); process.exit(1); }

function durToSec(s) {
  if (!s) return 0;
  const a = ("" + s).split(":").map(n => parseInt(n, 10) || 0);
  if (a.length === 3) return a[0] * 3600 + a[1] * 60 + a[2];
  if (a.length === 2) return a[0] * 60 + a[1];
  return a[0] || 0;
}

// Carried track state — events are often partial (progress-only), so we keep
// the last known video and only overwrite its fields when a new one is present.
let cur = { has: false, title: "", artist: "", album: "", art: "",
            durationSeconds: 0 };

function compact(state) {
  if (!state) return null;
  const p = state.player || {};
  let v = state.video;
  if (!v || !v.title) {
    const q = p.queue;
    if (q && q.items && q.items.length) {
      const it = q.items[q.selectedItemIndex] || q.items.find(x => x.selected);
      if (it) v = { title: it.title, author: it.author, album: "",
                    thumbnails: it.thumbnails, durationSeconds: durToSec(it.duration) };
    }
  }
  if (v && v.title) {
    const th = v.thumbnails || [];
    cur = {
      has: true,
      title: v.title,
      artist: v.author || "",
      album: v.album || "",
      art: (th.length ? th[th.length - 1].url : "") || cur.art,
      durationSeconds: v.durationSeconds || 0,
    };
  }
  return {
    ok: true,
    has: cur.has,
    title: cur.title, artist: cur.artist, album: cur.album, art: cur.art,
    durationSeconds: cur.durationSeconds,
    progress: p.videoProgress || 0,
    trackState: p.trackState,
    volume: p.volume,
    repeatMode: p.repeatMode || 0,
  };
}

let lastSig = "";
function emit(state) {
  const c = compact(state);
  if (!c) return;
  const line = JSON.stringify(c);
  // de-dupe identical consecutive states (ignoring progress, which always ticks)
  const sig = c.has + c.title + c.artist + c.trackState + c.volume + c.repeatMode;
  if (sig === lastSig && c.trackState !== 1) return; // skip noise while paused/stopped
  lastSig = sig;
  process.stdout.write(line + "\n");
}

// REST seed so the UI has the current track immediately (esp. when stopped, when
// socket events carry no video). /state is rate-limited (1/5s) and returns an
// invalid-JSON stub when throttled — so retry every 5.5s until we land a track.
let seedTries = 0;
function seed() {
  const req = http.request(BASE + "/api/v1/state", { headers: { Authorization: token } }, res => {
    let body = "";
    res.on("data", d => body += d);
    res.on("end", () => {
      let ok = false;
      try { const s = JSON.parse(body); emit(s); ok = cur.has; } catch (e) {}
      if (!ok && ++seedTries < 6) setTimeout(seed, 5500);
    });
  });
  req.on("error", () => { if (++seedTries < 6) setTimeout(seed, 5500); });
  req.end();
}

const socket = io(BASE + NS, { transports: ["websocket"], auth: { token }, reconnection: true });
socket.on("connect", () => { process.stderr.write("connected\n"); seed(); });
socket.on("connect_error", e => process.stderr.write("connect_error " + (e && e.message) + "\n"));
socket.on("disconnect", r => process.stderr.write("disconnect " + r + "\n"));
// The state-change event name varies; capture any event carrying player state.
socket.onAny((event, data) => { if (data && data.player) emit(data); });
