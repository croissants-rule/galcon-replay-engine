#!/usr/bin/env python3
"""
analyze_replay.py -- validate geometry_engine.predict_transit() against a
real match replay (mod1.lua / galcon.py's .jsonl session format), and
(as the same code path) sweep every planet pair on the map for the
map-wide predictor.

Replay format (one JSON object per line):
  {"type": "init", "map": [{"x","y","r","prod","owner","ships","n"}, ...],
   "w", "h", ...}
  {"type": "chunk", "chunk": N, "events": [...], "pos": [[t, id, x, y, 0], ...]}

IMPORTANT: this is a per-tick POLLING recorder (mod1.lua, ~line 2744),
not a launch/arrival log:
  - "fs": a fleet id seen for the first time this tick (o, tg, x, y, s, rem, t)
    -- x,y is its LAUNCH position (the source planet's surface, offset
       from center by its own radius toward the target -- verified
       empirically).
  - "fr": that fleet's TARGET CHANGED since last tick (id, tg, t) -- a
    mid-flight REDIRECT, not an arrival. A fleet can redirect any
    number of times before it finally lands.
  - "fu": that fleet's ship count changed since last tick (id, s, t).
  - "fd": the fleet id is no longer found this tick -- it arrived or was
    destroyed (id, tg, o, t) -- tg/o are its state just before vanishing.
  - "pos": EVERY currently-alive fleet's (t, id, x, y, 0) is logged every
    tick, regardless of event -- full per-tick trajectory data.

Because targets can change mid-flight, a fleet's lifetime (fs ... fd) is
segmented into LEGS at each redirect: each leg is a straight run at one
target, bounded by two consecutive boundary events (fs/fr/fd) for that
id, with its start/end position read from the `pos` stream. This is the
unit of analysis here -- NOT the whole fs-to-fd lifetime, which may
span several different targets.
"""

import sys
import json
import math
import csv
import statistics

sys.path.insert(0, "/home/claude")
from geometry_engine import Obstacle, predict_transit, obstacles_along_path


def load_replay(path):
    """A .jsonl file can hold ONE game (a bare init + chunks) or, for a
    "BATCH_*" file, MANY games concatenated back to back (batch_header,
    then repeated game_divider/init/chunk... blocks, one per game -- each
    with its OWN planet layout even when the arena's w/h repeat). Every
    "init" starts a new game; chunks belong to whichever init most
    recently preceded them. Returns a list of per-game dicts so callers
    never pool one game's fleet events against another game's map."""
    games = []
    current = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            if obj["type"] == "init":
                current = dict(init=obj, events=[], pos=[])
                games.append(current)
            elif obj["type"] == "chunk" and current is not None:
                current["events"].extend(obj.get("events", []))
                pos = obj.get("pos")
                if isinstance(pos, list):
                    current["pos"].extend(pos)
    if not games:
        raise ValueError(f"{path}: no init record found")
    return games


def get_map_size(init):
    return init.get("w"), init.get("h")


def build_planets(init):
    planets = {}
    for p in init["map"]:
        planets[p["n"]] = dict(x=p["x"], y=p["y"], prod=p["prod"], r=p["r"])
    return planets


def _dedupe_ticks(samples):
    """samples: list of (t,x,y). mod1.lua's pos log emits several
    sub-tick duplicate records for the same ~0.1s tick (confirmed
    empirically: a single "t=56.30" tick can appear 5-6 times with
    slightly different coordinates before settling -- likely intra-tick
    render/interpolation noise, not real motion). Bucket to the nearest
    0.1s tick and keep the LAST record in each bucket so a stall test
    sees one point per real simulation tick instead of being swamped by
    that jitter."""
    buckets = {}
    for t, x, y in samples:
        buckets[round(t, 1)] = (t, x, y)
    return sorted(buckets.values())


def _max_stall_duration(samples, dist_thresh=15.0):
    """Longest sub-interval of `samples` (sorted, deduped (t,x,y)) during
    which the fleet never moved more than dist_thresh away from where
    that sub-interval started -- i.e. the longest stretch of near-zero
    NET progress, regardless of how much raw path length it covered
    while doing so (so genuine circling/jittering in place counts, not
    just literally standing still). Two-pointer over time-sorted points:
    as the right edge j advances, drop the left edge i forward past any
    point the fleet has since moved dist_thresh away from.

    Calibrated against 5 legs with a known ground truth from a replay
    video (see STUCK_SHIPS_MAX/STUCK_CLEARANCE_MAX below): the 3
    confirmed stuck-pathing legs (44610, 44777, 48864) all measured
    max_stall_duration 3.2-3.7s; two superficially similar
    redirected-away legs with normal transit (48859, 48612) measured
    only 1.0-1.3s. STALL_DUR_MIN is set between those two clusters."""
    if len(samples) < 2:
        return 0.0
    best = 0.0
    i = 0
    for j in range(len(samples)):
        tj, xj, yj = samples[j]
        while True:
            ti, xi, yi = samples[i]
            if math.hypot(xj - xi, yj - yi) <= dist_thresh:
                break
            i += 1
        best = max(best, tj - samples[i][0])
    return best


