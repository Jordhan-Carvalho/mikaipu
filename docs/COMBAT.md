# Combat design (agreed direction)

This document records the intended combat design and the current Milestone 2 proof of concept.

## Milestone 2 implementation

The battle test contains two 30-soldier Spearmen formations. Combat is resolved at formation level every 0.5 seconds, not through independent soldier targeting.

Temporary PoC values:

- 100 aggregate HP per soldier
- 5 base attack per surviving soldier per second
- Front attack: 1.0× damage
- Flank attack: 1.3× damage
- Rear attack: 1.6× damage
- Front/rear sectors: 60° from the defender's forward/back direction

Damage reduces aggregate formation HP. Each completed 100-HP loss removes one visible soldier; partial damage carries toward the next casualty. The visual casualty is chosen from the living soldiers nearest the attacking formation, so losses appear on the actual contact side. Fallen soldiers stop moving, while surviving soldiers recalculate their normal formation slots and close gaps. These values are PoC tuning only and are not final balance.

Melee damage uses only active combatants. A living soldier is active when at least one living opponent is within that formation's configurable melee range; Spearmen currently use 1.75 units. The formation can remain engaged with zero active melee combatants, in which case it deals no damage until soldiers make contact. When enemy chase is enabled, the enemy continues closing this gap until at least one of its soldiers reaches melee range, which prevents shallow late-battle formations from stalling. This is still aggregate formation combat, not individual combat AI.

Each formation has an always-visible world-space health bar and surviving-soldier count. Every non-zero formation damage tick creates one floating damage number near the receiving contact line. Debug builds append the incoming direction and temporary modifier.

The enemy uses deterministic direct pursuit and faces the player until engagement. `F` toggles it stationary for controlled flank/rear tests. The player can continue issuing movement and facing orders while engaged. Combat stops and both formations disengage once their centers move outside engagement range. A battle ends at zero living soldiers, showing Victory or Defeat and stopping combat ticks.

## Camera and control

Battles use an Age of Empires / Warcraft III-style RTS camera. The player commands formations and, in a later milestone, a Captain; soldiers are visible members of those formations rather than independently commanded tactical actors.

## Scale and formations

The initial battle target is approximately 300 soldiers, with roughly 150 per player. Formation controls movement and tactical behavior while individual soldiers visually occupy slots, animate, and eventually represent casualties.

Facing is chosen explicitly by the player. Future combat distinguishes front, flank, and rear attacks. Initial combat resolution will be primarily formation-level, with individual soldier loss presented visually; deeper individual simulation may be considered later.

## Planned content

Initial unit types are Spearmen, Archers, Cavalry, and Captain. Planned defensive structures are a Central Structure, Tower, and Barricade.

The Captain will fight directly, have equipment and abilities, and buff nearby troops. A possible ability is Battle Roar. Captain death does not automatically end a battle.

The attacker wins by destroying the Central Structure. The defender wins by surviving 20 minutes or defeating the attacking army.

## Persistent casualties

Persistent losses are a core Mikaipu principle: soldiers lost in a battle will eventually remain lost afterward. For example, an army might fall from 70 Spearmen, 45 Archers, and 35 Cavalry to 43, 31, and 19. Persistence beyond the current battle is not implemented in this proof of concept.
