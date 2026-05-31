"""
Galcon 2 — Recorder + Replay (all-in-one)

Run this before starting Galcon. When your game ends and you hit
'Save and Quit', the replay launches automatically.

Pass an existing session file as argument to skip recording:
    python galcon.py galcon_recordings/session_20260522_172946.jsonl
"""

import json, os, sys, time, math
from datetime import datetime
import matplotlib
matplotlib.use("MacOSX")
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib.patches import Circle

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────
BIN_FILE   = "/Users/name/Library/Application Support/Galcon 2/mod1.bin"
OUTPUT_DIR = "galcon_recordings"

KEY_PLAY_PAUSE   = " "
KEY_STEP_FORWARD = "d"
KEY_STEP_BACK    = "a"
KEY_SPEED_UP     = "w"
KEY_SPEED_DOWN   = "s"
KEY_RESTART      = "r"
KEY_QUIT         = "q"

DEBUG_POS = False

# ─────────────────────────────────────────────────────────────────────────────
# COLOURS
# ─────────────────────────────────────────────────────────────────────────────
BG       = "#050a10"
P_COLOR  = "#00ff88"
E_COLOR  = "#ff4444"
P_FLEET  = "#00ffbb"
E_FLEET  = "#ff8888"
YELLOW   = "#ffee44"
WHITE    = "#ddeeff"
MUTED    = "#445566"
GRID     = "#0d1a26"
NEUTRAL  = "#666677"
SEL_RING = "#ffffff"
P_PCT_COLOR = "#44ffaa"   # player send % label
E_PCT_COLOR = "#ff9966"   # enemy bot send % label

def fleet_radius(ships):
    return 3 + 2.5 * (max(1, ships) ** 0.4)

# ─────────────────────────────────────────────────────────────────────────────
# RECORDER
# ─────────────────────────────────────────────────────────────────────────────
def read_bin():
    try:
        with open(BIN_FILE, "r") as f:
            return json.load(f)
    except:
        return None

def run_recorder():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 60)
    print("  GALCON 2  —  RECORDER + REPLAY")
    print("=" * 60)
    print(f"  Watching : {BIN_FILE}")
    print(f"  Load your mod in Galcon and play.")
    print(f"  When the game ends it will save automatically.")
    print(f"  Replay launches automatically.")
    print("=" * 60)

    last_chunk = -1

    while True:
        try:
            data = read_bin()
            if data is None:
                time.sleep(0.1); continue

            payload = data.get("payload")
            if payload is None:
                time.sleep(0.1); continue

            chunk_index = payload.get("chunk", -1)
            is_final    = payload.get("final", False)

            # wait for a new chunk or a final flag
            if chunk_index == last_chunk and not is_final:
                time.sleep(0.1); continue

            last_chunk = chunk_index

            if not is_final:
                print(f"  [watching... chunk {chunk_index}]")
                time.sleep(0.1); continue

            # final chunk received — build the session file from accumulated data
            map_data = payload.get("map", [])
            if not map_data:
                print("  [waiting for complete game data...]")
                time.sleep(0.1); continue

            session_id   = datetime.now().strftime("%Y%m%d_%H%M%S")
            session_file = os.path.join(
                OUTPUT_DIR, f"session_{session_id}.jsonl")

            all_events = data.get("all_events", [])
            all_pos    = data.get("all_pos",    [])
            summary    = data.get("summary",    [])

            print(f"\n  [GAME COMPLETE] {len(map_data)} planets  "
                  f"{len(all_events)} events  {len(all_pos)} positions")

            with open(session_file, "w") as f:
                # init line
                json.dump({
                    "type":     "init",
                    "map":      map_data,
                    "player_n": payload.get("player_n"),
                    "enemy_n":  payload.get("enemy_n"),
                    "version":  payload.get("version"),
                    "w":        payload.get("w"),
                    "h":        payload.get("h"),
                    "session":  session_id,
                }, f)
                f.write("\n")
                # single chunk with all data
                json.dump({
                    "type":    "chunk",
                    "chunk":   1,
                    "events":  all_events,
                    "pos":     all_pos,
                    "summary": summary,
                    "final":   True,
                }, f)
                f.write("\n")

            print(f"  Saved → {session_file}")
            print("  Launching replay...\n")
            return session_file

        except KeyboardInterrupt:
            print("\n  Recorder stopped.")
            return None
        except Exception as ex:
            print(f"  [error] {ex}")
            time.sleep(0.2)