def find_planet_at(planets, x, y, tol=5.0):
    """The point sits on some planet's surface: |dist(center,pt) - r| ~ 0.
    Returns the closest such planet id within tol, else None."""
    best_id, best_resid = None, None
    for pid, p in planets.items():
        d = math.hypot(p["x"] - x, p["y"] - y)
        resid = abs(d - p["r"])
        if best_resid is None or resid < best_resid:
            best_resid, best_id = resid, pid
    if best_resid is not None and best_resid <= tol:
        return best_id
    return None


def build_legs(planets, events, pos):
    # per-id boundary list: (t, kind, tg)
    boundaries = {}
    fu_times = {}
    for e in events:
        if e["e"] == "fu":
            fu_times.setdefault(e["id"], []).append(e["t"])
        if e["e"] not in ("fs", "fr", "fd"):
            continue
        boundaries.setdefault(e["id"], []).append((e["t"], e["e"], e.get("tg")))
        if e["e"] == "fs":
            # fs carries its own position and initial ship count -- stash
            # both for exact lookup
            boundaries[e["id"]][-1] = (e["t"], e["e"], e.get("tg"), (e["x"], e["y"]), e.get("s"))

    pos_by_id = {}
    for t, fid, x, y, _ in pos:
        pos_by_id.setdefault(fid, []).append((t, x, y))
    for fid in pos_by_id:
        pos_by_id[fid].sort(key=lambda r: r[0])

    def pos_at(fid, t, exact_xy=None, tol=0.35):
        if exact_xy is not None:
            return exact_xy
        samples = pos_by_id.get(fid)
        if not samples:
            return None
        best = min(samples, key=lambda r: abs(r[0] - t))
        if abs(best[0] - t) <= tol:
            return (best[1], best[2])
        return None

    legs = []
    skipped_no_pos = 0
    for fid, blist in boundaries.items():
        blist.sort(key=lambda b: b[0])
        for a, b in zip(blist, blist[1:]):
            t0, kind0, tg0 = a[0], a[1], a[2]
            exact0 = a[3] if len(a) > 3 else None
            ships0 = a[4] if len(a) > 4 else None
            t1 = b[0]
            if tg0 is None or t1 <= t0:
                continue
            p0 = pos_at(fid, t0, exact_xy=exact0)
            p1 = pos_at(fid, t1)
            if p0 is None or p1 is None:
                skipped_no_pos += 1
                continue
            contested = any(t0 < t <= t1 for t in fu_times.get(fid, []))
            end_kind = b[1]  # "fd" = this leg ended in arrival/destruction,
                              # "fr" = the fleet was redirected away before
                              # reaching tg0 -- it never actually landed on
                              # the target this leg's distance/speed was
                              # measured toward.
            leg_samples = _dedupe_ticks([
                (t, x, y) for (t, x, y) in pos_by_id.get(fid, ())
                if t0 - 0.05 <= t <= t1 + 0.05
            ])
            max_stall_dur = _max_stall_duration(leg_samples)
            legs.append(dict(
                id=fid, tgt_id=tg0,
                t0=t0, t1=t1,
                x0=p0[0], y0=p0[1], x1=p1[0], y1=p1[1],
                contested=contested,
                start_kind=kind0,  # "fs" = clean launch, "fr" = mid-flight redirect
                end_kind=end_kind,
                ships_sent=ships0,  # only known for "fs"-started legs
                max_stall_dur=max_stall_dur,
            ))
    return legs, skipped_no_pos


