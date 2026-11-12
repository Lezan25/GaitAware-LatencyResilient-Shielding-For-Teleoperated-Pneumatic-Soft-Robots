# Gait-aware shielding — UPPAAL models

UPPAAL 5 model of a runtime shield for a teleoperated pneumatic soft robot that walks with multi-phase gaits among moving obstacles, which it detects with a 1-tu delay. Every result below is reproduced by `./run.sh`. It takes a few hours on 4 cores, and `results/summary.md` lists every query with its outcome.

## Files

| File | Content |
|---|---|
| `shield.xml` | **the model**, used for simulation. It is configured as S7, and the shield constants list the values for S1–S7. |
| `proofs/shield_proof.xml` | proof copy of `shield.xml` (details below) |
| `proofs/T1_filter.xml`, `proofs/T2_executor.xml`, `proofs/T3_handback.xml` | `shield_proof.xml` with the `Shield` template replaced, used for the three theorems |
| `queries/proof.q`, `queries/proof_chamber_naive.q` | properties checked on every shield |
| `stratego/shield_stratego.xml` | UPPAAL Stratego synthesis attempt on the same model (reported as a negative result: it did not terminate with two obstacles and ran out of memory with three) |
| `run.sh` | runs everything: `./run.sh [proofs\|theorems\|checks\|sim\|sweep\|sens\|summary\|all]` |
| `tmp/` | per-shield and per-setting copies made by `run.sh` (generated) |
| `results/` | verifyta output, with counterexample traces, and `summary.md` (generated) |

How `proofs/shield_proof.xml` differs from `shield.xml`:
- `NUM_OBSTACLES = 1` (see the lifting argument below);
- no simulation metrics;
- a hand-back observer (`guardedCycle`, `seenAtHandBack`, `earlyReintervention`), called from `decideGait`.

The three theorem models differ from `shield_proof.xml` only in the `Shield` template:

| Model | Template | What it allows each tu |
|---|---|---|
| T1 | `AnyFilteredGait` | any gait that passes the filter |
| T2 | `AnyGait` | any gait at all |
| T3 | `HandBackLemma` | any filtered gait, plus a hand-back whenever the hand-back rule allows it |

## Model in brief

**Templates.** One time unit is driven by `Clock`:
1. `tick`: every `Obstacle(id)` moves or waits.
2. `readJoystick`: the `Joystick` sets the request.
3. `decide`: the `Shield` chooses the gait.
4. `execute`: the `Robot` runs one step of it. On a completed forward cycle it broadcasts `worldShift`, the world shifts by one cell, and the collision check runs.

**Robot.**
- Two segments (head, tail), each with a left and a right chamber. Chamber levels are `EMPTY`, 1 and `FULL`; `OVERINFLATED` (3) must never be reached.
- Gaits: `FORWARD` (5 tu), `LEFT` and `RIGHT` (3 tu each), and `HOLD`. They are given by `PHASE_COMMANDS` and `PHASE_LEVELS`.
- The robot moves one cell, or turns 45°, when a cycle completes.

**Arena.** Robot-centred and unbounded: positions are relative to the tail. Obstacles farther than `WINDOW = SENSOR_RANGE + 2` from the tail are absent.

**Obstacles.**
- **Speed:** two moves of an obstacle are at least `MIN_MOVE_GAP` (3) tu apart. In between it may stand still for any time. This is the assumed maximum speed: it should be chosen a priori from real data, the proofs hold for every slower obstacle, and setting it higher than needed only makes the shield over-conservative.
- **Entering:** an absent obstacle appears on the window border with a random move timer. If that timer makes it free to move, it takes its move decision in the same tick.
- **Detection:** it shows the position 1 tu earlier, so it hides at most one move.
- **Passive safety:** obstacles never step onto the robot. A *collision* means the robot entered an obstacle's cell.

