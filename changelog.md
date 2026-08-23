# Changelog

All notable changes to BagPlus for EllesmereUI will be documented in this file.

## 26.3 - 2026-08-23

- Added an opt-in Compact Category Rows setting and `/bagplus compact on|off` command for packing short All Items category sections left-to-right.
- Added a BagPlus-only Hide Empty Recent Items option and `/bagplus emptyrecent on|off` command that temporarily hides EllesmereUI's Recent Items quickview only while it has no items.
- Tightened compact category sizing to title width and hides compact-only header separator artifacts.
- Adjusted EllesmereUI's Auto-Size to Fit height after compacting so the bag frame follows the compacted All Items layout.

## 26.2 - 2026-08-22

- Changed the BagPlus gear sort option in EllesmereUI from an on/off switch to a dropdown so all three sort modes are selectable.
- Added a release script that builds a clean addon zip from the `.toc` version and validates the matching Git tag.
- Moved runtime addon files into `src/BagPlus_for_EllesmereUI/` while keeping release zips installable at the normal addon folder path.
- Split the packaged user README from maintainer-only release notes.

## 26.1 - 2026-08-19

- Added Warbound Gear and BoE Gear categories for EllesmereUI Bags.
- Added item-level gear sorting for armor and weapons with highest-first, lowest-first, and off modes.
- Added a BagPlus page inside the EllesmereUI options sidebar.
- Added `/bagplus` commands for category toggles, item-level sort mode, status, and refresh.
