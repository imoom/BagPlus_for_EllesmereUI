# EllesmereUI 9.7 compatibility review

Reviewed 2026-10-31. Baseline: BagPlus 26.12 and EUI `d4eb56ee` (9.5.5).
Target: the existing EUI checkout at `fc8d3c83`, two translation commits after
9.7.2. The checkout was already updated when this review started. No upstream
files were edited. Initial in-game testing was reported successful by the user
on 2026-10-31. The full in-game checklist below remains outstanding.

## Compatibility findings and changes

| Finding | Effect before this change | Resolution |
| --- | --- | --- |
| EUI 9.7 adds Slot Size and Slot Spacing. BagPlus assumed 34 and 4. | Changed sizes could stop slots/pads being recognized; changed spacing could cause incorrect row positions, widths, and section grouping. | Read EUI's applied `ns.SLOT_SIZE` and `ns.SPACING` after native refresh. Update the compact bucket gap too. Applied values respect EUI's combat deferral; defaults support earlier EUI versions. |
| OfflineView calls `ClassifyItem(link, id, nil, nil, quality)`. | BagPlus could treat already-bound BoE gear as unbound, with no container state available to disprove it. Warbound detection also needs a live item location. | Retain native classification when both live slot state and an explicit info table are unavailable. Offline BoE/Warbound categories are not inferred from links. |
| Offline panels cover the live item area and manage their own geometry. | BagPlus's post-layout pass could inspect or resize the underlying live grid despite the offline panel being active. | Skip post-layout changes while EUI's `OfflineUp()` is true. |
| Native `SyncHeaderIcons` rebuilds the header icon chain. | It could put Show Bags back over the reagent button. With Show Bags hidden, Quick Actions or Junk could occupy the reagent button's position. This issue predates 9.7. | Post-hook native synchronization and insert the reagent button before the next native control without changing downstream icon order or visibility. |

## New EUI behavior checked

- **Offline bank, alt inventories, and tooltip counts:** snapshot collection and
  tooltip hooks remain EUI-owned. Offline classification keeps native categories;
  BagPlus's layout options apply to the live Grid only. Counts and the full offline
  renderer still need in-game checks.
- **Bag/bank appearance:** background tint, opacity, slot backgrounds, and
  custom item-level colors remain native. BagPlus moves existing frames rather
  than repainting their textures, borders, or labels. Slot dimensions now follow
  the native applied metrics.
- **Native List and Compact:** BagPlus still skips their post-layout geometry.
  Its categorization and selected gear sorting remain active for live items.
- **Bank changes:** the updated gold/silver/copper money popup and nested bank
  sidebar remain native. EUI still routes ordinary deposits to the selected tab
  (or space in aggregate warbank); it has not adopted BagPlus's deposit-filter
  matching. BagPlus still overrides the two bank-routing methods on retail.
- **9.7.1/9.7.2 bag fixes:** between the 9.7 and 9.7.2 tags, bag runtime changes
  are in `EUI_Bags_Start.lua`, adding mail-close bag handling. BagPlus does not
  replace those event handlers or open/close functions.
- **Module split:** EUI moved the former main bag implementation into
  `EUI_Bags_*` files. The global manager/frame methods BagPlus extends are still
  present. The upstream category implementation itself is unchanged from the
  baseline.

## Features worth keeping or retiring

The main overlaps below already existed in the 9.5.5 baseline; 9.7 adds no full
replacement for BagPlus's category and transfer extensions.

| BagPlus feature | EUI 9.7.2 equivalent | Assessment |
| --- | --- | --- |
| BoE, Bind-on-Use, cosmetic, and Warbound-until-Equipped gear categories | No corresponding built-in binding rules. Manual categories and item assignments exist. | Keep for live inventories. Preserve manual assignments, equipment sets, quests, reagent/special bags, and disabled-category routing. |
| Gear item-level sort | Native gear order prioritizes upgrade track, then descending item level for ranked gear. | Partial overlap. Keep ascending and pure item-level sorting; use `/bagplus ilvl off` to choose EUI's native order. BagPlus's default overrides native track priority intentionally. |
| Compact Category Rows | Native Compact packs category/group blocks side by side and supports bags and bank. | Strong alternative. Prefer native Compact if its layout suits the user. Keep this optional Grid behavior for users who want it; consider retiring it separately to reduce maintenance. |
| Hide Empty Recent Items | EUI can turn Recent Items off entirely; Grid explicitly allows its empty section to render. | Keep: conditional hiding differs from disabling Recent Items. |
| Maximum items per row | Slot dimensions and window resizing control geometry; they do not provide the same explicit BagPlus row cap. | Keep as an optional live Grid feature. |
| Move reagents into reagent bag | EUI sorting and bank reagent deposits have different destinations or broader effects. | Keep the targeted inventory-only move. |
| Bank category routing | Native tab deposit filters are configurable, but ordinary EUI right-click routing does not match items to those filters. | Keep on retail; Forever continues using native routing. |
| Extra Blizzard warbank cleanup button | EUI's native bank sort calls the same `C_Container.SortBank(Account)` when a warbank view is selected. | Best retirement candidate. Its remaining difference is sorting the warbank directly while viewing the character bank. Retained in this change pending a product decision. |

## Validation

`scripts/test.sh` passes 29 tests. Explicit Lua 5.1 parsing and `git diff --check`
also pass. Coverage includes the actual checked-out category manager on retail
and Forever, bound/unbound/Warbound classification, manual assignments, disabled
categories, offline calls without a live location, applied slot metrics at
24/0, 48/10, 56/12 and back to 34/4, compact rows with a row cap, offline layout
isolation, and native header refreshes with icons shown or hidden.

The rest of the suite covers sorting modes, reagent movement, bank routing,
warbank cleanup, saved-variable migration, and earlier layout cases. Most WoW
APIs and UI frames are mocked: passing tests do not prove live secure-frame,
combat, click, or visual behavior.

Before releasing, check in WoW:

1. Change slot size/spacing with bags open; exercise compact Grid rows, row
   caps, empty Recent Items, and nested armory/expansion sections. Try settings
   changes in combat and confirm the layout catches up after combat.
2. Enable Offline Bank and tooltip counts. Switch between the current
   character, an alt, the saved bank, and warbank; check counts, search, category
   filters, tooltip totals, and return to the live inventory.
3. Toggle Sort, Show Bags, Quick Actions, and Junk controls; open a merchant
   and check that header controls stay separate and clickable.
4. Verify manual category assignments, equipment sets, pins, Recent Items,
   reagent bags, and normal/BoE/Warbound gear. Switch gear sorting off and
   compare native track-first order.
5. Open character bank and warbank, test right-click deposits against tab
   filters, then test money input and cleanup. Close mail and verify EUI's
   configured bag-close behavior still runs.
6. Check new background/slot colors and item-level colors; switch to native
   List and Compact. Repeat the supported live Grid/category checks on Forever.
