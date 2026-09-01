# BagPlus for EllesmereUI

BagPlus for EllesmereUI is a small extension addon for EllesmereUI Bags.

This is intended as a temporary solution until BoE, Warbound-until-Equipped, and item-level gear sorting support is added to the ordinary EllesmereUI Bags addon.

## Dependencies

Keep these addons enabled:

- EllesmereUI
- EllesmereUI Bags
- BagPlus for EllesmereUI

BagPlus does not replace EllesmereUI Bags. It extends the existing bag category system at runtime.

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
- Warbound Gear category: on
- Item-level sorting: descending
- Compact category rows: off
- Hide empty Recent Items: on
- Change maximum items per row: off
- Maximum items per row: 12

The reagent-bag button in the inventory header, and `/bagplus reagents`, move crafting reagents from the main bags into the reagent bag without running a full bag sort.