**One model for proofs and simulation.** Obstacle moves, appearances and joystick requests are probabilistic branches.
- **Proofs:** UPPAAL's symbolic checker treats every branch as possible, including zero-weight ones. The results hold for any obstacle motion and any joystick input.
- **Simulation:** the weights are followed:
  - Obstacles keep their walking direction with weight `KEEP_DIRECTION_WEIGHT` = 54 against 4 for each of the 9 options.
  - The joystick is forward about 80% of the time, with turn bursts of 1–4 turn cycles starting once per `TURN_ONE_IN` = 24 tu on average.
  - 3 obstacles.

**Shield layers** (constants at the top of the declarations):

| Constant | Meaning | Values |
|---|---|---|
| `CHAMBER_AWARE` | how the executor gets from the current chamber state into the target gait | aware: align to the cheapest phase of the target gait; naive: blindly restart the gait |
| `DELAY_AWARE` | what the danger set covers | aware: every cell an obstacle can have reached since its detection; naive: only the detected cell |
| `HANDBACK` | when control returns to the user | `LATE`: once nothing is sensed; `EARLY`: once the surroundings of the head are clear; `GAIT`: once the requested gait's remaining cycle, counted from the current chambers, can complete safely against worst-case obstacle motion |
| `AVOIDANCE` | what the shield does while in control | `MAX_CLEARANCE`: maximise distance; `GAIT_AWARE`: reach (no more than) the clearance an obstacle cannot close during the detection delay plus one full cycle of the request, preferring the request, then the gait quickest to complete from the current chambers |

| Shield | `CHAMBER_AWARE` | `DELAY_AWARE` | `HANDBACK` | `AVOIDANCE` |
|---|---|---|---|---|
| S1 naive | false | false | LATE | MAX_CLEARANCE |
| S2 | true | false | LATE | MAX_CLEARANCE |
| S3 | false | true | LATE | MAX_CLEARANCE |
| S4 | true | true | LATE | MAX_CLEARANCE |
| S5 minimal intervention | true | true | EARLY | MAX_CLEARANCE |
| S6 gait-aware hand-back | true | true | GAIT | MAX_CLEARANCE |
| **S7 full shield** | true | true | GAIT | GAIT_AWARE |

Every shield intervenes only when the requested step is unsafe, and every one ends with the same one-step safety filter (`passesFilter`).

## Formal results

Shields are checked with one obstacle. The results are lifted to any number of obstacles on the unbounded grid by the projection and window lemmas in `../paper/lemmas.pdf` (source: `../paper/lemmas.tex`).

| Property | S1 | S2 | S3 | S4 | S5 | S6 | S7 |
|---|---|---|---|---|---|---|---|
| `A[] !collision` | ✗ trace | ✗ trace | ✓ | ✓ | ✓ | ✓ | ✓ |
| `A[] !overinflated` | ✗ trace | ✓ | ✗ trace | ✓ | ✓ | ✓ | ✓ |
| `A[] !earlyReintervention` | – | ✓* | – | ✓* | **✗ trace** | **✓** | **✓** |
| `A[] !deadlock` | – | ✓ | – | ✓ | ✓ | ✓ | ✓ |

- ✗ trace: the property is violated, and UPPAAL gives the shortest counterexample (`results/proof_*.txt`).
- \*S2 and S4 hand back only once nothing is sensed, so the property holds trivially for them.
- –: not checked. The chamber-naive shields (S1, S3) are checked only for collision and over-inflation, because blind restarts reach arbitrary chamber levels; S3's collision check alone takes 38 M states. The others need at most 2.0 M.

**Policy-independent results**

| Id | Statement | Result |
|---|---|---|
| T1 | Any gait choice that passes the delay-aware filter is collision-free | ✓ (1.9 M states) |
| T2 | The chamber-aware executor never over-inflates, for any sequence of gaits | ✓ (3.9 M states) |
| T3 | Gait-aware hand-back: no early re-intervention, for any recovery before the hand-back and any other obstacles | ✓ (2.1 M states) |

**Boundary checks** (`results/check_*.txt`)

| Check | Result |
|---|---|
| Filter trusting the detection | ✗ |
| Sensor range 1 | ✗ |
| T3 with the early hand-back rule | ✗ (the lemma is not vacuous) |
| T1 with `MIN_MOVE_GAP` 1 (obstacles 3× faster) | ✓ |
| T1 and T3 at every sensitivity setting (range 2 and 4, gap 2 and 4) | ✓ |

