"""Move grading (I3): grade every launch in a replay as brilliant / best / excellent / good /
inaccuracy / mistake / blunder.

Usage:
  python3 grade_moves.py "/Users/phillipcall/Desktop/PvP Replays"
  options:  --horizon 10        minimum seconds simulated after each send (default 10); the window is
                                stretched so every option has landed + 3 s (max 25 s), so a far
                                target is never judged before its ships arrive
            --targets 10        nearest targets tried per send (default 10, the real target is always added)
            --max-games N       only grade the first N games (quick test)
            --opening 0         skip sends before this many seconds (default 0 = grade everything).
                                Opening sends (first 10 s) are graded but reported separately: the
                                evaluator is weakest there (AUC 0.73 at 0-5 s) and replaying the
                                opponent's real sends lets an alternative "steal" the planet the
                                opponent is about to take, so check the opening outcome test before
                                trusting opening grades
            --coeffs FILE       landing-model coefficients (default: v3 fit embedded below;
                                stage2c_coeffs_v3.json from the 51-game run)

Chains: a send that lands on the player's own planet and is relaunched from it within 1 s of the first
ships arriving (staging / tunnelling) is graded as ONE move with its later legs (route column, e.g.
27>16>9). The real move replays the whole route on the landing model; every option skips the chain's later
legs, so a direct send to the front is compared with the tunnelled route on equal terms.

For each send (fs) by either player:
  1. Start from the RECORDED game state at that tick (planet ships, owners, fleets in flight).
  2. Try every option: hold (no send), or send 25/50/75/100% (and the real %) to each of the
     nearest targets plus the real target. Every option, the real one included, lands on the
     v3 landing schedule, so they are compared on equal terms.
  3. Simulate `horizon` seconds with the Stage 1 rules engine. Every other send in that window
     (both players) is replayed as the same PERCENT of its source with its logged landing
     timing, scaled to the new fleet size; it is skipped if the source changed hands.
  4. Score each option with the evaluator (--evaluator v2 default, or v3 = train_evaluator.py's model C, read from
     --eval-json, default evaluator_v3.json in the current folder). v2: win prob = logistic(0.064*ship_adv + 0.689*prod_adv),
     ship_adv counts planet ships + ships in flight, prod_adv in ships/s (prod/50).
  4b. Robustness: each option is simulated three times with its landings 0.2 s early / on time /
     0.2 s late, and WP is averaged over the last 2 s of the window, so a 1-ship snipe that only
     works on one exact tick doesn't count as a great move. If the real send's or the best option's
     WP swings more than 0.15 across those timings, the send is graded 'unclear' (like a chess
     engine's "unclear") and left out of the stats.
  5. loss = WP(best option) - WP(real send). Grades (expected-points style):
        best <= 0.005 < excellent <= 0.02 < good <= 0.05 < inaccuracy <= 0.10 < mistake <= 0.20 < blunder
     great = the only move, and it had to be now: holding leaves the player >= 0.03 worse than at the
             send, at most 2 targets (any %) end within 0.02 of where the player started, the real send is
             one of them (loss <= 0.02), and the same send made 1 s later (--great-window) ends >= 0.03 worse.
     brilliant = a sacrifice the engine likes: best (loss <= 0.005), beats the median option by >= 0.10,
             ends at least as well as holding, and gives up a planet that holding would have kept.
             (Stripping a planet into capture range was tried as a second test but fired on a third
             of all sends, so it is only recorded in the exposes_source column.)

Limits (read before trusting a grade):
  - The opponent does not react to the alternative: their later sends are replayed as the same %
    of the same sources. Grades say "given what the opponent actually did next".
  - Win prob is the raw v2 logistic (no isotonic calibration): it ranks options the same way,
    but the WP scale is somewhat different from the viewer's.
  - Hindsight: because the opponent's later sends are fixed, an alternative can look brilliant by
    beating a send the player could not have known about yet. Strongest in the opening (skipped).
  - Retake check (columns adj_, NOT the default): any planet that changed hands in the window is given
    back if the side that lost it could retake it with one send from one planet. It tracked winners
    worse than the raw grades on both test sets (51 games: 70% vs 74%), so raw is the default.
  - One decision at a time: a multi-source team send is graded one send at a time, with the
    other sends of the team kept.

Validation printed at the end:
  A. Fidelity: the real send simulated forward vs what actually happened (WP at the horizon).
  B. Outcome: does the eventual winner lose less WP per move than the loser?

Writes grade_moves_decisions.csv (one row per send), grade_moves_players.csv, and prints a summary.
"""
import json, glob, math, collections, sys, os, csv, time
import numpy as np

# ---------------------------------------------------------------- args
def _arg(name, default, cast=str):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv): return cast(sys.argv[i + 1])
    return default
HORIZON = _arg('--horizon', 10.0, float)
NTARGETS = _arg('--targets', 10, int)
MAXGAMES = _arg('--max-games', 0, int)
OPENING = _arg('--opening', 0.0, float)
GREAT_WINDOW = _arg('--great-window', 1.0, float)
COEFFS = _arg('--coeffs', '')
EVAL_JSON = _arg('--eval-json', 'evaluator_v3.json')
EVALUATOR = _arg('--evaluator', 'both' if os.path.exists(EVAL_JSON) else 'v2')   # v2 = shipped 2-feature logistic, v3 = train_evaluator.py model C,
                                                                                  # both = grade under v2 AND v3 and only call it when they agree
if EVALUATOR not in ('v2', 'v3', 'both'): sys.exit(f"--evaluator must be v2, v3 or both, got {EVALUATOR!r}")
if EVALUATOR == 'both' and not os.path.exists(EVAL_JSON): sys.exit(f"--evaluator both needs {EVAL_JSON} (run train_evaluator.py first)")
ENSEMBLE = EVALUATOR == 'both'
_skip = set()
for f in ('--horizon', '--targets', '--max-games', '--coeffs', '--opening', '--great-window', '--evaluator', '--eval-json'):
    if f in sys.argv:
        i = sys.argv.index(f); _skip.update({i, i + 1})
ARGS = [a for i, a in enumerate(sys.argv[1:], 1) if i not in _skip and not a.startswith('--')]

def _collect(args):
    out = []
    for a in (args or [os.path.expanduser("~/Downloads")]):
        a = os.path.expanduser(a)
        if os.path.isdir(a): out += glob.glob(os.path.join(a, "**", "*.jsonl"), recursive=True)
        else: out += glob.glob(a)
    return sorted(set(out))
