<img width="250" height="250" alt="brotato-easy-ready" src="https://github.com/user-attachments/assets/05c5a7d9-3c72-46bf-9f74-b12aba0a7e38" />

# Brotato - Easy Ready

A small quality-of-life mod for [Brotato](https://store.steampowered.com/app/1942280/Brotato/) that adds a global hotkey to ready up on the wave/shop screen — no more navigating focus over to the GO button before every wave.

## How It Works

Press the hotkey anywhere on the shop screen and the wave starts immediately, exactly as if you'd clicked GO. Works while browsing items, rerolling, or hovering anything else.

- **Keyboard default:** `G` — chosen because nothing else in Brotato uses it.
- **Controller default:** the **View** button on Xbox / **Share/Create** button on PlayStation / **−** button on Switch.

Both bindings are configurable via the in-game ModLoader config (Mods → Easy Ready), with `keyboard_scancode` and `joypad_button_index` fields.

## Features

- **Visual hint on the GO button** — Styled like the lock button's E-key glyph (dark cap, gray interior, white letter/symbol). Mirrors Brotato's own UI aesthetic.
- **Device-aware** — Auto-switches between the keyboard glyph and the correct controller glyph (Xbox / PS / Switch) the moment you swap input devices, the same way Brotato's lock button does.
- **Coop-friendly** — Pressing the hotkey only readies up the player who pressed it; the wave does **not** start until every player is ready, exactly like clicking the GO button. Each player's controller readies their own slot; keyboard goes to player 1.
- **Respects pause** — Pressing the hotkey while paused does nothing.
- **Toggleable** — Press again before all players are ready to un-ready (same behavior as clicking the GO button twice).

## Installation

Just hit Subscribe, and the mod will be added to your game automatically. No setup required.
