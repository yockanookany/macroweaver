# MacroWeaver

Build WoW macros by clicking instead of typing. Pick a spell, choose when it should fire, and drag
the macro onto your bar. Made for WoW: Forever; also loads on Classic Era.

## Install

With [WowUp](https://wowup.io): Get Addons, Install from URL, and paste this repository's address.
WowUp then keeps it updated from new releases.

By hand: download the `-forever` zip (or `-classic` for Classic Era) from the latest release and
put the `MacroWeaver` folder in `World of Warcraft\_forever_\Interface\AddOns` (or `_classic_era_`),
so the path ends in `AddOns\MacroWeaver\MacroWeaver.toc`. Type `/mw` in game to open it.

## Use

Start from **Single action** or one of the presets (mouseover, friendly/hostile, healer
mouseover > target > self, modifier keys, focus, cursor, form-then-ability, swim/travel and more).
Select a rule on the right, click a spell, item or buff on the left, then set its conditions:
target, friendly or hostile, modifier, alive or dead, form or stance, and combat, stealth, mounted,
swimming or indoors.

Rules are checked top to bottom and the first match wins. Drag the icon at the bottom to your bar
to save it.

Some handy extras:

- **Rank** casts a fixed rank, for downranking. Leave it on Highest to always cast your best rank.
- **All class spells** lets you plan with spells you haven't learned yet. They do nothing until you
  train them.
- **Auto-update** keeps your macros current after training, talent or pet changes. It leaves macros
  you've edited by hand alone and never deletes anything.
- The **Saved** tab reopens a macro you made here. Change it and press **Save changes**, or type a
  new name to rename it.
- WoW's own Macros window gets a **Keep spell ranks current** checkbox for macros you wrote
  yourself.

## Credits and license

Class spell data from [talentsforever.com](https://talentsforever.com/about), used under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

The addon's code is under the MIT license; see [LICENSE](LICENSE).