FILES = _collect(ARGS)
if not FILES: sys.exit("No .jsonl replay files found.")

def games():
    seen = set()
    for f in FILES:
        init = None; ev = []
        for l in open(f):
            try: o = json.loads(l)
            except ValueError: continue
            if not isinstance(o, dict) or 'type' not in o: continue
            if o['type'] == 'init':
                if init and init['session'] not in seen: seen.add(init['session']); yield init, ev
                init = o; ev = []
            else: ev += o.get('events', [])
        if init and init['session'] not in seen: seen.add(init['session']); yield init, ev

K = lambda t: round(t * 10)

# ---------------------------------------------------------------- evaluator v2 (raw logistic)
B_SHIP, B_PROD = 0.064, 0.689
def wp(ship_adv, prod_adv):
    z = B_SHIP * ship_adv + B_PROD * prod_adv
    return 1 / (1 + math.exp(-max(-50, min(50, z))))

# ---------------------------------------------------------------- v3 landing model (from stage2c)
V3 = {"c": 9.5, "b1": [-0.00031106734015032153, 0.024971796860001387, 0.0],
      "b2": [-0.5151419157014635, 0.027882696302337688, 0.22205810181282293, 0.003561940489179143, -0.00908686626141579, 0.0],
      "gamma": 1.5, "lump": 0.5, "adj1": [-0.04296439697846518, 0.09019314644338519],
      "adj2": [0.11942116695358769, 0.1967810348187098]}
if COEFFS:
    V3 = json.load(open(COEFFS))['full']

def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay; L2 = dx * dx + dy * dy
    u = 0 if L2 == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / L2))
    return math.hypot(ax + u * dx - px, ay + u * dy - py)

NEAR_CLEARANCE = 15.8   # Item H's "negligible" clearance; only used to flag obstacle sends
def detour(ax, ay, bx, by, obs, m=4.0):
    L = math.hypot(bx - ax, by - ay); extra = 0.0
    for ox, oy, r in obs:
        R = r + m
        if seg_dist(ox, oy, ax, ay, bx, by) >= R: continue
        da, db = math.hypot(ax - ox, ay - oy), math.hypot(bx - ox, by - oy)
        if da <= R or db <= R: continue
        ang = math.acos(max(-1, min(1, ((ax - ox) * (bx - ox) + (ay - oy) * (by - oy)) / (da * db))))
        arc = ang - math.acos(R / da) - math.acos(R / db)
        if arc < 0: continue
        extra += math.sqrt(da * da - R * R) + math.sqrt(db * db - R * R) + R * arc - L
    return extra

def features(P, src, tg, owner, x, y, n):
    T = P[tg]
    route = max(0.0, math.hypot(T['x'] - x, T['y'] - y) - T['r'])
    obs = [(p['x'], p['y'], p['r']) for m, p in P.items() if m not in (src, tg) and p['o'] != owner]
    nobs = 0; near = 0
    for ox, oy, r in obs:
        d = seg_dist(ox, oy, x, y, T['x'], T['y']) - r
        if d < 2: nobs += 1
        if d <= NEAR_CLEARANCE: near += 1
    return dict(n=n, sq=math.sqrt(n), route=route, rs=P[src]['r'], nobs=nobs, near=near,
                det=detour(x, y, T['x'], T['y'], obs) if near else 0.0)

def predict(f, M=V3):
    first = M['b1'][0] + M['b1'][1] * max(0, f['route'] - M['c'] * f['sq']) + M['b1'][2] * f['nobs']
    b = M['b2']
    last = b[0] + b[1] * f['route'] + b[2] * f['sq'] + b[3] * f['n'] + b[4] * f['rs'] + b[5] * f['nobs']
    if 'adj1' in M and (f['near'] > 0 or f['nobs'] > 0):
        first += M['adj1'][0] + M['adj1'][1] * f['det']; last += M['adj2'][0] + M['adj2'][1] * f['det']
    first = max(0.0, first); return first, max(first, last)

def schedule(f, M=V3):
    """[(tick offset from send, ships)] summing to n."""
    first, last = predict(f, M); n = f['n']; out = []; prev = 0
    for k in range(K(first), K(last) + 1):
        t = k / 10
        if t < first - 1e-9: c = 0
        elif last - first < 1e-9 or t >= last - 1e-9: c = n
        else: c = min(n, max(1, round(n * (M['lump'] + (1 - M['lump']) * ((t - first) / (last - first)) ** M['gamma']))))
        if c > prev: out.append((k, c - prev)); prev = c
    if prev < n: out.append((K(last), n - prev))
    return out

# ---------------------------------------------------------------- per-game preparation
CHAIN_GAP = 10   # ticks: a relaunch from the landing planet within 1 s of the first ships arriving continues the move
CHAIN_AFTER_LAST = 5   # ...or within 0.5 s after the LAST ships of the stream have landed (players who wait for the whole fleet)
CHAIN_MAX = 30         # never link a relaunch more than 3 s after the first landing
CHAIN_FWD = 1.5        # (src>P1 + P1>T2) / (src>T2): relaunch must continue roughly forward, not back toward the source
CHAIN_SHARE = 0.4      # relaunched ships >= this share of the ships that arrived (unless within 0.5 s)
def chain_of(G, fid):
    out = [fid]
    while 'next' in G['fleets'][out[-1]] and len(out) < 6: out.append(G['fleets'][out[-1]]['next'])
    return out

