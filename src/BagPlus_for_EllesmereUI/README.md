# BagPlus for EllesmereUI

BagPlus for EllesmereUI is a small extension addon for EllesmereUI Bags.

This is intended as a temporary solution until BoE (including Bind-on-Use and unbound cosmetic gear), Warbound-until-Equipped, and item-level gear sorting support is added to the ordinary EllesmereUI Bags addon.

## Dependencies

Keep these addons enabled:

- EllesmereUI
- EllesmereUI Bags
- BagPlus for EllesmereUI

BagPlus does not replace EllesmereUI Bags. It extends the existing bag category system at runtime.

## WoW Forever (experimental)

Version 26.12 adds Forever interface 16001 support using EllesmereUI's client
flag. Use an EllesmereUI build with Forever support (9.5.5 or newer).

- BoE categorization and highest/lowest item-level sorting are enabled.
- Specialty bags such as quivers, ammo pouches, and profession bags retain their
  EllesmereUI category and native item order.
- Compact Category Rows, Hide Empty Recent Items, and maximum row length apply
  to the Grid display. EllesmereUI's List and Compact displays keep their own layout.
- Warbound Gear controls, the reagent-bag move button, and the extra warbank
  cleanup button are disabled on Forever. Reagent moves and Warbound slash
  commands explain that they are unsupported.
- Bank deposits use EllesmereUI's native routing on Forever.

This compatibility pass has automated coverage, including the checked-out
EllesmereUI classifier when available; it still needs in-game validation.

## Commands

```text
/bagplus boe on
/bagplus boe off
/bagplus wue on
/bagplus wue off
/bagplus ilvl asc
/bagplus ilvl desc
/bagplus ilvl off
/bagplus compact on
/bagplus compact off
/bagplus emptyrecent on
/bagplus emptyrecent off
/bagplus perrow on
/bagplus perrow off
/bagplus perrow 10
/bagplus reagents
/bagplus status
/bagplus refresh
```

## Defaults

- BoE Gear category: on
- Warbound Gear category: on (retail only)
- Item-level sorting: descending
- Compact category rows: off
- Hide empty Recent Items: on
- Change maximum items per row: off
- Maximum items per row: 12

The reagent-bag button in the inventory header, and `/bagplus reagents`, move crafting reagents from the main bags into the reagent bag without running a full bag sort.
