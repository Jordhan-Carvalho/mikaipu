# Combat design (agreed direction)

This document records the intended combat design and the current Milestone 3 proof of concept.

## Milestone 3: Cavalry Charge and Spearmen Brace

The battle test now has player Spearmen (30) and Cavalry (18), against matching enemy formations. Unit definitions centralize movement, spacing, melee, charge, and brace tuning.

- Cavalry move at 10 units/s, use 2.0 spacing, and have lower sustained melee attack than Spearmen.
- `Q` starts a player Cavalry charge toward its nearest hostile formation when it is 7+ units away and facing within 35 degrees. A charge moves at 1.5x speed, requires 7 units of travel, resolves once at actual melee contact, then requires disengagement and 7 units of separation to reset.
- Charge impact is formation-level: active nearby cavalry × 25 × speed/travel factor × direction. Temporary direction multipliers are Front 1.0, Flank 1.5, Rear 2.0.
- `Q` toggles Spearmen Brace. Spearmen must remain within 0.2 units of their destination for 0.6 seconds; any movement/facing order cancels Brace.
- A Braced Spearmen formation hit from the front receives only 15% of charge impact and deals a one-time counter-hit of active nearby Spearmen × 25. Brace does not protect flank/rear impacts.

Charge and counter impacts still use aggregate formation HP and the existing casualty-selection and floating-feedback systems. Cavalry soldiers stay in formation slots during the approach; local melee resumes after impact. These values are deliberate PoC tuning, not final balance.

## Milestone 2 baseline

Milestone 2 introduced 30-soldier Spearmen formations and formation-level combat every 0.5 seconds, not independent soldier targeting. Milestone 3 retains this baseline for normal melee and extends it with Cavalry charge and Spearmen Brace.

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

During formation engagement, soldiers enter a visual-only local melee mode as opponents come within the configured 6.5-unit local acquisition radius. They remain tethered within 5 units of their assigned slots, so rear and edge soldiers can feed into combat without becoming independent battlefield units. Up to six friendly soldiers may visually engage each nearby opponent; this deliberately lets full formations continue showing activity against a reduced enemy line. An advancing enemy formation now keeps closing until all living soldiers in both paired formations are within melee range, rather than stopping at first contact. Soldier attack motion does not calculate damage; CombatResolver continues to count only living soldiers physically within melee range as active combatants. `G` toggles local-melee target and slot debug lines.

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