def prepare(init, ev):
    """Pre-scan: per fleet, its logged drops; base pass (resync) for recorded state per tick."""
    P = {p['n']: dict(o=p['owner'], s=float(p['ships']), prod=p['prod'], x=p['x'], y=p['y'], r=p['r']) for p in init['map']}
    neutral = [p['owner'] for p in init['map'] if p['owner'] not in (init['player_n'], init['enemy_n'])]
    NEU = neutral[0] if neutral else 1
    def src_of(x, y): return min(P, key=lambda n: abs(math.hypot(P[n]['x'] - x, P[n]['y'] - y) - P[n]['r']))
    by = collections.defaultdict(list)
    for e in ev: by[K(e['t'])].append(e)
    last_k = max(by) if by else 0
    fleets = {}      # id -> dict(o, src, tg, s, k, pct, drops=[(tick, tg, amt)])
    cur = {}
    snap = {}        # tick -> {planet: (o, s)} at START of tick (before production)
    inflight_end = {}  # tick -> {owner: ships in flight at END of tick}
    true_end = {}    # tick -> {planet: (o, s)} at END of tick
    flying = collections.Counter()
    decisions = []
    for k in range(0, last_k + 1):
        snap[k] = {n: (p['o'], p['s']) for n, p in P.items()}
        for n, p in P.items():
            if p['o'] != NEU: p['s'] += p['prod'] / 50 * 0.1
        lands = collections.defaultdict(list); order = 0
        for e in by.get(k, []):
            if e['e'] == 'fs':
                s = src_of(e['x'], e['y']); before = max(P[s]['s'], 0.0)
                pct = min(1.0, e['s'] / before) if before > 0 else 1.0
                fleets[e['id']] = dict(o=e['o'], src=s, tg=e['tg'], s=e['s'], k=k, pct=pct, drops=[], order=order, x=e['x'], y=e['y'])
                cur[e['id']] = [e['s'], e['tg']]; P[s]['s'] -= e['s']; flying[e['o']] += e['s']
                decisions.append(e['id']); order += 1
            elif e['e'] == 'fr' and e['id'] in cur: cur[e['id']][1] = e['tg']
            elif e['e'] in ('fu', 'fd') and e['id'] in cur:
                c = cur[e['id']]; drop = c[0] - e['s'] if e['e'] == 'fu' else c[0]
                c[0] = e['s'] if e['e'] == 'fu' else 0
                if drop > 0:
                    f = fleets[e['id']]; f['drops'].append((k, c[1], drop)); lands[c[1]].append((f['o'], drop)); flying[f['o']] -= drop
        for n, L in lands.items():
            p = P[n]
            for o, a in L:
                if o == p['o']: p['s'] += a
                else:
                    p['s'] -= a
                    if p['s'] < 0: p['o'] = o; p['s'] = -p['s']
        for e in by.get(k, []):
            if e['e'] == 'pn': P[e['n']]['s'] = float(e['s'])
            elif e['e'] == 'pc': P[e['n']]['o'] = e['o']
        true_end[k] = {n: (p['o'], p['s']) for n, p in P.items()}
        inflight_end[k] = dict(flying)
    # winner: production at the end, then ships
    a, b = init['player_n'], init['enemy_n']
    def score(o): return (sum(p['prod'] for p in P.values() if p['o'] == o), sum(p['s'] for p in P.values() if p['o'] == o))
    winner = a if score(a) > score(b) else b
    drops_by_tick = collections.defaultdict(list)
    for fid, f in fleets.items():
        for (t, tg, amt) in f['drops']: drops_by_tick[t].append((fid, tg, f['o'], amt))
    # chains: a fleet that lands on its own planet and is relaunched from there within CHAIN_GAP of the
    # first ships arriving (staging / tunnelling). The whole chain is graded as one move.
    by_src = collections.defaultdict(list)
    for fid, f in fleets.items(): by_src[(f['o'], f['src'])].append(fid)
    claimed = set(); P0 = {p['n']: (p['x'], p['y']) for p in init['map']}
    for fid, f in sorted(fleets.items(), key=lambda kv: kv[1]['k']):
        if not f['drops']: continue
        kf, P1 = f['drops'][0][0], f['drops'][0][1]
        if kf not in snap or snap[kf][P1][0] != f['o']: continue
        kl = max(k for k, t, a in f['drops'] if t == P1); arrived = max(sum(a for k, t, a in f['drops'] if t == P1), 0.1)
        def _ok(g):
            h = fleets[g]; kg = h['k']; T2 = h['tg']
            if g in claimed or g == fid or kg < f['k'] or kg < kf - 1: return False
            if kg > min(kf + CHAIN_MAX, max(kf + CHAIN_GAP, kl + CHAIN_AFTER_LAST)): return False
            if T2 in (P1, f['src']): return False
            ds = lambda a, b: math.hypot(P0[a][0] - P0[b][0], P0[a][1] - P0[b][1])
            if (ds(f['src'], P1) + ds(P1, T2)) / max(1.0, ds(f['src'], T2)) > CHAIN_FWD: return False
            return kg - kf <= 5 or h['s'] >= CHAIN_SHARE * arrived
        cands = [g for g in by_src[(f['o'], P1)] if _ok(g)]
        if cands:
            g = min(cands, key=lambda g: fleets[g]['k']); claimed.add(g)
            f['next'] = g; fleets[g]['prev'] = fid; fleets[g]['gap'] = max(0, fleets[g]['k'] - kf)
    return dict(init=init, NEU=NEU, by=by, fleets=fleets, prodmap={p['n']: p['prod'] for p in init['map']},
                geo={p['n']: (p['x'], p['y'], p['r']) for p in init['map']}, snap=snap, true_end=true_end, inflight_end=inflight_end,
                last_k=last_k, winner=winner, decisions=decisions, drops_by_tick=drops_by_tick, src_of=src_of)

SPEED = 40.25
def retake_adjust(planets, start_owner, geo, prodmap, NEU):
    """One-move reply for both sides: a planet that changed hands during the window is handed back if
    the side that lost it has one planet that could retake it in a single send (all its ships, straight
    line at 40.25 u/s, beating the planet's ships + production en route + 1). Each retaking planet is
    used once, biggest captures first. Ships: an even trade (both lose the planet's ships)."""
    P = {n: list(v) for n, v in planets.items()}; used = set()
    changed = [n for n, (o, s) in planets.items() if o != start_owner[n] and o != NEU and start_owner[n] != NEU]
    changed.sort(key=lambda n: -prodmap[n])
    for n in changed:
        o, s = P[n]; loser = start_owner[n]; xi, yi, ri = geo[n]; best = None
        for m, (om, sm) in P.items():
            if om != loser or m in used or m == n: continue
            xm, ym, rm = geo[m]; tau = max(0.0, math.hypot(xm - xi, ym - yi) - ri - rm) / SPEED
            need = s + prodmap[n] / 50 * tau + 1
            if sm >= need and (best is None or tau < best[0]): best = (tau, m, need)
        if best:
            _, m, need = best; used.add(m); P[m][1] -= need; P[n] = [loser, need - s]
    return {n: tuple(v) for n, v in P.items()}