def main():
    if len(sys.argv) < 2:
        print("usage: analyze_replay.py <replay.jsonl> [more replays...] [--csv out.csv]")
        sys.exit(1)

    csv_path = None
    paths = []
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--csv":
            csv_path = args[i + 1]
            i += 2
        else:
            paths.append(args[i])
            i += 1

    all_legs = []
    for path in paths:
        games = load_replay(path)
        total_legs = 0
        total_skipped = 0
        for gi, game in enumerate(games):
            planets = build_planets(game["init"])
            map_w, map_h = get_map_size(game["init"])
            legs, skipped_no_pos = build_legs(planets, game["events"], game["pos"])
            total_legs += len(legs)
            total_skipped += skipped_no_pos
            replay_label = path if len(games) == 1 else f"{path}#game{gi + 1}"
            for leg in legs:
                leg["_planets"] = planets
                leg["_replay"] = replay_label
                leg["_w"] = map_w
                leg["_h"] = map_h
            all_legs.extend(legs)
        game_note = f", {len(games)} games in this file" if len(games) > 1 else ""
        print(f"{path}: {total_legs} legs built across {len(games)} game(s){game_note} "
              f"({total_skipped} skipped for missing position data)")

    if not all_legs:
        print("No legs built.")
        return

    # --- Distance/duration filter + geometry per leg ---
    # mod1.lua rounds fleet positions to integers and timestamps to ~0.1s
    # ticks (see line ~2747: round(f.position_x)/round(f.position_y)).
    # That's negligible noise over a long leg but dominates a short one --
    # e.g. a 3-tick, 20u leg can show 2-3x its real speed just from
    # rounding. Require enough distance/time for quantization error to
    # wash out (checked empirically: every extreme outlier in an
    # unfiltered run had dist<40u and dur<0.5s).
    MIN_DIST = 60.0
    MIN_DUR = 2.0

    # Confirmed via a screen recording of BATCH_starcoinsvshimon (legs
    # 44610/44777, ships_sent=1, clearance -17.9u/-11.1u against a
    # radius-21 obstacle): a 1-ship fleet can get caught literally
    # orbiting an obstacle's collision edge for several seconds before
    # escaping -- visibly circling the rim, not just flying slower. This
    # is NOT a smooth function of clearance or fleet size (most ships=1
    # legs at similarly deep clearance in the same file flew at normal
    # speed, ~33-35u/s) -- it's a sporadic collision-avoidance pathing
    # bug that happens to hit low-ship-count fleets harder, since a
    # multi-ship swarm has enough spread/redundancy to route around a
    # local minimum that traps a lone ship. No smooth geometry model
    # (this one included) should be expected to predict a stuck-pathing
    # glitch, so these legs are pulled out of the fitting/error stats
    # the same way contested and redirect-started legs already are --
    # not because the model is wrong here, but because this isn't the
    # phenomenon the model describes.
    STUCK_SHIPS_MAX = 3        # ships_sent at/below this counts as a low-ship-count fleet
    STUCK_CLEARANCE_MAX = -10.0  # nearest obstacle's clearance must be at least this deep

    # Direct, trajectory-based detector -- catches the bug from its
    # SYMPTOM (the fleet's own position stream shows it stalled in place
    # for a while) rather than inferring risk from static obstacle
    # geometry. This matters because the geometry heuristic above can
    # only ever see stalls caused by an obstacle blocking the path (it
    # excludes the SOURCE planet from the obstacle set, since a fleet
    # starts on its surface) -- but leg 48864 (BATCH_starcoinsvshimon
    # game7, src=planet#19, min_clearance=+8.1 i.e. barely any obstacle
    # interference at all) showed the exact same signature happening
    # right at LAUNCH: 3.8s stalled in a ~15x15u box near its own source
    # planet, then a normal-speed straight run for the rest of the leg.
    # See _max_stall_duration()'s docstring for the calibration numbers.
    STALL_DUR_MIN = 2.0

    # diagnostic: show the raw dist/dur distribution (uncontested legs
    # only) before filtering, so the thresholds above can be sanity
    # checked against real data instead of picked blind.
    uncontested_dd = [
        (math.hypot(leg["x1"] - leg["x0"], leg["y1"] - leg["y0"]), leg["t1"] - leg["t0"])
        for leg in all_legs if not leg.get("contested")
    ]
    if uncontested_dd:
        dists = sorted(d for d, _ in uncontested_dd)
        durs = sorted(t for _, t in uncontested_dd)

        def pct(sorted_vals, p):
            idx = min(len(sorted_vals) - 1, int(p * len(sorted_vals)))
            return sorted_vals[idx]

        print(f"\nuncontested leg distance percentiles (u): "
              f"p10={pct(dists,.10):.1f} p25={pct(dists,.25):.1f} p50={pct(dists,.50):.1f} "
              f"p75={pct(dists,.75):.1f} p90={pct(dists,.90):.1f}")
        print(f"uncontested leg duration percentiles (s): "
              f"p10={pct(durs,.10):.2f} p25={pct(durs,.25):.2f} p50={pct(durs,.50):.2f} "
              f"p75={pct(durs,.75):.2f} p90={pct(durs,.90):.2f}")

    # Group EVERY leg (pre-filtering) by (replay, fleet id) so a leg that
    # ends in a redirect can look at that same fleet's later history --
    # needed to tell apart the three "redirected away" cases Phil spotted
    # in the replay viewer:
    #   Case A: fleet partially lands, remainder redirects -- the partial
    #           landing changes ship count mid-leg, so this is already an
    #           "fu" event and already caught by the existing "contested"
    #           filter below; nothing new needed for it.
    #   Case B: fleet redirects almost exactly at the target's edge --
    #           essentially a completed transit, just labeled "fr"
    #           instead of "fd". Flagged below as near_arrival_abort.
    #   Case C: fleet redirects away, then redirects again LATER back
    #           onto the same original target. The leg we keep (the
    #           fs-to-first-fr segment) is a real, valid partial-path
    #           measurement up to wherever that first redirect happened --
    #           it didn't "fail" the transit, it just got interrupted.
    #           Flagged below as returns_later.
    legs_by_fleet = {}
    for leg in all_legs:
        legs_by_fleet.setdefault((leg["_replay"], leg["id"]), []).append(leg)
    for group in legs_by_fleet.values():
        group.sort(key=lambda l: l["t0"])

    rows = []
    stuck_risk_rows = []
    n_contested_skipped = 0
    n_redirect_skipped = 0
    n_stuck_risk_skipped = 0
    for leg in all_legs:
        if leg.get("contested"):
            n_contested_skipped += 1
            continue
        if leg.get("start_kind") != "fs":
            # A leg starting at a mid-flight redirect ("fr") carries the
            # fleet's deceleration/reacceleration from that turn -- a real
            # player-initiated velocity change the geometry model has no
            # way to see or predict (confirmed: redirects can happen at
            # any time, for any reason). Only clean launches ("fs") are
            # valid tests of the terrain-slowdown model.
            n_redirect_skipped += 1
            continue
        planets = leg["_planets"]
        tgt = planets.get(leg["tgt_id"])
        if tgt is None:
            continue
        dist = math.hypot(leg["x1"] - leg["x0"], leg["y1"] - leg["y0"])
        dur = leg["t1"] - leg["t0"]
        if dist < MIN_DIST or dur < MIN_DUR:
            continue
        speed = dist / dur

        exclude_id = find_planet_at(planets, leg["x0"], leg["y0"])
        obstacles = [
            Obstacle(x=p["x"], y=p["y"], prod=p["prod"], id=pid)
            for pid, p in planets.items()
            if pid != leg["tgt_id"] and pid != exclude_id
        ]
        on_path = obstacles_along_path(obstacles, (leg["x0"], leg["y0"]), (tgt["x"], tgt["y"]))
        min_clearance = min((o.clearance for o in on_path), default=None)

        ships_sent = leg.get("ships_sent")
        max_stall_dur = leg.get("max_stall_dur", 0.0)
        trajectory_stall = max_stall_dur >= STALL_DUR_MIN
        geometry_stuck = (
            ships_sent is not None and ships_sent <= STUCK_SHIPS_MAX
            and min_clearance is not None and min_clearance <= STUCK_CLEARANCE_MAX
        )
        # Tested trajectory_stall alone as the sole exclusion criterion
        # (dropping geometry_stuck): it made the fit WORSE (local sample:
        # MAE 7.51% -> 8.99%), because the geometry-flagged legs that
        # DON'T hit the >=2.0s hard-stall threshold aren't false
        # positives -- they show a continuum of shorter stalls (0.6-1.7s
        # observed, no gap right below the threshold) and still fit
        # meaningfully worse than clean legs (MAE 12.70% vs 7.51% on that
        # sample). So this isn't a binary bug with a clean cutoff; a
        # partial/shorter obstacle-interaction slowdown is real too, just
        # milder. Keep the union until that continuum itself is modeled.
        stuck_risk = trajectory_stall or geometry_stuck
        if trajectory_stall and geometry_stuck:
            stuck_risk_reason = "both"
        elif trajectory_stall:
            stuck_risk_reason = "trajectory"
        elif geometry_stuck:
            stuck_risk_reason = "geometry"
        else:
            stuck_risk_reason = None

        near_arrival_abort = None
        returns_later = None
        if leg.get("end_kind") == "fr":
            dist_to_target = math.hypot(tgt["x"] - leg["x0"], tgt["y"] - leg["y0"])
            frac_covered = (dist / dist_to_target) if dist_to_target > 0 else None
            near_arrival_abort = frac_covered is not None and frac_covered >= 0.85
            group = legs_by_fleet.get((leg["_replay"], leg["id"]), [])
            returns_later = any(
                g["t0"] > leg["t1"] and g["tgt_id"] == leg["tgt_id"]
                for g in group
            )

        row = dict(
            replay=leg["_replay"], id=leg["id"], tgt=leg["tgt_id"],
            x0=leg["x0"], y0=leg["y0"], x1=leg["x1"], y1=leg["y1"],
            t0=leg["t0"], t1=leg["t1"],
            w=leg.get("_w"), h=leg.get("_h"),
            ships_sent=ships_sent,
            dist=dist, dur=dur, speed=speed,
            n_obstacles=len(on_path), min_clearance=min_clearance,
            end_kind=leg.get("end_kind"),
            near_arrival_abort=near_arrival_abort,
            returns_later=returns_later,
            max_stall_dur=max_stall_dur,
            stuck_risk_reason=stuck_risk_reason,
            obstacles=obstacles, planets=planets,
        )
        if stuck_risk:
            n_stuck_risk_skipped += 1
            stuck_risk_rows.append(row)
        else:
            rows.append(row)

    print(f"\n{n_contested_skipped} legs skipped as contested (ship count changed mid-leg -- combat)")
    print(f"{n_redirect_skipped} legs skipped as redirect-started (velocity change from turning mid-flight, "
          f"not terrain -- unmodelable)")
    print(f"{n_stuck_risk_skipped} legs skipped as stuck-pathing risk (trajectory stalled >={STALL_DUR_MIN:.1f}s "
          f"in place, and/or ships_sent<={STUCK_SHIPS_MAX} near an obstacle with clearance<={STUCK_CLEARANCE_MAX:.0f}u "
          f"-- confirmed via replay video to be a collision-avoidance pathing bug, not terrain slowdown; "
          f"see worst-case detail below)")
    print(f"{len(rows)} legs pass the distance/duration filter "
          f"(dist>={MIN_DIST}u, dur>={MIN_DUR}s)")

    clear = [r for r in rows if r["n_obstacles"] == 0]
    print(f"{len(clear)} of those have a clear (unobstructed) path -- used to calibrate baseline_speed")

    if not clear:
        print("No clear-path legs to calibrate against -- aborting.")
        return

    speeds = [r["speed"] for r in clear]
    baseline_speed = statistics.median(speeds)
    sd = statistics.stdev(speeds) if len(speeds) > 1 else 0.0
    cv = sd / baseline_speed if baseline_speed else float("inf")
    print(f"baseline_speed = {baseline_speed:.3f} (median, n={len(speeds)}, "
          f"mean={statistics.mean(speeds):.3f}, sd={sd:.3f}, cv={cv:.4f})")

    # --- Evaluate predict_transit on every leg ---
    results = []
    for r in rows:
        tgt = r["planets"][r["tgt"]]
        pred = predict_transit(r["obstacles"], (r["x0"], r["y0"]), (tgt["x"], tgt["y"]), baseline_speed)
        actual_pct = 100.0 * r["speed"] / baseline_speed
        w, h = r.get("w"), r.get("h")
        edge_dist = None
        if w and h:
            edge_dist = min(r["x0"], w - r["x0"], r["y0"], h - r["y0"],
                             r["x1"], w - r["x1"], r["y1"], h - r["y1"])
        results.append(dict(
            replay=r["replay"], id=r["id"], tgt=r["tgt"],
            x0=r["x0"], y0=r["y0"], x1=r["x1"], y1=r["y1"], w=w, h=h,
            edge_dist=edge_dist, ships_sent=r.get("ships_sent"),
            dist=r["dist"], dur=r["dur"],
            n_obstacles=r["n_obstacles"], min_clearance=r.get("min_clearance"),
            end_kind=r.get("end_kind"),
            near_arrival_abort=r.get("near_arrival_abort"),
            returns_later=r.get("returns_later"),
            max_stall_dur=r.get("max_stall_dur"),
            geometry_stuck=r.get("stuck_risk_reason") in ("geometry", "both"),
            actual_pct=actual_pct,
            predicted_pct=pred.pct_of_baseline,
            residual=actual_pct - pred.pct_of_baseline,
            flagged=bool(pred.assumptions_flagged),
            stuck_risk=False,
        ))

    # Evaluate (but do NOT fold into the fitting stats above) the
    # stuck-pathing-risk legs pulled out earlier, purely so their
    # magnitude stays visible instead of silently vanishing.
    stuck_risk_results = []
    for r in stuck_risk_rows:
        tgt = r["planets"][r["tgt"]]
        pred = predict_transit(r["obstacles"], (r["x0"], r["y0"]), (tgt["x"], tgt["y"]), baseline_speed)
        actual_pct = 100.0 * r["speed"] / baseline_speed
        stuck_risk_results.append(dict(
            replay=r["replay"], id=r["id"], tgt=r["tgt"],
            x0=r["x0"], y0=r["y0"], x1=r["x1"], y1=r["y1"], w=r.get("w"), h=r.get("h"),
            edge_dist=None, ships_sent=r.get("ships_sent"),
            dist=r["dist"], dur=r["dur"], n_obstacles=r["n_obstacles"],
            min_clearance=r.get("min_clearance"),
            end_kind=r.get("end_kind"),
            near_arrival_abort=r.get("near_arrival_abort"),
            returns_later=r.get("returns_later"),
            max_stall_dur=r.get("max_stall_dur"),
            stuck_risk_reason=r.get("stuck_risk_reason"),
            actual_pct=actual_pct, predicted_pct=pred.pct_of_baseline,
            residual=actual_pct - pred.pct_of_baseline,
            flagged=bool(pred.assumptions_flagged),
            stuck_risk=True,
        ))

    if stuck_risk_results:
        sr_actual = statistics.mean(r["actual_pct"] for r in stuck_risk_results)
        sr_pred = statistics.mean(r["predicted_pct"] for r in stuck_risk_results)
        sr_resid = statistics.mean(r["residual"] for r in stuck_risk_results)
        print(f"\n=== EXCLUDED as stuck-pathing risk (n={len(stuck_risk_results)}, kept out of the stats below) ===")
        print(f"  mean actual_pct={sr_actual:.1f}%  mean predicted_pct={sr_pred:.1f}%  mean residual={sr_resid:+.1f}%")

        # How was each one caught -- the new trajectory-stall test, the
        # old static-geometry heuristic, or both? Shows how much the
        # trajectory test is actually adding versus just re-finding what
        # the geometry heuristic already caught.
        by_reason = {}
        for r in stuck_risk_results:
            by_reason.setdefault(r.get("stuck_risk_reason"), []).append(r)
        for reason in ("trajectory", "geometry", "both"):
            grp = by_reason.get(reason)
            if grp:
                print(f"    caught by {reason} (n={len(grp)}): "
                      f"mean actual_pct={statistics.mean(g['actual_pct'] for g in grp):.1f}%")

        # And how do these break down by end_kind/case -- were they
        # heading straight for the target (fd) or were they also flagged
        # by Phil's redirect cases above?
        by_end = {}
        for r in stuck_risk_results:
            by_end.setdefault(r.get("end_kind"), []).append(r)
        for ek, grp in by_end.items():
            print(f"    end_kind={ek} (n={len(grp)})")

        worst_stuck = sorted(stuck_risk_results, key=lambda r: -abs(r["residual"]))[:5]
        for r in worst_stuck:
            print(f"    id={r['id']:>7} tgt={r['tgt']:>3} ships={r['ships_sent']} reason={r.get('stuck_risk_reason')} "
                  f"max_stall={r.get('max_stall_dur', 0.0):.1f}s min_clearance={r['min_clearance']:6.1f} "
                  f"dist={r['dist']:6.1f} dur={r['dur']:5.2f} "
                  f"actual={r['actual_pct']:6.1f}% predicted={r['predicted_pct']:6.1f}% residual={r['residual']:+6.1f}%")

    mae = statistics.mean(abs(r["residual"]) for r in results)
    rmse = math.sqrt(statistics.mean(r["residual"] ** 2 for r in results))
    xs = [r["predicted_pct"] for r in results]
    ys = [r["actual_pct"] for r in results]
    mx, my = statistics.mean(xs), statistics.mean(ys)
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    dxx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    dyy = math.sqrt(sum((y - my) ** 2 for y in ys))
    corr = num / (dxx * dyy) if dxx and dyy else float("nan")

    print(f"\n=== all legs (n={len(results)}) ===")
    print(f"  mean actual_pct={statistics.mean(ys):.2f}%  mean predicted_pct={statistics.mean(xs):.2f}%")
    print(f"  MAE={mae:.2f}%  RMSE={rmse:.2f}%  corr(predicted,actual)={corr:.3f}")

    zero = [r for r in results if r["n_obstacles"] == 0]
    nonzero = [r for r in results if r["n_obstacles"] > 0]
    if zero:
        print(f"\n  no-obstacle legs (n={len(zero)}): MAE={statistics.mean(abs(r['residual']) for r in zero):.2f}%")
    if nonzero:
        print(f"  with-obstacle legs (n={len(nonzero)}): MAE={statistics.mean(abs(r['residual']) for r in nonzero):.2f}%")

    # Does max_stall_dur behave as a continuum rather than a bug/no-bug
    # binary? If short, sub-threshold stalls still correlate with worse
    # fit among the legs we DIDN'T exclude, that's evidence for a milder
    # version of the same obstacle-interaction slowdown, not unrelated
    # noise -- i.e. STALL_DUR_MIN is a cutoff of convenience, not a real
    # boundary in the underlying phenomenon.
    with_stall = [r for r in results if r.get("max_stall_dur") is not None]
    if with_stall:
        sd = [r["max_stall_dur"] for r in with_stall]
        ar = [abs(r["residual"]) for r in with_stall]
        ms, mr = statistics.mean(sd), statistics.mean(ar)
        num = sum((s - ms) * (rr - mr) for s, rr in zip(sd, ar))
        dxx = math.sqrt(sum((s - ms) ** 2 for s in sd))
        dyy = math.sqrt(sum((rr - mr) ** 2 for rr in ar))
        stall_corr = num / (dxx * dyy) if dxx and dyy else float("nan")
        print(f"\n  corr(max_stall_dur, |residual|) among INCLUDED legs = {stall_corr:.3f} "
              f"(positive = even sub-threshold stalls predict worse fit -- a continuum, not a clean bug/no-bug split)")
        # bucket by stall duration to see the shape of that continuum
        # directly, not just a single correlation coefficient
        buckets = [(0.0, 0.5), (0.5, 1.0), (1.0, 1.5), (1.5, 2.0)]
        for lo, hi in buckets:
            grp = [r for r in with_stall if lo <= r["max_stall_dur"] < hi]
            if grp:
                print(f"    max_stall_dur in [{lo:.1f},{hi:.1f})s (n={len(grp)}): "
                      f"MAE={statistics.mean(abs(r['residual']) for r in grp):.2f}%")

    flagged = [r for r in results if r["flagged"]]
    print(f"\n  {len(flagged)} legs hit a flagged/extrapolated assumption in predict_transit()")

    # edge-proximity check -- tests whether pathologically-slow legs sit
    # near the map border (would point at map wraparound distorting a
    # naive Euclidean distance calc)
    with_edge = [r for r in results if r["edge_dist"] is not None]
    if with_edge:
        eds = [r["edge_dist"] for r in with_edge]
        res = [abs(r["residual"]) for r in with_edge]
        me, mr = statistics.mean(eds), statistics.mean(res)
        num = sum((e - me) * (rr - mr) for e, rr in zip(eds, res))
        dxx = math.sqrt(sum((e - me) ** 2 for e in eds))
        dyy = math.sqrt(sum((rr - mr) ** 2 for rr in res))
        edge_corr = num / (dxx * dyy) if dxx and dyy else float("nan")
        print(f"\n  corr(distance-to-map-edge, |residual|) = {edge_corr:.3f} "
              f"(negative = outliers cluster near the border -- possible wraparound)")
        near_edge = [r for r in with_edge if r["edge_dist"] < 20]
        if near_edge:
            near_mae = statistics.mean(abs(r["residual"]) for r in near_edge)
            far_mae = statistics.mean(abs(r["residual"]) for r in with_edge if r["edge_dist"] >= 20)
            print(f"  legs within 20u of the map border (n={len(near_edge)}): MAE={near_mae:.2f}%")
            print(f"  legs farther than 20u from the border: MAE={far_mae:.2f}%")

    # fleet-size check -- tests whether small ("probe") sends are
    # inherently slower, which would show as a positive correlation
    # between ships_sent and actual_pct (small fleets -> low actual_pct)
    with_ships = [r for r in results if r["ships_sent"] is not None]
    if with_ships:
        sh = [r["ships_sent"] for r in with_ships]
        ap = [r["actual_pct"] for r in with_ships]
        ms, ma = statistics.mean(sh), statistics.mean(ap)
        num = sum((s - ms) * (a - ma) for s, a in zip(sh, ap))
        dxx = math.sqrt(sum((s - ms) ** 2 for s in sh))
        dyy = math.sqrt(sum((a - ma) ** 2 for a in ap))
        ships_corr = num / (dxx * dyy) if dxx and dyy else float("nan")
        print(f"\n  corr(ships_sent, actual_pct) = {ships_corr:.3f} "
              f"(positive = bigger fleets fly faster -- a fleet-size speed effect)")
        small = [r for r in with_ships if r["ships_sent"] <= 5]
        big = [r for r in with_ships if r["ships_sent"] > 5]
        if small and big:
            print(f"  ships_sent<=5 (n={len(small)}): mean actual_pct={statistics.mean(r['actual_pct'] for r in small):.1f}%  "
                  f"MAE={statistics.mean(abs(r['residual']) for r in small):.2f}%")
            print(f"  ships_sent>5  (n={len(big)}): mean actual_pct={statistics.mean(r['actual_pct'] for r in big):.1f}%  "
                  f"MAE={statistics.mean(abs(r['residual']) for r in big):.2f}%")

    # landed-vs-redirected-away check -- Phil spot-checked several worst
    # residuals in the replay viewer and found a pattern: the fleet flies
    # normally, then gets redirected away before reaching tg0 (sometimes
    # never landing on it at all). A leg like that still starts clean
    # ("fs"), so it wasn't excluded by the redirect-started filter above --
    # but its measured dist/dur only covers the fs-to-fr segment, not a
    # full flight to the target, so "actual_pct" here describes however
    # fast it was moving up to the moment someone redirected it, not
    # necessarily terrain slowdown. Compare the two populations directly.
    with_end_kind = [r for r in results if r.get("end_kind") is not None]
    if with_end_kind:
        landed = [r for r in with_end_kind if r["end_kind"] == "fd"]
        redirected_away = [r for r in with_end_kind if r["end_kind"] == "fr"]
        if landed:
            print(f"\n  legs that landed/arrived (end_kind=fd, n={len(landed)}): "
                  f"mean actual_pct={statistics.mean(r['actual_pct'] for r in landed):.1f}%  "
                  f"MAE={statistics.mean(abs(r['residual']) for r in landed):.2f}%")
        if redirected_away:
            print(f"  legs redirected away before landing (end_kind=fr, n={len(redirected_away)}): "
                  f"mean actual_pct={statistics.mean(r['actual_pct'] for r in redirected_away):.1f}%  "
                  f"MAE={statistics.mean(abs(r['residual']) for r in redirected_away):.2f}%")

            # Sub-split the fr-ending legs into Phil's Case B (aborted
            # right at the target's doorstep -- essentially a completed
            # transit) vs Case C (redirected away, but comes back to the
            # same target later -- this leg's own measurement is still a
            # valid partial-path segment) vs neither (redirected away and
            # never returns -- the ambiguous "did it actually fail to
            # transit, or is the low speed itself evidence of the same
            # stuck-pathing issue in a fleet too big/shallow to trip the
            # STUCK_* thresholds above?" case).
            near_arrival = [r for r in redirected_away if r.get("near_arrival_abort")]
            returns = [r for r in redirected_away if r.get("returns_later") and not r.get("near_arrival_abort")]
            neither = [r for r in redirected_away
                       if not r.get("near_arrival_abort") and not r.get("returns_later")]
            if near_arrival:
                print(f"    Case B -- aborted near the target (>=85% of the way there, n={len(near_arrival)}): "
                      f"mean actual_pct={statistics.mean(r['actual_pct'] for r in near_arrival):.1f}%  "
                      f"MAE={statistics.mean(abs(r['residual']) for r in near_arrival):.2f}%")
            if returns:
                print(f"    Case C -- redirected away, returns to same target later (n={len(returns)}): "
                      f"mean actual_pct={statistics.mean(r['actual_pct'] for r in returns):.1f}%  "
                      f"MAE={statistics.mean(abs(r['residual']) for r in returns):.2f}%")
            if neither:
                print(f"    redirected away, never returns, not near target (n={len(neither)}): "
                      f"mean actual_pct={statistics.mean(r['actual_pct'] for r in neither):.1f}%  "
                      f"MAE={statistics.mean(abs(r['residual']) for r in neither):.2f}%")

    worst = sorted(results, key=lambda r: -abs(r["residual"]))[:10]
    print("\n  10 worst residuals:")
    for r in worst:
        ed = f"edge_dist={r['edge_dist']:.1f}" if r["edge_dist"] is not None else "edge_dist=?"
        sh = f"ships={r['ships_sent']}" if r["ships_sent"] is not None else "ships=?"
        ek = f"end={r['end_kind']}" if r.get("end_kind") else "end=?"
        case = ""
        if r.get("end_kind") == "fr":
            if r.get("near_arrival_abort"):
                case = " caseB"
            elif r.get("returns_later"):
                case = " caseC"
            else:
                case = " unresolved-fr"
        ms = f"stall={r['max_stall_dur']:.1f}s" if r.get("max_stall_dur") is not None else "stall=?"
        print(f"    id={r['id']:>7} tgt={r['tgt']:>3} obstacles={r['n_obstacles']} "
              f"dist={r['dist']:6.1f} dur={r['dur']:5.2f} "
              f"actual={r['actual_pct']:6.1f}% predicted={r['predicted_pct']:6.1f}% "
              f"residual={r['residual']:+6.1f}%  ({ed}, {sh}, {ek}{case}, {ms}, "
              f"start=({r['x0']:.0f},{r['y0']:.0f}) end=({r['x1']:.0f},{r['y1']:.0f}), w={r['w']} h={r['h']})")

    if csv_path:
        fieldnames = ["replay", "id", "tgt", "x0", "y0", "x1", "y1", "w", "h", "edge_dist",
                      "ships_sent", "dist", "dur", "n_obstacles", "min_clearance", "end_kind",
                      "near_arrival_abort", "returns_later", "max_stall_dur", "stuck_risk_reason",
                      "actual_pct", "predicted_pct", "residual", "flagged", "stuck_risk"]
        all_rows_out = results + stuck_risk_results
        with open(csv_path, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fieldnames)
            w.writeheader()
            for r in all_rows_out:
                w.writerow({k: r.get(k) for k in fieldnames})
        print(f"\nwrote {len(all_rows_out)} legs -> {csv_path} "
              f"({len(results)} used for fitting, {len(stuck_risk_results)} flagged stuck_risk=True)")


if __name__ == "__main__":
    main()