## Simulation results

3 obstacles, 1000 runs × 1000 tu. 95% CI half-widths are ≤ 2.7 tu for override time, ≤ 0.25 for the counts, and ≤ 0.08 for re-takeovers.

Two ways of counting interventions:
- **override-based:** an *intervention* starts whenever the executed gait stops matching the request, and a *re-intervention* is one that starts ≤ 6 tu after the executed gait last matched it.
- **takeover-based:** a *takeover* is a real transfer of control to the shield, and a *re-takeover* is one that starts ≤ 6 tu after the shield really handed control back.

| Shield | P(collision) | P(over-infl.) | override tu | interventions | re-interventions | takeovers | re-takeovers | requested cycles | inflations |
|---|---|---|---|---|---|---|---|---|---|
| S1 | 0.45–0.52 | ≈ 1 | 32.6 | 5.1 | 1.7 | 3.2 | 0.00 | 208.8 | 1536 |
| S2 | 0.44–0.51 | 0 | 34.5 | 5.0 | 1.7 | 3.2 | 0.01 | 202.5 | 1544 |
| S3 | 0 | ≈ 1 | 109.5 | 18.2 | 6.2 | 12.1 | 0.32 | 189.2 | 1490 |
| S4 | 0 | 0 | 115.6 | 17.9 | 5.9 | 11.7 | 0.30 | 181.6 | 1507 |
| S5 | 0 | 0 | 84.6 | 16.4 | 3.8 | 13.5 | 1.14 | 185.6 | 1520 |
| S6 | 0 | 0 | 91.6 | **14.7** | **2.2** | 13.3 | 1.13 | 186.4 | 1518 |
| S7 | 0 | 0 | **72.1** | 16.1 | 3.3 | 13.3 | **0.89** | **187.3** | 1546 |

"0" means none was observed in 1000 runs (upper 95% bound 0.004).

**Obstacle-count sweep** (override tu / re-interventions / re-takeovers / requested cycles)

| Obstacles | S4 | S5 | S6 | S7 |
|---|---|---|---|---|
| 1 | 37.2 / 1.27 / 0.05 / 199.5 | 29.7 / 1.06 / 0.32 / 200.7 | 31.4 / **0.74** / 0.32 / **200.8** | **27.3** / 0.86 / **0.19** / **200.8** |
| 2 | 75.2 / 3.24 / 0.16 / 191.1 | 56.2 / 2.47 / 0.74 / 193.0 | 60.8 / **1.43** / 0.63 / 193.5 | **50.8** / 1.94 / **0.48** / **194.1** |
| 3 | 115.6 / 5.86 / 0.30 / 181.6 | 84.6 / 3.81 / 1.14 / 185.6 | 91.6 / **2.22** / 1.13 / 186.4 | **72.1** / 3.34 / **0.89** / **187.3** |
| 4 | 161.9 / 9.15 / 0.50 / 171.9 | 114.0 / 5.49 / 1.74 / 178.2 | 123.0 / **3.29** / 1.64 / 178.1 | **93.7** / 5.34 / **1.33** / **180.2** |
| 5 | 204.6 / 12.79 / 0.53 / 161.3 | 142.9 / 7.47 / 2.26 / 171.1 | 154.2 / **4.43** / 2.04 / 171.8 | **113.5** / 7.44 / **1.80** / **173.2** |

**Reading:**
- **Delay awareness** is what makes the shield safe. Without it, P(collision) is about 0.5 per 1000 tu even with a 1-tu delay, and the low override time of S1 and S2 is only because they trust stale detections.
- **Chamber awareness** removes over-inflation.
- **Minimal intervention** (S5 vs S4) cuts override time by 27%. S4's few re-takeovers are the other side of its late hand-back: it keeps control until nothing is sensed.
- **Gait-aware hand-back** (S6 vs S5):
  - 30–42% fewer re-interventions, and the fewest interventions;
  - re-takeovers 0–15% fewer;
  - 6–8% more override time.