# ─────────────────────────────────────────────────────────────────────────────
# TIMELINE BUILDER
# ─────────────────────────────────────────────────────────────────────────────
def build_timeline(init_data, chunks):
    planet_owners   = {p["n"]: p["owner"] for p in init_data["map"]}
    planet_ships    = {p["n"]: p["ships"] for p in init_data["map"]}
    planet_selected = {p["n"]: False      for p in init_data["map"]}

    fleet_meta   = {}
    fleet_ships  = {}   # FIX: track live ship counts separately
    fleet_exists = {}

    all_events = []
    all_pos    = []
    for chunk in chunks:
        all_events.extend(chunk.get("events", []))
        all_pos.extend(   chunk.get("pos",    []))

    all_events.sort(key=lambda e: e["t"])
    all_pos.sort(   key=lambda p: p[0])

    # first pass: reconstruct absolute positions
    abs_pos     = {}
    raw_samples = {}

    for p in all_pos:
        t_s  = p[0]
        fid  = str(p[1])
        a, b = p[2], p[3]
        mode = p[4]

        if mode == 0:
            abs_pos[fid] = (a, b)
        elif fid in abs_pos:
            ox, oy = abs_pos[fid]
            abs_pos[fid] = (ox + a, oy + b)

        if fid in abs_pos:
            if fid not in raw_samples:
                raw_samples[fid] = []
            raw_samples[fid].append((t_s, abs_pos[fid][0], abs_pos[fid][1]))

    if DEBUG_POS:
        print(f"\n  [DEBUG] {len(raw_samples)} fleets have position samples:")
        for fid in sorted(raw_samples.keys()):
            s = raw_samples[fid]
            print(f"    fleet {fid:>8s}: {len(s):4d} samples  "
                  f"t={s[0][0]:.1f}->{s[-1][0]:.1f}  "
                  f"start=({s[0][1]:.0f},{s[0][2]:.0f})  "
                  f"end=({s[-1][1]:.0f},{s[-1][2]:.0f})")
        print()

    # ── Build send-percentage annotations ────────────────────────────────────
    # The Lua mod writes "sent" (ships dispatched) and "rem" (ships remaining
    # on the source planet, read that same loop() tick) into every player "fs"
    # event.  pct = round(sent / (sent + rem) / 5) * 5, snapped to nearest 5
    # because Galcon only allows 5% increments.  Both values come from the
    # same frame so there is no timer lag.
    # Structure: list of {t, pid, pct, x, y}
    send_pct_events = []

    # Planet positions for annotation placement
    planet_pos = {p["n"]: (p["x"], p["y"]) for p in init_data["map"]}

    # Position -> planet_id lookup for spawn-point matching
    pos_to_pid = {}
    for p in init_data["map"]:
        pos_to_pid[(round(p["x"]), round(p["y"]))] = p["n"]

    def pid_from_spawn(sx, sy, tol=60):
        best_pid  = None
        best_dist = tol
        for (px, py), pid in pos_to_pid.items():
            d = math.hypot(px - sx, py - sy)
            if d < best_dist:
                best_dist = d
                best_pid  = pid
        return best_pid

    for ev in all_events:
        if ev["e"] != "fs":
            continue
        sent = ev.get("s", 0)
        rem  = ev.get("rem")          # ships left on planet, same tick
        if rem is None or sent == 0:
            continue                   # old recording without rem field
        total = sent + rem
        if total == 0:
            continue
        raw_pct = sent / total * 100
        pct     = round(raw_pct / 5) * 5
        pct     = max(5, min(100, pct))
        pid = pid_from_spawn(ev.get("x", 0), ev.get("y", 0))
        if pid is None:
            continue
        px, py = planet_pos[pid]
        send_pct_events.append({
            "t":     ev["t"],
            "pid":   pid,
            "pct":   pct,
            "x":     px,
            "y":     py,
            "owner": ev.get("o"),
        })


    # second pass: event timeline
    times = sorted(set(
        [e["t"] for e in all_events] +
        [p[0]   for p  in all_pos]
    ))

    ei = 0
    frames = [{
        "t":               0.0,
        "fleet_meta":      {},
        "fleet_ships":     {},
        "planet_owners":   dict(planet_owners),
        "planet_ships":    dict(planet_ships),
        "planet_selected": dict(planet_selected),
    }]

    for t in times:
        while ei < len(all_events) and all_events[ei]["t"] <= t:
            ev = all_events[ei]; ei += 1
            e  = ev["e"]
            if e == "fs":
                fid = ev["id"]
                fleet_meta[fid]   = {
                    "owner":   ev["o"],
                    "target":  ev["tg"],
                    "ships":   ev["s"],
                    "spawn_t": ev["t"],
                    "spawn_x": ev["x"],
                    "spawn_y": ev["y"],
                }
                fleet_ships[fid]  = ev["s"]   # FIX: seed live count
                fleet_exists[fid] = True
            elif e == "fd":
                fleet_exists[ev["id"]] = False
            elif e == "fr":
                if ev["id"] in fleet_meta:
                    fleet_meta[ev["id"]]["target"] = ev["tg"]
            elif e == "fu":
                # FIX: fleet ship count update (partial combat / redirect)
                fid = ev["id"]
                fleet_ships[fid] = ev["s"]
            elif e == "pc":
                planet_owners[ev["n"]] = ev["o"]
            elif e == "pn":
                planet_ships[ev["n"]]  = ev["s"]
            elif e == "sel":
                planet_selected[ev["n"]] = True
            elif e == "dsel":
                planet_selected[ev["n"]] = False

        active = {}
        for fid in fleet_exists:
            if fleet_exists.get(fid) and fid in fleet_meta:
                m = dict(fleet_meta[fid])
                m["ships"] = fleet_ships.get(fid, m["ships"])  # FIX: live count
                active[fid] = m

        frames.append({
            "t":               t,
            "fleet_meta":      active,
            "planet_owners":   dict(planet_owners),
            "planet_ships":    dict(planet_ships),
            "planet_selected": dict(planet_selected),
        })

    all_fleet_meta = {}
    for fr in frames:
        for fid, m in fr["fleet_meta"].items():
            if fid not in all_fleet_meta:
                all_fleet_meta[fid] = m

    # ── Collect fleet target events (spawn + redirect) ──────────────────────
    # Each entry: {t, fid, tg, owner}
    # Used by replay to show target label and flash effects.
    fleet_target_events = []
    for ev in all_events:
        if ev["e"] == "fs":
            fleet_target_events.append({
                "t":     ev["t"],
                "fid":   ev["id"],
                "tg":    ev["tg"],
                "owner": ev["o"],
                "redirect": False,
            })
        elif ev["e"] == "fr":
            owner = fleet_meta.get(ev["id"], {}).get("owner", None)
            fleet_target_events.append({
                "t":     ev["t"],
                "fid":   ev["id"],
                "tg":    ev["tg"],
                "owner": owner,
                "redirect": True,
            })

    return frames, raw_samples, all_fleet_meta, send_pct_events, fleet_target_events