_EV3 = None; _DIST = {}
def _load_ev3():
    global _EV3
    if _EV3 is None:
        _EV3 = json.load(open(EVAL_JSON)); assert _EV3['features'] == ['ship_adv', 'prod_adv', 'planet_ship_adv', 'flight_adv',
            'planets_adv', 'logship', 'vor_adv', 'near_adv', 't_prod', 't_ship'], 'evaluator json feature list changed'
    return _EV3

def wp_v3(planets, inflight, me, other, prodmap, geo, k):
    """train_evaluator.py model C on a simulated state: same features, same units (me minus enemy)."""
    ev = _load_ev3(); c = ev['coef']; near = ev.get('near', 60.0)
    key = id(geo)
    if key not in _DIST:     # keep a reference to geo so its id can't be reused by another dict
        ns = list(geo); _DIST[key] = (geo, {a: {b: math.hypot(geo[a][0] - geo[b][0], geo[a][1] - geo[b][1]) for b in ns} for a in ns})
    D = _DIST[key][1]
    mine = [n for n, (o, s) in planets.items() if o == me]; theirs = [n for n, (o, s) in planets.items() if o == other]
    neut = [n for n, (o, s) in planets.items() if o != me and o != other]
    ps_me = sum(planets[n][1] for n in mine); ps_en = sum(planets[n][1] for n in theirs)
    fl_me = inflight.get(me, 0.0); fl_en = inflight.get(other, 0.0)
    pr_me = sum(prodmap[n] for n in mine) / 50; pr_en = sum(prodmap[n] for n in theirs) / 50
    t = k / 10.0; vor = 0.0
    for n in neut:
        dm = min((D[n][a] for a in mine), default=1e9); de = min((D[n][a] for a in theirs), default=1e9)
        if dm < de: vor += prodmap[n] / 50
        elif de < dm: vor -= prodmap[n] / 50
    near_me = sum(planets[a][1] for a in mine if theirs and min(D[a][b] for b in theirs) <= near)
    near_en = sum(planets[b][1] for b in theirs if mine and min(D[a][b] for a in mine) <= near)
    ship_adv = ps_me + fl_me - ps_en - fl_en; prod_adv = pr_me - pr_en
    f = [ship_adv, prod_adv, ps_me - ps_en, fl_me - fl_en, len(mine) - len(theirs),
         math.log((ps_me + fl_me + 1) / (ps_en + fl_en + 1)), vor, near_me - near_en, t * prod_adv / 100.0, t * ship_adv / 100.0]
    z = sum(a * b for a, b in zip(c, f))
    return 1 / (1 + math.exp(-max(-50, min(50, z))))

def wp_of(planets, inflight, me, other, prodmap, geo=None, k=None, ev=None):
    ev = ev or ('v3' if EVALUATOR == 'v3' else 'v2')      # 'both' grades with v2 as the primary, v3 as the check
    if ev == 'v3' and geo is not None and k is not None:
        return wp_v3(planets, inflight, me, other, prodmap, geo, k)
    ships = collections.Counter(); prod = collections.Counter()
    for n, (o, s) in planets.items(): ships[o] += s; prod[o] += prodmap[n] / 50
    for o, v in inflight.items(): ships[o] += v
    return wp(ships[me] - ships[other], prod[me] - prod[other])

# ---------------------------------------------------------------- counterfactual simulation
def prelaunched(G, k0):
    """logged drops from tick k0 on, of fleets launched before k0"""
    F = G['fleets']; out = []
    for t in sorted(G['drops_by_tick']):
        if t < k0: continue
        for (f2, tg, o, amt) in G['drops_by_tick'][t]:
            if F[f2]['k'] < k0: out.append((t, tg, o, amt))
    return out

SAMPLES = (20, 10, 0)   # WP is averaged at end-2 s, end-1 s and end (a single tick is knife-edge)
EARLY = 20   # ticks: the "how does it look 2 s after the send" check used for brilliant
def simulate(G, fid, option, end_k, shift=0, pre=(), delay=0):
    """option: None = hold, else (target, ships). shift: ticks added to the option's landing schedule.
    delay: ticks the option's launch is held back (the 'send it 1 s later' check for great moves).
    Returns (raw WP, retake-adjusted WP, info): WPs averaged over SAMPLES; info = raw WP 2 s after the
    send and the planets the player owned at the send but no longer owns at the end."""
    init = G['init']; F = G['fleets']; dec = F[fid]; k0 = dec['k']
    base = G['snap'][k0]; prodmap = G['prodmap']; geo = G['geo']
    P = {n: [o, s] for n, (o, s) in base.items()}
    NEU = G['NEU']
    pending = collections.defaultdict(list)   # tick -> [(tg, owner, amt)]
    beyond = collections.Counter()            # ships in flight past end_k
    for (t, tg, o, amt) in pre:
        if t <= end_k: pending[t].append((tg, o, amt))
        else: beyond[o] += amt
    me = dec['o']; other = init['enemy_n'] if me == init['player_n'] else init['player_n']
    start_owner = {n: o for n, (o, _) in base.items()}
    sample_at = {max(k0, end_k - d) for d in SAMPLES}; raws = []; adjs = []; raws3 = []; wp_early = None
    chain = chain_of(G, fid); skip = set(chain[1:])          # the chain's later legs belong to this move
    is_real = option is not None and option == (dec['tg'], dec['s'])
    triggers = collections.defaultdict(list)
    def launch_leg(k, s, tg, n, nxt):
        P[s][1] -= n
        Pf = {m: dict(o=P[m][0], x=geo[m][0], y=geo[m][1], r=geo[m][2]) for m in P}
        sx, sy, sr = geo[s]; tx, ty, _ = geo[tg]; d = math.hypot(tx - sx, ty - sy) or 1
        ft = features(Pf, s, tg, dec['o'], sx + sr * (tx - sx) / d, sy + sr * (ty - sy) / d, n)
        sch = schedule(ft)
        for dk, a in sch:
            t = max(k, k + dk + shift)
            if t <= end_k: pending[t].append((tg, dec['o'], a))
            else: beyond[dec['o']] += a
        if nxt is not None and sch:   # relaunch from the landing planet, the same gap after the first ships arrive
            triggers[max(k, k + sch[0][0] + shift) + F[nxt]['gap']].append(nxt)
    def launch(k):
        if option is None: return
        tg, n = option; s = dec['src']
        if P[s][0] != dec['o'] or n <= 0: return
        n = min(n, max(0, math.floor(P[s][1]))) if delay else n
        if n <= 0: return
        launch_leg(k, s, tg, n, dec.get('next') if is_real else None)
    for k in range(k0, end_k + 1):
        for n, p in P.items():
            if p[0] != NEU: p[1] += prodmap[n] / 50 * 0.1
        if delay and k == k0 + delay: launch(k)
        for g in triggers.pop(k, []):
            gf = F[g]; s = gf['src']
            if P[s][0] != dec['o']: continue
            avail = max(0.0, P[s][1]); n = min(math.floor(avail), max(1, round(gf['pct'] * avail))) if avail >= 1 else 0
            if n > 0: launch_leg(k, s, gf['tg'], n, gf.get('next'))
        for e in G['by'].get(k, []):
            if e['e'] != 'fs': continue
            f = F[e['id']]
            if e['id'] in skip: continue
            if e['id'] == fid:
                if not delay: launch(k)
                continue
            s = f['src']
            if P[s][0] != f['o']: continue
            avail = max(0.0, P[s][1]); n = min(math.floor(avail), max(1, round(f['pct'] * avail))) if avail >= 1 else 0
            if n <= 0: continue
            P[s][1] -= n; scale = n / f['s']
            for (t, tg, amt) in f['drops']:
                if t <= end_k: pending[t].append((tg, f['o'], amt * scale))
                else: beyond[f['o']] += amt * scale
            sent_dropped = sum(a for _, _, a in f['drops'])
            if sent_dropped < f['s'] - 0.5: beyond[f['o']] += (f['s'] - sent_dropped) * scale  # never landed in log
        for tg, o, a in pending.pop(k, []):
            p = P[tg]
            if o == p[0]: p[1] += a
            else:
                p[1] -= a
                if p[1] < 0: p[0] = o; p[1] = -p[1]
        if k == min(end_k, k0 + EARLY):
            infl = collections.Counter(beyond)
            for t, L in pending.items():
                for tg, o, a in L: infl[o] += a
            wp_early = wp_of({n: tuple(v) for n, v in P.items()}, infl, me, other, prodmap, geo, k)
        if k in sample_at:
            inflight = collections.Counter(beyond)
            for t, L in pending.items():
                for tg, o, a in L: inflight[o] += a
            now = {n: tuple(v) for n, v in P.items()}
            raws.append(wp_of(now, inflight, me, other, prodmap, geo, k))
            if ENSEMBLE: raws3.append(wp_of(now, inflight, me, other, prodmap, geo, k, 'v3'))
            adjs.append(wp_of(retake_adjust(now, start_owner, geo, prodmap, NEU), inflight, me, other, prodmap, geo, k))
    lost = frozenset(n for n, o in start_owner.items() if o == me and P[n][0] != me)
    return sum(raws) / len(raws), sum(adjs) / len(adjs), dict(early=wp_early, lost=lost), (sum(raws3) / len(raws3) if raws3 else None)