- **Gait-aware avoidance** (S7 vs S5):
  - override time: 8–21% less, with the gap growing with obstacle count;
  - re-takeovers: 20–41% fewer, the fewest at every count;
  - progress: highest at every count (tied with S6 at 1 obstacle);
  - re-interventions level with or below S5;
  - cost: at most 4% more air.
- **Why the two counts differ.** While in control, the avoidance can pick the *requested gait itself* whenever that already gives enough clearance. Those tu match the request, so one takeover can show up as several overrides, although control never returned to the user.
- **Why S6 and S7 still have re-takeovers.** The formal guarantee covers only takeovers caused by an obstacle that was in view at the hand-back, before the requested cycle completes, with the request unchanged. The simulation counts every takeover within 6 tu, including those caused by:
  - a request change;
  - a new obstacle;
  - the next cycle;
  - a hand-back made because nothing was sensed.

## Sensitivity to the parameters we chose

S4–S7 with 3 obstacles, one parameter changed at a time (`./run.sh sens`). Each cell gives override tu / re-takeovers; bold marks the best of S5–S7. The safety and hand-back proofs hold at every setting (boundary checks). Direction persistence and turn rate only change simulation weights.

| Setting | S4 | S5 | S6 | S7 |
|---|---|---|---|---|
| default (range 3, gap 3, keep weight 54, turns 1/24) | 115.6 / 0.30 | 84.6 / 1.14 | 91.6 / 1.13 | **72.1 / 0.89** |
| sensor range 2 | 112.1 / 1.81 | 113.2 / **1.70** | 104.6 / 2.42 | **90.9** / 2.12 |
| sensor range 4 | 116.6 / 0.06 | 66.7 / 0.95 | 75.6 / 0.80 | **57.2 / 0.64** |
| faster obstacles (gap 2) | 98.3 / 0.49 | **70.9** / 1.42 | 79.4 / 1.19 | 71.5 / **0.97** |
| slower obstacles (gap 4) | 128.1 / 0.21 | 93.1 / **1.05** | 91.2 / 1.08 | **70.9** / 1.06 |
| random-walk obstacles (keep weight 0) | 132.2 / 0.44 | 91.7 / 2.31 | 100.6 / 1.71 | **72.3 / 0.97** |
| very persistent obstacles (keep weight 324) | 116.0 / 0.19 | 84.7 / **0.73** | 90.4 / 0.91 | **73.3** / 0.76 |
| frequent turns (1/12) | 117.2 / 0.37 | 86.5 / **1.26** | 91.2 / 1.43 | **73.2** / 1.32 |
| rare turns (1/48) | 111.0 / 0.26 | 83.0 / 1.16 | 91.5 / 1.01 | **72.2 / 0.66** |

S4 is excluded from the bolding: it has the fewest re-takeovers only because it hands back once nothing is sensed, at the price of the most override time.

**Reading:**
- **S7's override advantage holds everywhere except with faster obstacles.** It needs 13–24% less override time than S5 in 8 of 9 settings. With faster obstacles (gap 2) the two are level within the confidence interval (71.5 vs 70.9).
- **Its re-takeover advantage depends on the setting:**
  - fewer in 5 settings, by up to 58%: default, range 4, gap 2, random walk, rare turns;
  - about equal in 3: gap 4 +1%, very persistent +4%, frequent turns +5%;
  - more only at sensor range 2 (+25%).
- **S6 alone** ranges from −26% to +42% against S5 on re-takeovers. It always has the fewest override-based re-interventions.
- **The guarantee itself is unaffected.** The extra re-takeovers come from causes it doesn't cover:
  - request changes;
  - the next cycle;
  - obstacles leaving the sensor range and coming back, which is likely with a short range.

## Running

```bash
VERIFYTA=/path/to/uppaal/bin/verifyta JOBS=4 ./run.sh all
```

`shield.xml` and every file in `proofs/` can also be opened in the UPPAAL GUI, where their embedded queries can be run directly. Select a shield by editing the four shield constants.
