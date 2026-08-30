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

## Milestone 4: Archers and ranged volleys

Archers use the existing Formation and aggregate-HP model. The player explicitly assigns a ranged target by selecting Archers and right-clicking an enemy formation. Ground right-click remains a movement order and clears the ranged target.

- Initial Archer formation: 24 soldiers, 8 columns, 1.7 spacing, 6.5 movement speed, 1.5 melee attack per second, and 25m maximum range.
- Archers do not chase an out-of-range target. They show `OUT OF RANGE` until the player repositions them.
- In range, Archers automatically rotate their formation to face the target, then fire a volley every 2 seconds.
- A volley deals `living Archers × 6` aggregate damage. It creates up to 12 visual arrows, distributed around living target soldiers. Arrow collision is visual only; aggregate damage lands once the volley reaches its target.
- Ranged casualties are selected from a randomized group of soldiers nearest the volley impact location. Melee and charge casualty rules are unchanged.
- Reciprocal melee engagement suppresses ranged fire immediately. Archers then use the normal local-melee system and are intentionally weak in melee.
- Cavalry melee and charge damage against Archers currently gain a temporary 2.0x matchup multiplier.

These range, damage, projectile, and matchup values are PoC tuning only. There is no accuracy, terrain cover, line of sight, ammunition, or individual projectile damage authority yet.

## Milestone 5: Warlord

The Warlord is a directly controlled individual unit, not a formation. He has 1000 individual HP, moves at 8 units/s, and attacks enemy formations in melee for 30 aggregate damage every second. He can follow a selected formation target within a 28m leash. His direct attacks use the target formation's normal aggregate HP and casualty representation.

Enemy formations damage the Warlord only through their soldiers physically within melee range of him; a whole formation does not automatically apply its full damage just because he contacts one edge.

- Command Aura: while the alive Warlord is within 10m of a player formation, that formation gains +10% outgoing damage.
- Battle Roar: `Q` while selected; formations within 10m when cast gain +20% outgoing damage for 10 seconds. This is an activation snapshot, does not stack, and has a 40-second cooldown.
- Formation outgoing damage is multiplied by applicable Command Aura and Battle Roar modifiers for normal melee, Cavalry charge/counter damage, and Archer volleys.
- Warlord death disables his movement, attacks, ability, Aura, and active Battle Roar recipients. The Warlord remains visibly fallen and the battle continues normally; Warlord death never determines victory.

Enemy Archers do not target the Warlord in this PoC. Warlord progression, equipment, mana, respawn, and enemy Warlords are not implemented.

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

Battles use an Age of Empires / Warcraft III-style RTS camera. The player commands formations and an individually controlled Warlord; soldiers are visible members of formations rather than independently commanded tactical actors.

## Scale and formations

The initial battle target is approximately 300 soldiers, with roughly 150 per player. Formation controls movement and tactical behavior while individual soldiers visually occupy slots, animate, and eventually represent casualties.

Facing is chosen explicitly by the player. Future combat distinguishes front, flank, and rear attacks. Initial combat resolution will be primarily formation-level, with individual soldier loss presented visually; deeper individual simulation may be considered later.

## Planned content

Initial unit types are Spearmen, Archers, Cavalry, and Warlord. Planned defensive structures are a Central Structure, Tower, and Barricade.

The Warlord fights directly, has Command Aura and Battle Roar, and buffs nearby troops. Warlord death does not automatically end a battle.

The attacker wins by destroying the Central Structure. The defender wins by surviving 20 minutes or defeating the attacking army.

## Persistent casualties

Persistent losses are a core Mikaipu principle: soldiers lost in a battle will eventually remain lost afterward. For example, an army might fall from 70 Spearmen, 45 Archers, and 35 Cavalry to 43, 31, and 19. Persistence beyond the current battle is not implemented in this proof of concept.
