# MLeaderSmartAlign v0.5 — Live Preview & Content-Aware Alignment

First public release of the working MLeaderSmartAlign prototype for AutoCAD.

## Highlights

- geometry-aware iterative ordering of MLeaders;
- recalculation of all remaining candidates after every placement;
- Live Preview while defining alignment direction;
- original arrowhead locations are preserved;
- equal `N + 1` distribution along the selected direction;
- block/circular content aligned by content position;
- MText aligned by horizontal text center projected onto the landing line;
- `Esc` restores the original geometry;
- `MSADEBUG` diagnostic command included.

## Why it exists

The standard `MLEADERALIGN` command can distribute MLeader content, but it does not solve the ordering problem created by leader anchor geometry. On complex drawings this can leave or create crossing Leader Lines.

MLeaderSmartAlign applies the iterative algorithm originally developed for the CATIA V5 VBA Align Balloons project and adapts it to AutoCAD `MULTILEADER` objects.

## Commands

- `MLEADERSMARTALIGN`
- `MSA`
- `MSA5`
- `MSADEBUG`

## Related CATIA project

https://github.com/ivashinpavel07/CATIA-V5-VBA-Align-Balloons

Video:
https://www.youtube.com/watch?v=UVtbpVKDkvY