# ─────────────────────────────────────────────────────────────────────────────
# POSITION INTERPOLATION
# ─────────────────────────────────────────────────────────────────────────────
def interpolate_fleet_pos(raw_samples, fid, t, all_fleet_meta):
    meta = all_fleet_meta.get(fid, {})

    if fid not in raw_samples or not raw_samples[fid]:
        return meta.get("spawn_x", 0), meta.get("spawn_y", 0)

    samples = raw_samples[fid]

    if t <= samples[0][0]:
        sx  = meta.get("spawn_x", samples[0][1])
        sy  = meta.get("spawn_y", samples[0][2])
        t0  = meta.get("spawn_t", samples[0][0])
        t1  = samples[0][0]
        if t1 > t0:
            alpha = max(0.0, min(1.0, (t - t0) / (t1 - t0)))
            return (sx + alpha * (samples[0][1] - sx),
                    sy + alpha * (samples[0][2] - sy))
        return samples[0][1], samples[0][2]

    if t >= samples[-1][0]:
        return samples[-1][1], samples[-1][2]

    lo, hi = 0, len(samples) - 1
    while lo + 1 < hi:
        mid = (lo + hi) // 2
        if samples[mid][0] <= t:
            lo = mid
        else:
            hi = mid

    t0, x0, y0 = samples[lo]
    t1, x1, y1 = samples[hi]
    if t1 == t0:
        return x0, y0
    alpha = (t - t0) / (t1 - t0)
    return x0 + alpha * (x1 - x0), y0 + alpha * (y1 - y0)

# ─────────────────────────────────────────────────────────────────────────────
# REPLAY
# ─────────────────────────────────────────────────────────────────────────────
def payoff_time(cost, prod):
    if prod <= 0: return None
    return cost * 50.0 / prod

def calc_vt(ps, pp, es, ep):
    diff = (pp - ep) / 50.0
    if diff == 0: return None
    return -(ps - es) / diff

