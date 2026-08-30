# Known issues

## Milestone 1 formation rotation

An extreme or full facing change can occasionally make soldiers converge toward the formation center before they reorganize into their new slots. This is accepted for the current proof of concept because ordinary movement and moderate turns work well.

Milestone 2 intentionally does not change this movement behavior.

## Milestone 4 ranged limitations

Arrows are visual-only and do not collide with terrain or individual soldiers. Archers use a formation-center range check and automatic turn-in-place behavior; terrain cover, elevation, and line of sight are not implemented.

## Milestone 5 Warlord limitations

Enemy Archers do not target the Warlord. Enemy formation damage against him is a local proximity abstraction and does not yet animate individual soldiers turning to attack him.

## Milestone 6 defensive limitations

Barricades use deterministic segment blocking for formation orders, charges, and individual soldier movement rather than NavMesh pathfinding or physical collision. Formations still need manual routing around barricade ends. Towers use nearest-target logic and damage feedback without dedicated tower projectile visuals. Structures do not have repair, construction, destruction physics, or persistence.

## Scenario 01 AI limitations

Defender formations use anchor/radius hold behavior rather than strategic AI. Defender Cavalry does not autonomously charge, and the Defender Warlord remains a targetable Aura guardian without autonomous attacks.