def options_for(G, fid):
    init = G['init']; f = G['fleets'][fid]; s = f['src']
    snapP = G['snap'][f['k']]
    geo = {p['n']: (p['x'], p['y']) for p in init['map']}
    sx, sy = geo[s]
    near = sorted((m for m in geo if m != s), key=lambda m: math.hypot(geo[m][0] - sx, geo[m][1] - sy))[:NTARGETS]
    if f['tg'] not in near: near.append(f['tg'])
    # ships available at the moment of the send (start of tick + production; earlier same-tick sends ignored)
    o, ships = snapP[s]; prod = next(p['prod'] for p in init['map'] if p['n'] == s)
    avail = ships + (prod / 50 * 0.1 if o != G['NEU'] else 0)
    real_pct = f['pct']
    pcts = sorted({0.25, 0.5, 0.75, 1.0, min(1.0, math.ceil(real_pct * 20 - 1e-9) / 20)})
    opts = [None]
    for tg in near:
        for p in pcts:
            n = min(math.floor(avail), math.ceil(p * avail - 1e-9))
            if n >= 1: opts.append((tg, n))
    real = (f['tg'], f['s'])
    if real not in opts: opts.append(real)
    return opts, real

# ---- great and brilliant (Phil's definitions, 2026-10-04) ----
GREAT_HOLD_DROP = 0.03   # holding must leave the player at least this much worse off than at the send
GREAT_OK = 0.02          # an option "holds the position" if it ends no more than this below the start
GREAT_MAX_OK = 2         # ... and at most this many options do
GREAT_DELAY = int(round(GREAT_WINDOW * 10))   # ticks: the same send made this much later (--great-window, default 1 s) ...
GREAT_LATE = 0.03        # ... must end at least this much worse (it had to be sent now)
BRILL_MARGIN = 0.10      # best option beats the median option by at least this
BRILL_END = 0.0          # a sacrifice must still end at least this far above holding
def exposes_source(G, fid, option):
    """True if the send leaves its source capturable by one enemy planet (all its ships, straight line at
    40.25 u/s, beating the ships left + production en route + 1) when it was not capturable before."""
    if option is None: return False
    f = G['fleets'][fid]; init = G['init']; s = f['src']; me = f['o']
    other = init['enemy_n'] if me == init['player_n'] else init['player_n']
    snap = G['snap'][f['k']]; geo = G['geo']; prod = G['prodmap'][s] / 50
    left_before = snap[s][1]; left_after = snap[s][1] - option[1]
    xs, ys, rs = geo[s]
    def capturable(left):
        for m, (o, sm) in snap.items():
            if o != other: continue
            xm, ym, rm = geo[m]; tau = max(0.0, math.hypot(xm - xs, ym - ys) - rs - rm) / SPEED
            if sm >= left + prod * tau + 1: return True
        return False
    return (not capturable(left_before)) and capturable(left_after)

