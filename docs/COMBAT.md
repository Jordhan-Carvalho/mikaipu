# Combat design (agreed direction)

This document records the intended combat design. Only formation control is implemented in the current proof of concept.

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

Persistent losses are a core Mikaipu principle: soldiers lost in a battle will eventually remain lost afterward. For example, an army might fall from 70 Spearmen, 45 Archers, and 35 Cavalry to 43, 31, and 19. Persistence is not implemented in this proof of concept.
