# Known issues

## Milestone 1 formation rotation

An extreme or full facing change can occasionally make soldiers converge toward the formation center before they reorganize into their new slots. This is accepted for the current proof of concept because ordinary movement and moderate turns work well.

Milestone 2 intentionally does not change this movement behavior.

## Milestone 4 ranged limitations

Arrows are visual-only and do not collide with terrain or individual soldiers. Archers use a formation-center range check and automatic turn-in-place behavior; terrain cover, elevation, and line of sight are not implemented.