def run_replay(session_file):
    lines     = open(session_file).readlines()
    init_data = json.loads(lines[0])
    chunks    = [json.loads(l) for l in lines[1:]]
    frames, raw_samples, all_fleet_meta, send_pct_events, fleet_target_events = build_timeline(init_data, chunks)

    # ── Load summary log for graphs ───────────────────────────────────────────
    summary = []
    for c in chunks:
        if c.get("summary"):
            summary = c["summary"]
            break

    W, H     = init_data["w"], init_data["h"]
    player_n = init_data["player_n"]
    enemy_n  = init_data["enemy_n"]
    planets  = {p["n"]: p for p in init_data["map"]}

    print(f"  Timeline: {len(frames)} frames  "
          f"({frames[-1]['t']:.1f}s game time)")
    print(f"  Send-% annotations: {len(send_pct_events)}")
    print(f"  Fleet target events: {len(fleet_target_events)}")
    for _spe in send_pct_events[:5]:
        print(f"    pct event: t={_spe['t']} pid={_spe['pid']} pct={_spe['pct']}%")

    fig = plt.figure(figsize=(15, 9), facecolor=BG)
    fig.canvas.manager.set_window_title("Galcon 2 Replay")

    try:
        fig.canvas.mpl_disconnect(
            fig.canvas.manager.key_press_handler_id)
    except Exception:
        pass

    # layout: game map left (full height), stats top-right, graphs bottom-right
    gs  = fig.add_gridspec(2, 2,
                           width_ratios=[2.3, 1],
                           height_ratios=[1, 1],
                           wspace=0.03, hspace=0.35)
    ax  = fig.add_subplot(gs[:, 0])   # map spans both rows
    axr = fig.add_subplot(gs[0, 1])   # stats top-right

    ax.set_facecolor(BG)
    ax.set_xlim(0, W); ax.set_ylim(H, 0)
    ax.set_aspect("equal"); ax.axis("off")
    axr.set_facecolor(BG); axr.axis("off")

    for gx in range(0, W + 1, 100):
        ax.axvline(gx, color=GRID, linewidth=0.4, zorder=0)
    for gy in range(0, H + 1, 100):
        ax.axhline(gy, color=GRID, linewidth=0.4, zorder=0)

    def owner_color(n):
        if n == player_n: return P_COLOR
        if n == enemy_n:  return E_COLOR
        return NEUTRAL

    # ── Graphs (ships + prod) embedded in bottom-right cell ─────────────────
    def find_crossovers(ts, a_vals, b_vals):
        crossovers = []
        for i in range(len(ts) - 1):
            da0 = a_vals[i]   - b_vals[i]
            da1 = a_vals[i+1] - b_vals[i+1]
            if da0 * da1 < 0:
                frac  = da0 / (da0 - da1)
                cx_t  = ts[i] + frac * (ts[i+1] - ts[i])
                cx_v  = a_vals[i] + frac * (a_vals[i+1] - a_vals[i])
                crossovers.append((cx_t, cx_v))
        return crossovers

    # two stacked graphs share the bottom-right gridspec cell
    gs_inner = gs[1, 1].subgridspec(2, 1, hspace=0.55)
    ax_sh = fig.add_subplot(gs_inner[0])
    ax_pr = fig.add_subplot(gs_inner[1])

    for gax in (ax_sh, ax_pr):
        gax.set_facecolor("#080f18")
        gax.tick_params(colors=MUTED, labelsize=5)
        for spine in gax.spines.values():
            spine.set_edgecolor(MUTED)
            spine.set_linewidth(0.4)

    ax_sh.set_title("Ships",      color=WHITE, fontsize=6.5, pad=2)
    ax_pr.set_title("Production", color=WHITE, fontsize=6.5, pad=2)
    ax_sh.set_xlabel("time (s)", color=MUTED, fontsize=5)
    ax_pr.set_xlabel("time (s)", color=MUTED, fontsize=5)

    if summary:
        g_ts = [e["t"]  for e in summary]
        g_ps = [e["ps"] for e in summary]
        g_es = [e["es"] for e in summary]
        g_pp = [e["pp"] for e in summary]
        g_ep = [e["ep"] for e in summary]

        ax_sh.plot(g_ts, g_ps, color=P_COLOR, linewidth=1.0, label="P")
        ax_sh.plot(g_ts, g_es, color=E_COLOR, linewidth=1.0, label="E")
        ax_pr.plot(g_ts, g_pp, color=P_COLOR, linewidth=1.0, label="P")
        ax_pr.plot(g_ts, g_ep, color=E_COLOR, linewidth=1.0, label="E")

        for cx_t, cx_v in find_crossovers(g_ts, g_ps, g_es):
            ax_sh.annotate("", xy=(cx_t, cx_v),
                xytext=(cx_t, cx_v - max(g_ps + g_es) * 0.08),
                arrowprops=dict(arrowstyle="->", color=YELLOW, lw=1.0))
        for cx_t, cx_v in find_crossovers(g_ts, g_pp, g_ep):
            ax_pr.annotate("", xy=(cx_t, cx_v),
                xytext=(cx_t, cx_v - max(g_pp + g_ep) * 0.08),
                arrowprops=dict(arrowstyle="->", color=YELLOW, lw=1.0))

        for gax in (ax_sh, ax_pr):
            gax.legend(fontsize=5, facecolor="#0d1a26",
                       labelcolor=WHITE, edgecolor=MUTED, loc="upper left")

    sh_cursor = ax_sh.axvline(0, color=YELLOW, linewidth=0.7, alpha=0.5)
    pr_cursor = ax_pr.axvline(0, color=YELLOW, linewidth=0.7, alpha=0.5)

    # planets
    planet_fills     = {}
    planet_rings     = {}
    planet_sel_rings = {}
    planet_ship_txt  = {}
    planet_prod_txt  = {}
    planet_po_txt    = {}

    for pid, p in planets.items():
        col  = owner_color(p["owner"])
        fill = Circle((p["x"], p["y"]), p["r"],
                      color=col, alpha=0.2, zorder=2)
        ring = Circle((p["x"], p["y"]), p["r"],
                      fill=False, edgecolor=col, linewidth=1.8, zorder=3)
        sel  = Circle((p["x"], p["y"]), p["r"] + 5,
                      fill=False, edgecolor=SEL_RING,
                      linewidth=2.2, zorder=4, visible=False)
        ax.add_patch(fill); ax.add_patch(ring); ax.add_patch(sel)
        planet_fills[pid]     = fill
        planet_rings[pid]     = ring
        planet_sel_rings[pid] = sel

        st = ax.text(p["x"], p["y"], str(p["ships"]),
                     color=WHITE, fontsize=7, ha="center", va="center",
                     fontweight="bold", zorder=5)
        planet_ship_txt[pid] = st

        # prod value label (ships per 50s, static — prod doesn't change)
        prod_lbl = ax.text(p["x"], p["y"] + p["r"] + 7,
                           f"{p['prod']}",
                           color="#4499ff", fontsize=6.5, ha="center",
                           va="top", alpha=0.9, zorder=5)
        planet_prod_txt[pid] = prod_lbl

        pt_val = payoff_time(p["ships"], p["prod"])
        ptt = ax.text(p["x"], p["y"] + p["r"] + 18,
                      f"{pt_val:.0f}s" if pt_val else "--",
                      color=YELLOW, fontsize=6.5, ha="center",
                      va="top", alpha=0.9, zorder=5)
        planet_po_txt[pid] = ptt

    # ── Send-% annotation artists ─────────────────────────────────────────────
    # Pre-create one text artist per send event; fade them in/out by alpha.
    PCT_FADE_DUR = 1.8   # seconds the label stays visible
    pct_artists  = []    # list of {t, ax_txt}
    for spe in send_pct_events:
        _p       = planets.get(spe["pid"]) or planets.get(str(spe["pid"])) or {}
        _r       = _p.get("r", 12)
        is_enemy = (spe.get("owner") == enemy_n)
        col      = E_PCT_COLOR if is_enemy else P_PCT_COLOR
        # enemy labels below planet, player labels above to avoid overlap
        y_off = spe["y"] + _r + 20 if is_enemy else spe["y"] - _r - 14
        txt = ax.text(
            spe["x"], y_off,
            f'{spe["pct"]}%',
            color=col, fontsize=7, ha="center", va="bottom",
            fontweight="bold", alpha=0.0, zorder=8,
        )
        pct_artists.append({"t": spe["t"], "txt": txt})

    # ── Fleet target label + flash artists ──────────────────────────────────
    # One set of artists per fleet_target_event:
    #   - fading text label above the TARGET planet ("→ [planet]")
    #   - flashing ring on the TARGET planet
    #   - redirect-only: a brighter flash color on the fleet dot itself
    #     (handled in render_at by checking flash_fleets dict)
    TGT_FADE_DUR   = 2.0   # label fade duration (s)
    RING_FADE_DUR  = 0.75  # planet ring flash duration (s)
    FLASH_FADE_DUR = 0.8   # fleet dot flash duration (s)
    REDIRECT_COL   = "#ffffff"  # bright white flash on redirected fleets
    TGT_RING_COL   = "#ffee44"  # yellow flash ring on target planet

    tgt_artists  = []   # {t, fid, tg, redirect, lbl_txt, ring_patch}
    flash_fleets = {}   # fid -> list of redirect times (all flashes preserved)

    for fte in fleet_target_events:
        tg  = fte["tg"]
        tp  = planets.get(tg) or planets.get(str(tg)) or {}
        tx  = tp.get("x", 0)
        ty  = tp.get("y", 0)
        tr  = tp.get("r", 12)

        # label just above the target planet
        prefix = "⟳" if fte["redirect"] else "→"
        lbl = ax.text(
            tx, ty - tr - 18,
            prefix,
            color=TGT_RING_COL, fontsize=7, ha="center", va="bottom",
            fontweight="bold", alpha=0.0, zorder=9,
        )
        # flashing ring on the target planet (slightly outside sel ring)
        ring = Circle((tx, ty), tr + 10,
                      fill=False, edgecolor=TGT_RING_COL,
                      linewidth=2.0, alpha=0.0, zorder=4)
        ax.add_patch(ring)

        tgt_artists.append({
            "t":        fte["t"],
            "fid":      fte["fid"],
            "tg":       tg,
            "redirect": fte["redirect"],
            "lbl":      lbl,
            "ring":     ring,
        })
        if fte["redirect"]:
            flash_fleets.setdefault(fte["fid"], []).append(fte["t"])

    # fleets
    fleet_dots      = {}
    fleet_count_txt = {}

    def spawn_fleet(fid, owner, ships):
        col = P_FLEET if owner == player_n else E_FLEET
        r   = fleet_radius(ships)
        dot = Circle((0, 0), r, color=col, alpha=0.85, zorder=6)
        ax.add_patch(dot)
        cnt = ax.text(0, 0, str(ships), color=WHITE,
                      fontsize=5.5, ha="center", va="top", zorder=7)
        fleet_dots[fid]      = dot
        fleet_count_txt[fid] = cnt

    def remove_fleet(fid):
        if fid in fleet_dots:
            fleet_dots[fid].remove()
            fleet_count_txt[fid].remove()
            del fleet_dots[fid]
            del fleet_count_txt[fid]

    # info panel
    axr.set_xlim(0, 1); axr.set_ylim(0, 1)

    def rtext(x, y, s, color=WHITE, size=8, bold=False, ha="left"):
        return axr.text(x, y, s, color=color, fontsize=size,
                        fontweight="bold" if bold else "normal",
                        ha=ha, va="top", transform=axr.transAxes)

    rtext(0.5, 0.99, "GALCON 2 REPLAY", WHITE, 8, bold=True, ha="center")
    time_txt  = rtext(0.5, 0.94, "t = 0.0s",  YELLOW, 10, bold=True, ha="center")
    speed_txt = rtext(0.5, 0.89, "speed: 1x", MUTED,   7, ha="center")
    axr.axhline(0.86, color=MUTED, linewidth=0.5, alpha=0.4)

    def key_label(k):
        return "SPACE" if k == " " else k.upper()

    for i, c in enumerate([
        f"{key_label(KEY_PLAY_PAUSE)} play/pause  "
        f"{key_label(KEY_STEP_BACK)}/{key_label(KEY_STEP_FORWARD)} step",
        f"{key_label(KEY_SPEED_DOWN)}/{key_label(KEY_SPEED_UP)} speed  "
        f"{key_label(KEY_RESTART)} restart  "
        f"{key_label(KEY_QUIT)} quit",
    ]):
        rtext(0.05, 0.84 - i * 0.04, c, MUTED, 6.0)

    axr.axhline(0.75, color=MUTED, linewidth=0.5, alpha=0.4)

    rtext(0.05, 0.73, "PLAYER", P_COLOR, 9, bold=True)
    p_ships_t   = rtext(0.05, 0.68, "Ships:   --", P_COLOR, 8.5)
    p_prod_t    = rtext(0.05, 0.63, "Prod:    --", P_COLOR, 8.5)
    p_planets_t = rtext(0.05, 0.58, "Planets: --", P_COLOR, 8.5)
    axr.axhline(0.54, color=MUTED, linewidth=0.5, alpha=0.4)

    rtext(0.05, 0.52, "ENEMY", E_COLOR, 9, bold=True)
    e_ships_t   = rtext(0.05, 0.47, "Ships:   --", E_COLOR, 8.5)
    e_prod_t    = rtext(0.05, 0.42, "Prod:    --", E_COLOR, 8.5)
    e_planets_t = rtext(0.05, 0.37, "Planets: --", E_COLOR, 8.5)
    axr.axhline(0.33, color=MUTED, linewidth=0.5, alpha=0.4)

    prod_adv_txt = rtext(0.5, 0.31, "Prod Adv: --", WHITE,  8.5, bold=True, ha="center")
    adv_txt      = rtext(0.5, 0.26, "Ship Adv: --", WHITE,  9,   bold=True, ha="center")
    vs_txt       = rtext(0.5, 0.21, "VS: --",       YELLOW, 8.5, ha="center")
    fleets_txt   = rtext(0.5, 0.16, "Fleets: 0",    MUTED,  8,   ha="center")
    axr.axhline(0.12, color=MUTED, linewidth=0.5, alpha=0.4)

    state      = {"playing": True, "speed": 1.0, "game_t": 0.0, "anim": None}
    max_game_t = frames[-1]["t"]

    def render_at(game_t):
        idx = 0
        for i in range(len(frames) - 1):
            if frames[i + 1]["t"] <= game_t:
                idx = i + 1
            else:
                break
        fr = frames[idx]

        # FIX: track ships on planets AND in fleets for both players
        p_ships = 0; p_prod = 0; p_plan = 0
        e_ships = 0; e_prod = 0; e_plan = 0

        for pid, p in planets.items():
            owner      = fr["planet_owners"].get(pid, p["owner"])
            col        = owner_color(owner)
            cur_ships  = fr["planet_ships"].get(pid, p["ships"])

            planet_fills[pid].set_color(col)
            planet_rings[pid].set_edgecolor(col)
            planet_sel_rings[pid].set_visible(
                bool(fr["planet_selected"].get(pid, False)))
            planet_ship_txt[pid].set_text(str(cur_ships))
            pt_val = payoff_time(p["ships"], p["prod"])
            planet_po_txt[pid].set_text(
                f"{pt_val:.0f}s" if pt_val else "--")

            # FIX: use current ownership and add planet ships to totals
            if owner == player_n:
                p_prod  += p["prod"]   # static production stays correct
                p_plan  += 1
                p_ships += cur_ships   # FIX: was missing
            elif owner == enemy_n:
                e_prod  += p["prod"]
                e_plan  += 1
                e_ships += cur_ships   # FIX: was missing

        active_meta = fr.get("fleet_meta", {})

        for fid in list(fleet_dots):
            if fid not in active_meta:
                remove_fleet(fid)

        for fid, meta in active_meta.items():
            x, y  = interpolate_fleet_pos(
                raw_samples, fid, game_t, all_fleet_meta)
            ships  = meta["ships"]   # FIX: now carries live count from fu events
            owner  = meta["owner"]
            col    = P_FLEET if owner == player_n else E_FLEET
            r      = fleet_radius(ships)

            if fid not in fleet_dots:
                spawn_fleet(fid, owner, ships)

            fleet_dots[fid].center = (x, y)
            fleet_dots[fid].set_radius(r)   # FIX: update radius on ship change
            # flash bright white on redirect, fading back to normal color
            # check all redirect flash times for this fleet — use most recent active one
            flash_times = flash_fleets.get(fid, [])
            flashing = any(0 <= (game_t - ft) < FLASH_FADE_DUR for ft in flash_times)
            fleet_dots[fid].set_color(REDIRECT_COL if flashing else col)
            fleet_count_txt[fid].set_position((x, y + r + 2))
            fleet_count_txt[fid].set_text(str(ships))   # FIX: live count

            if owner == player_n: p_ships += ships
            elif owner == enemy_n: e_ships += ships

        # ── Send-% fade in/out ────────────────────────────────────────────
        for pa in pct_artists:
            dt = game_t - pa["t"]
            if dt < 0 or dt > PCT_FADE_DUR:
                pa["txt"].set_alpha(0.0)
            else:
                # quick fade-in (0→0.3s), hold, then fade-out
                if dt < 0.3:
                    alpha = dt / 0.3 * 0.55
                elif dt < PCT_FADE_DUR - 0.4:
                    alpha = 0.55
                else:
                    alpha = max(0.0, (PCT_FADE_DUR - dt) / 0.4 * 0.55)
                pa["txt"].set_alpha(alpha)

        # ── Target label + planet ring fade ──────────────────────────────
        for ta in tgt_artists:
            dt = game_t - ta["t"]
            # label: full TGT_FADE_DUR
            if dt < 0 or dt > TGT_FADE_DUR:
                ta["lbl"].set_alpha(0.0)
            else:
                if dt < 0.15:
                    a = dt / 0.15
                elif dt < TGT_FADE_DUR - 0.3:
                    a = 1.0
                else:
                    a = max(0.0, (TGT_FADE_DUR - dt) / 0.3)
                ta["lbl"].set_alpha(a * 0.9)
            # ring: shorter RING_FADE_DUR
            if dt < 0 or dt > RING_FADE_DUR:
                ta["ring"].set_alpha(0.0)
            else:
                if dt < 0.1:
                    ra = dt / 0.1
                elif dt < RING_FADE_DUR - 0.2:
                    ra = 1.0
                else:
                    ra = max(0.0, (RING_FADE_DUR - dt) / 0.2)
                ta["ring"].set_alpha(ra * 0.75)

        time_txt.set_text(f"t = {game_t:.2f}s")
        speed_txt.set_text(f"speed: {state['speed']:.3g}x")
        p_ships_t.set_text(  f"Ships:   {p_ships}")
        p_prod_t.set_text(   f"Prod:    {p_prod}")
        p_planets_t.set_text(f"Planets: {p_plan}")
        e_ships_t.set_text(  f"Ships:   {e_ships}")
        e_prod_t.set_text(   f"Prod:    {e_prod}")
        e_planets_t.set_text(f"Planets: {e_plan}")

        # ── prod adv ─────────────────────────────────────────────────────────
        prod_adv = p_prod - e_prod
        if prod_adv > 0:
            prod_adv_txt.set_text(f"Prod Adv: +{prod_adv}")
            prod_adv_txt.set_color(P_COLOR)
        elif prod_adv < 0:
            prod_adv_txt.set_text(f"Prod Adv: {prod_adv}")
            prod_adv_txt.set_color(E_COLOR)
        else:
            prod_adv_txt.set_text("Prod Adv: 0")
            prod_adv_txt.set_color(WHITE)

        # ── ship adv ─────────────────────────────────────────────────────────
        adv = p_ships - e_ships
        if adv > 0:
            adv_txt.set_text(f"Ship Adv: +{adv}"); adv_txt.set_color(P_COLOR)
        elif adv < 0:
            adv_txt.set_text(f"Ship Adv: {adv}");  adv_txt.set_color(E_COLOR)
        else:
            adv_txt.set_text("Ship Adv: 0");        adv_txt.set_color(WHITE)

        # ── versus timer ─────────────────────────────────────────────────────
        vt = calc_vt(p_ships, p_prod, e_ships, e_prod)
        if vt is None:
            vs_txt.set_text("VS: even prod"); vs_txt.set_color(WHITE)
        elif vt <= 0:
            leader = "P" if p_prod > e_prod else "E"
            col    = P_COLOR if leader == "P" else E_COLOR
            vs_txt.set_text(f"VS: {leader} dominating")
            vs_txt.set_color(col)
        else:
            leader = "P" if p_prod > e_prod else "E"
            col    = P_COLOR if leader == "P" else E_COLOR
            m  = int(vt // 60); s = vt % 60
            ts = f"{m}:{s:04.1f}" if m > 0 else f"{s:.1f}s"
            vs_txt.set_text(f"VS: {leader} evens in {ts}")
            vs_txt.set_color(col)

        fleets_txt.set_text(f"Fleets in air: {len(active_meta)}")
        # update graph time cursor
        sh_cursor.set_xdata([game_t, game_t])
        pr_cursor.set_xdata([game_t, game_t])
        fig.canvas.draw_idle()

    INTERVAL_MS = 33

    def animate(_):
        if not state["playing"]:
            return
        if state["game_t"] >= max_game_t:
            state["playing"] = False
            return
        state["game_t"] += (INTERVAL_MS / 1000.0) * state["speed"]
        state["game_t"]  = min(state["game_t"], max_game_t)
        render_at(state["game_t"])

    state["anim"] = animation.FuncAnimation(
        fig, animate, interval=INTERVAL_MS, cache_frame_data=False)

    def on_key(event):
        k = event.key
        if k == KEY_PLAY_PAUSE:
            state["playing"] = not state["playing"]
        elif k == KEY_STEP_FORWARD:
            state["playing"] = False
            state["game_t"]  = min(state["game_t"] + 0.1, max_game_t)
            render_at(state["game_t"])
        elif k == KEY_STEP_BACK:
            state["playing"] = False
            state["game_t"]  = max(state["game_t"] - 0.1, 0.0)
            render_at(state["game_t"])
        elif k == KEY_SPEED_UP:
            state["speed"] = min(state["speed"] * 2, 32.0)
            speed_txt.set_text(f"speed: {state['speed']:.3g}x")
            fig.canvas.draw_idle()
        elif k == KEY_SPEED_DOWN:
            state["speed"] = max(state["speed"] / 2, 0.125)
            speed_txt.set_text(f"speed: {state['speed']:.3g}x")
            fig.canvas.draw_idle()
        elif k == KEY_RESTART:
            state["game_t"]  = 0.0
            state["playing"] = True
            render_at(0.0)
        elif k in (KEY_QUIT, "escape"):
            plt.close(fig)

    fig.canvas.mpl_connect("key_press_event", on_key)
    render_at(0.0)
    plt.tight_layout(pad=0.5)
    plt.show()

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) > 1 and os.path.isfile(sys.argv[1]):
        print(f"  Replaying: {sys.argv[1]}")
        run_replay(sys.argv[1])
    else:
        session_file = run_recorder()
        if session_file:
            run_replay(session_file)
