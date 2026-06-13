# frozen_string_literal: true

# Each case: notation, the exact RNG draw sequence, and the expected total + kept values.
# RNG draws are in evaluator call order (see per-mechanic specs for ordering rules).
FlowDice::GOLDEN_ROLLS = [
  { notation: "d20",          rng: [14],            total: 14,  kept: [14] },
  { notation: "3d6+2",        rng: [3, 5, 2],       total: 12,  kept: [3, 5, 2] },
  { notation: "2d20kh+5",     rng: [18, 7],         total: 23,  kept: [18] },
  { notation: "2d20kl",       rng: [18, 7],         total: 7,   kept: [7] },
  { notation: "4d6kh3",       rng: [6, 1, 4, 3],    total: 13,  kept: [6, 4, 3] },
  { notation: "2d6c",         rng: [3, 5, 2, 6],    total: 16,  kept: [3, 5, 2, 6] },
  { notation: "2d6C",         rng: [3, 4],          total: 19,  kept: [3, 4] },
  { notation: "d100",         rng: [73],            total: 73,  kept: [73] },
  { notation: "d%",           rng: [7, 3],          total: 73,  kept: [70, 3] },
  { notation: "d%",           rng: [0, 0],          total: 100, kept: [0, 0] },
  { notation: "2d%kl",        rng: [7, 4, 3],       total: 43,  kept: [40, 3] },
  # Custom Skill System (Chris's homebrew) — must stay green.
  { notation: "4d[0..5]",     rng: [5, 0, 3, 2],    total: 10,  kept: [5, 0, 3, 2] },
  { notation: "6d[0..5]kh4",  rng: [5, 4, 1, 0, 3, 2], total: 14, kept: [5, 4, 3, 2] }
].freeze
