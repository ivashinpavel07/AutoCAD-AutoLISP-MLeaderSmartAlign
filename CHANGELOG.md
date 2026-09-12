# Changelog

## v0.5

- Added content-aware placement reference.
- MText uses horizontal text center projected onto the landing line.
- Block/circular content uses the block content position.
- Preserved the iterative CATIA-style geometry recalculation algorithm.
- Preserved Live Preview and original arrowhead restoration.

## v0.4

- Added full content-center alignment for MText and block content.
- Improved visual spacing for annotations with different widths.

## v0.3

- Added Live Preview while specifying alignment direction.
- Added adaptive preview throttling for large selections.
- Added cancellation with restoration of original geometry.

## v0.2

- Reimplemented the original CATIA-style iterative algorithm.
- For every target position, recalculates the angle for every remaining MLeader.
- Uses `N + 1` spacing so annotations occupy internal alignment points.

## v0.1

- Initial AutoCAD prototype.