def special_grade(g, loss, wps, real_w, best_w, start_w, sims, ens, real, G, fid, end_k, pre, row):
    """great = the only move, and it had to be now; brilliant = best, and it looks bad (a sacrifice)."""
    info = {o: L[len(L) // 2][2] for o, L in ens.items()}     # the on-time run of each option
    hold_w = sims[None][0]; ri, hi = info[real], info[None]
    # a "move" is a target choice: 25/50/75/100% to the same planet are one move
    ok_targets = {o[0] for o, w in sims.items() if o is not None and w[0] >= start_w - GREAT_OK}
    n_ok = len(ok_targets)
    late_w = simulate(G, fid, real, end_k, 0, pre, delay=GREAT_DELAY)[0]
    gave_up = sorted(ri['lost'] - hi['lost'])
    exposed = exposes_source(G, fid, real)
    row.update(n_hold_position=n_ok, wp_late_1s=round(late_w, 4), wp_real_2s=None if ri['early'] is None else round(ri['early'], 4),
               wp_hold_2s=None if hi['early'] is None else round(hi['early'], 4), gave_up_planets=' '.join(map(str, gave_up)),
               exposes_source=int(exposed))
    is_best = loss <= 0.005
    if is_best and best_w - float(np.median(wps)) >= BRILL_MARGIN and real_w >= hold_w + BRILL_END and gave_up:
        row['why'] = 'brilliant: gives up planet ' + ' '.join(map(str, gave_up)) + ' (holding would have kept it) and is still best'
        return 'brilliant'
    if (loss <= 0.02 and hold_w < start_w - GREAT_HOLD_DROP and real_w >= start_w - GREAT_OK
            and n_ok <= GREAT_MAX_OK and late_w <= real_w - GREAT_LATE):
        row['why'] = f'great: only {n_ok} target(s) hold the position, and sending {GREAT_WINDOW:g} s later is {real_w - late_w:.2f} worse'
        return 'great'
    row['why'] = ''
    return 'best' if g == 'brilliant' else g   # the old "brilliant" (only good move) is now covered by great

SEV = {'best': 0, 'great': 0, 'brilliant': 0, 'excellent': 1, 'good': 2, 'inaccuracy': 3, 'mistake': 4, 'blunder': 5}
GRADES = [('best', 0.005), ('excellent', 0.02), ('good', 0.05), ('inaccuracy', 0.10), ('mistake', 0.20), ('blunder', 9)]
def grade(loss, wps, real_wp, best_wp, is_hold):
    g = next(name for name, lim in GRADES if loss <= lim)
    if g == 'best' and not is_hold:
        med = float(np.median(wps)); close = sum(1 for w in wps if w >= best_wp - 0.02) / len(wps)
        if best_wp - med >= 0.10 and close <= 0.10: g = 'brilliant'
    return g

# ---------------------------------------------------------------- main
t0 = time.time()
ALL = list(games())
if MAXGAMES: ALL = ALL[:MAXGAMES]
print(f"EVALUATOR: {EVALUATOR}" + {'v3': f" ({EVAL_JSON}, trained on {_load_ev3().get('games', '?') if os.path.exists(EVAL_JSON) else '?'} games)",
      'both': f" (graded under v2 AND v3 [{EVAL_JSON}, trained on {_load_ev3().get('games', '?')} games]; mistakes/blunders only where they agree, 2+ steps apart = unclear)",
      'v2': " (shipped 2-feature logistic)"}[EVALUATOR])
print(f"{len(FILES)} file(s), {len(ALL)} game(s); horizon {HORIZON:g} s, {NTARGETS} nearest targets per send" + (f"; sends before {OPENING:g} s skipped" if OPENING > 0 else "; every send graded (opening = first 10 s, reported separately)"))
H = int(round(HORIZON * 10))
SETTLE = 30     # ticks (3 s) after the slowest option's last ship lands
MAXSPAN = 250   # never simulate more than 25 s past the send
SHIFTS = (-2, 0, 2)   # the option's landings are tried 0.2 s early, on time and 0.2 s late (landing-model error)
SIM_GATE = 0.15       # if the real send, simulated forward, ends more than this far (WP) from what actually
                      # happened, the simulation is wrong for this send: graded 'unclear' (reason sim_vs_reality).
                      # On the 51-game run this caught 35% of blunders and raised the outcome test 70% -> 79%
UNCLEAR = 0.15        # if the real send's or the best option's WP moves more than this across those timings,
                      # the outcome hinges on a tick: graded 'unclear' and left out of the stats
rows = []; n_opening = 0; n_chained = 0
for gi, (init, ev) in enumerate(ALL):
    G = prepare(init, ev); names = {init['player_n']: init['player_name'], init['enemy_n']: init['enemy_name']}
    prodmap = {p['n']: p['prod'] for p in init['map']}
    for fid in G['decisions']:
        f = G['fleets'][fid]
        if f['o'] not in names: continue
        if f['k'] < OPENING * 10: n_opening += 1; continue
        if 'prev' in f: n_chained += 1; continue      # graded as part of the move that started the chain
        opts, real = options_for(G, fid)
        # window: at least the horizon, and long enough for every option to have landed + SETTLE s
        geo = {p['n']: (p['x'], p['y'], p['r']) for p in init['map']}
        Pf = {m: dict(o=o, x=geo[m][0], y=geo[m][1], r=geo[m][2]) for m, (o, _) in G['snap'][f['k']].items()}
        sx, sy, sr = geo[f['src']]; longest = 0
        for o in opts:
            if o is None: continue
            tx, ty, _ = geo[o[0]]; d = math.hypot(tx - sx, ty - sy) or 1
            longest = max(longest, K(predict(features(Pf, f['src'], o[0], f['o'], sx + sr * (tx - sx) / d, sy + sr * (ty - sy) / d, o[1]))[1]))
        span = min(max(H, longest + SETTLE), MAXSPAN)
        end_k = min(f['k'] + span - 1, G['last_k'])
        if end_k <= f['k']: continue
        pre = prelaunched(G, f['k'])
        ens = {o: [simulate(G, fid, o, end_k, sh, pre) for sh in SHIFTS] for o in opts}
        sims = {o: (float(np.mean([v[0] for v in L])), float(np.mean([v[1] for v in L]))) for o, L in ens.items()}
        spread = {o: max(v[0] for v in L) - min(v[0] for v in L) for o, L in ens.items()}
        other = init['enemy_n'] if f['o'] == init['player_n'] else init['player_n']
        true_w = wp_of(G['true_end'][end_k], G['inflight_end'][end_k], f['o'], other, prodmap, G['geo'], end_k)
        start_w = wp_of(G['snap'][f['k']], G['inflight_end'].get(f['k'] - 1, {}), f['o'], other, prodmap, G['geo'], f['k'])
        ch = chain_of(G, fid)
        route = '>'.join([str(f['src']), str(f['tg'])] + [str(G['fleets'][c]['tg']) for c in ch[1:]])
        row = dict(game=init['session'], t=f['k'] / 10, player=names[f['o']], won=int(f['o'] == G['winner']),
                   source=f['src'], ships=f['s'], pct=round(f['pct'], 3), target=f['tg'], route=route, legs=len(ch), options=len(opts),
                   wp_start=round(start_w, 4), wp_true_at_horizon=round(true_w, 4), horizon_s=(end_k - f['k'] + 1) / 10)
        for tag, idx in (('', 0), ('adj_', 1)):     # default grade = raw; adj_ = with the one-move retake check
            res = [(o, w[idx]) for o, w in sims.items()]
            wps = [w for _, w in res]; best_o, best_w = max(res, key=lambda r: r[1])
            real_w = sims[real][idx]; loss = max(0.0, best_w - real_w)
            g = grade(loss, wps, real_w, best_w, False)
            if tag == '':
                row['base_grade'] = 'best' if g == 'brilliant' else g
                g = special_grade(g, loss, wps, real_w, best_w, start_w, sims, ens, real, G, fid, end_k, pre, row)
            if tag == '' and (spread[real] > UNCLEAR or spread[best_o] > UNCLEAR): g = 'unclear'
            row.update({tag + 'wp_real': round(real_w, 4), tag + 'wp_best': round(best_w, 4), tag + 'wp_hold': round(sims[None][idx], 4),
                        tag + 'best_target': 'hold' if best_o is None else best_o[0], tag + 'best_ships': 0 if best_o is None else best_o[1],
                        tag + 'loss': round(loss, 4), tag + 'grade': g})
        if ENSEMBLE:       # the same simulated options, scored by the second evaluator
            sims3 = {o: float(np.mean([v[3] for v in L])) for o, L in ens.items()}
            true3 = wp_of(G['true_end'][end_k], G['inflight_end'][end_k], f['o'], other, prodmap, G['geo'], end_k, 'v3')
            start3 = wp_of(G['snap'][f['k']], G['inflight_end'].get(f['k'] - 1, {}), f['o'], other, prodmap, G['geo'], f['k'], 'v3')
            best_o3, best_w3 = max(sims3.items(), key=lambda r: r[1]); real_w3 = sims3[real]; loss3 = max(0.0, best_w3 - real_w3)
            g3 = grade(loss3, list(sims3.values()), real_w3, best_w3, False); g3 = 'best' if g3 == 'brilliant' else g3
            row.update(v3_wp_start=round(start3, 4), v3_wp_real=round(real_w3, 4), v3_wp_best=round(best_w3, 4), v3_wp_hold=round(sims3[None], 4),
                       v3_best_target='hold' if best_o3 is None else best_o3[0], v3_best_ships=0 if best_o3 is None else best_o3[1],
                       v3_loss=round(loss3, 4), v3_grade=g3, v3_sim_err=round(abs(real_w3 - true3), 4))
        row['timing_spread_real'] = round(spread[real], 4); row['timing_spread_best'] = round(spread[best_o], 4)
        # sim-vs-reality gate: the real send simulated forward must land near what actually happened
        row['sim_err'] = round(abs(row['wp_real'] - true_w), 4); row['grade_before_gate'] = row['grade']; row['unclear_reason'] = ''
        if row['grade'] == 'unclear': row['unclear_reason'] = 'timing'
        elif row['sim_err'] > SIM_GATE: row['grade'] = 'unclear'; row['unclear_reason'] = 'sim_vs_reality'
        row['phase'] = 'opening' if f['k'] < 100 else 'midgame'
        row['confidence'] = 'low' if f['k'] < 100 else 'normal'     # first 10 s: the evaluator is weakest there (AUC ~0.7)
        row['why_demoted'] = ''
        if ENSEMBLE and row['grade'] != 'unclear':
            # a grade only stands if the second evaluator agrees with it
            g2 = row['grade']
            if g2 in ('great', 'brilliant'):
                kept = row['v3_loss'] <= 0.02 and row['v3_wp_real'] - row['v3_wp_hold'] >= (GREAT_HOLD_DROP if g2 == 'great' else BRILL_END)
                if not kept: row['grade'] = row['base_grade']; row['why'] = ''; row['why_demoted'] = f'{g2} under v2 only'
            if row['grade'] not in ('great', 'brilliant'):
                s2, s3 = SEV[row['grade']], SEV[row['v3_grade']]
                if abs(s2 - s3) >= 2: row['grade'] = 'unclear'; row['unclear_reason'] = 'evaluators_disagree'
                elif s3 < s2: row['grade'] = row['v3_grade']          # both must agree it is at least this bad: the milder verdict stands
        row['ens_grade'] = row['grade']
        rows.append(row)
    done = gi + 1
    el = time.time() - t0
    print(f"  game {done}/{len(ALL)} {init['session']}: {len(G['decisions'])} sends graded  ({el:.0f} s elapsed, ~{el / done * (len(ALL) - done):.0f} s left)", flush=True)

if not rows: sys.exit("no sends graded")
with open('grade_moves_decisions.csv', 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

order = ['brilliant', 'great', 'best', 'excellent', 'good', 'inaccuracy', 'mistake', 'blunder']
allrows = rows; unclear = [r for r in rows if r['grade'] == 'unclear']; rows = [r for r in rows if r['grade'] != 'unclear']
uc = collections.Counter(r['unclear_reason'] for r in unclear)
print(f"\n{len(unclear)} of {len(allrows)} sends ({100 * len(unclear) / max(1, len(allrows)):.1f}%) graded 'unclear', left out below:"
      f" {uc['timing']} because the outcome flips with 0.2 s of landing timing, {uc['sim_vs_reality']} because the simulated real send"
      f" ended > {SIM_GATE} WP from what actually happened" + (f", {uc['evaluators_disagree']} because the two evaluators disagree by 2+ grade steps" if ENSEMBLE else ""))
if ENSEMBLE:
    _g = [r for r in rows if r['grade'] != 'unclear']
    print(f"Evaluator agreement: {sum(1 for r in _g if r['v3_grade'] == r['grade'])} of {len(_g)} kept grades equal the v3 grade; "
          f"{sum(1 for r in rows if r['why_demoted'])} great/brilliant dropped back to the base grade because v3 did not agree")
    print(f"  mistakes+blunders kept: {sum(1 for r in _g if r['grade'] in ('mistake', 'blunder'))}  (v2 alone said "
          f"{sum(1 for r in _g if r['base_grade'] in ('mistake', 'blunder'))} for the same sends, v3 alone {sum(1 for r in _g if r['v3_grade'] in ('mistake', 'blunder'))})")
def gradeline(R):
    c = collections.Counter(r['grade'] for r in R); n = len(R)
    return "  ".join(f"{g} {100 * c[g] / n:4.1f}%" for g in order)
if n_opening: print(f"\nSkipped {n_opening} sends before {OPENING:g} s.")
print(f"{n_chained} relaunches were graded as later legs of a chain (staging / tunnelling through an own planet);"
      f" {sum(1 for r in allrows if r['legs'] > 1)} graded moves are chains")
print(f"Graded {len(rows)} sends.  Overall:  {gradeline(rows)}")
print(f"  with retake check:  " + "  ".join(f"{g} {100 * sum(1 for r in rows if r['adj_grade'] == g) / len(rows):4.1f}%" for g in order))
print(f"  mean loss per send {np.mean([r['loss'] for r in rows]):.4f} WP")

# players
P = collections.defaultdict(list)
for r in rows: P[r['player']].append(r)
prow = []
print("\nBy player (players with >= 50 graded sends):")
for name, R in sorted(P.items(), key=lambda kv: -len(kv[1])):
    c = collections.Counter(r['grade'] for r in R)
    prow.append(dict(player=name, sends=len(R), games=len({r['game'] for r in R}), mean_loss=round(np.mean([r['loss'] for r in R]), 4),
                     **{g: c[g] for g in order}))
    if len(R) >= 50: print(f"  {name:<18} sends {len(R):5d}  mean loss {np.mean([r['loss'] for r in R]):.4f}   {gradeline(R)}")
with open('grade_moves_players.csv', 'w', newline='') as fh:
    w = csv.DictWriter(fh, fieldnames=list(prow[0])); w.writeheader(); w.writerows(prow)

# A. fidelity
print("\nA. Fidelity (real send simulated forward vs what actually happened, WP at the horizon):")
d_sim = np.array([r['wp_real'] - r['wp_start'] for r in rows]); d_true = np.array([r['wp_true_at_horizon'] - r['wp_start'] for r in rows])
err = np.abs(np.array([r['wp_real'] for r in rows]) - np.array([r['wp_true_at_horizon'] for r in rows]))
print(f"  mean |WP sim - WP actual| {err.mean():.3f}  (median {np.median(err):.3f}, P90 {np.quantile(err, .9):.3f})")
print(f"  correlation of WP change over the horizon, sim vs actual: {np.corrcoef(d_sim, d_true)[0, 1]:.3f}")
print(f"  mean loss per send {np.mean([r['loss'] for r in rows]):.4f} must be well above the sim error on WP changes for grades to mean much")

# B2. clustering check
bl = sorted([r for r in rows if r['grade'] == 'blunder'], key=lambda r: (r['game'], r['player'], r['t']))
cl = sum(1 for a, b in zip(bl, bl[1:]) if a['game'] == b['game'] and a['player'] == b['player'] and b['t'] - a['t'] <= 2)
print(f"\nBlunders within 2 s of the same player's previous blunder: {cl}/{max(1, len(bl))} ({100 * cl / max(1, len(bl)):.0f}%)  (51-game run before this fix: 49%)")

# B. outcome
print("\nB. Outcome: does the winner lose less WP per send than the loser?  (pre-registered bar: >= 60% of games;")
print("   keep this robust version if it is >= 70%, the previous 51-game run's figure)")
for tag, lbl in (('', 'raw (default)'), ('adj_', 'with retake check')):
    G2 = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in rows: G2[r['game']][r['won']].append(r[tag + 'loss'])
    both = [(np.mean(v[1]), np.mean(v[0])) for v in G2.values() if v[1] and v[0]]
    wins = sum(1 for a, b in both if a < b)
    mbw = np.mean([sum(1 for r in rows if r['game'] == g and r['won'] == 1 and r[tag + 'grade'] in ('mistake', 'blunder')) for g in G2])
    mbl = np.mean([sum(1 for r in rows if r['game'] == g and r['won'] == 0 and r[tag + 'grade'] in ('mistake', 'blunder')) for g in G2])
    print(f"  {lbl:<28} winner lower in {wins}/{len(both)} games ({100 * wins / max(1, len(both)):.0f}%);  mistakes+blunders per game: winner {mbw:.1f}, loser {mbl:.1f}")

print("\nB by phase (raw grades): opening = sends in the first 10 s, midgame = the rest")
for ph in ('opening', 'midgame'):
    R = [r for r in rows if r['phase'] == ph]
    G2 = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in R: G2[r['game']][r['won']].append(r['loss'])
    both = [(np.mean(v[1]), np.mean(v[0])) for v in G2.values() if v[1] and v[0]]
    wins = sum(1 for a, b in both if a < b)
    print(f"  {ph:<8} sends {len(R):5d}  {gradeline(R) if R else ''}")
    print(f"           winner lower in {wins}/{len(both)} games ({100 * wins / max(1, len(both)):.0f}%)  (below 60% = these grades don't track who wins; don't trust them)")

print("\nBiggest blunders (game, time, player, real send -> best option):")
for r in sorted(rows, key=lambda r: -r['loss'])[:10]:
    print(f"  {r['game']} t={r['t']:6.1f}s {r['player']:<16} {r['ships']:4d} ships {r['source']}->{r['target']}  best: {r['best_ships']} -> {r['best_target']}   loss {r['loss']:.3f}")
br = [r for r in rows if r['grade'] == 'brilliant']
print(f"\nGreat sends ({sum(1 for r in rows if r['grade'] == 'great')}):")
for r in sorted([r for r in rows if r['grade'] == 'great'], key=lambda r: r['wp_hold'] - r['wp_real'])[:10]:
    print(f"  {r['game']} t={r['t']:6.1f}s {r['player']:<16} {r['ships']:4d} ships {r['source']}->{r['target']}  WP start {r['wp_start']:.3f}  real {r['wp_real']:.3f}  hold {r['wp_hold']:.3f}  1 s later {r['wp_late_1s']:.3f}")
print(f"\nBrilliant sends ({len(br)}):")
for r in sorted(br, key=lambda r: -(r['wp_best'] - r['wp_hold']))[:10]:
    print(f"  {r['game']} t={r['t']:6.1f}s {r['player']:<16} {r['ships']:4d} ships {r['source']}->{r['target']}  WP {r['wp_start']:.3f} -> {r['wp_real']:.3f} (hold {r['wp_hold']:.3f})  {r['why']}")
print(f"\nwrote grade_moves_decisions.csv, grade_moves_players.csv   ({time.time() - t0:.0f} s)")
