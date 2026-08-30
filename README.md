# Mikaipu

Mikaipu is an experimental real-time strategy game. This repository currently contains a 3D proof of concept for formation movement, explicit facing, melee/ranged formation combat, Cavalry charges, Spearmen Brace, Archers, a Warlord, and an attacker-versus-defender objective battle.

## Run

1. Install Godot 4.7.2 (or a compatible Godot 4 release).
2. Import `project.godot` in the Godot Project Manager.
3. Run the project with **F6/F5**.

The main scene is `scenes/battle/battle_test.tscn`.

## Runtime debugging

This project includes the **Godot MCP Bridge** editor addon in `addons/godot-mcp` and enables it through `project.godot`. The matching `godot-mcp` server is registered in Codex on local bridge port `6510`.

Godot 4.7.2 is installed locally. Restart Codex so it reloads the MCP configuration, then open this project in the Godot editor and run the scene. The MCP tools can then inspect runtime errors, scene nodes and properties, screenshots, and console output.

## Controls

- **WASD**: pan the RTS camera.
- **Mouse wheel**: zoom in/out.
- **Left click**: select exactly one player formation or the Warlord.
- **Right click ground**: move the selected formation while retaining its facing.
- **Right-click drag**: choose its destination (where the drag starts) and facing (from start toward release). A cyan preview appears before release.
- **Right-click enemy while Archers are selected**: assign a formation or defensive structure as the Archer ranged target.
- **Right-click enemy structure while Spearmen/Cavalry are selected**: approach and attack that structure.
- **Right-click ground while Warlord is selected**: move the Warlord independently.
- **Right-click enemy while Warlord is selected**: approach and attack that formation or structure.
- **Escape**: cancel a pending right-click drag.
- **Q**: with Cavalry selected, charge the nearest enemy; with Spearmen selected, toggle Brace.
- **Q with Warlord selected**: activate Battle Roar.
- **E**: test-only trigger for the enemy Cavalry to charge the nearest player formation.
- **F**: toggle enemy chase. The enemy chases by default; turn it stationary to set up flank and rear tests.
- **G**: toggle local-melee debug lines for active soldiers and their formation slots.
- **R**: restart the battle scene.

## Objective battle

The player is the **Attacker**. Destroy the Defender's Central Keep before the timer reaches zero. The battle scene uses a 3-minute PoC timer; `BattleManager.design_timer_seconds` retains the intended 20-minute value.

Two Towers visibly fire arrows at nearby attackers. Six Barricades form a continuous full-width line: create a breach by destroying a section, then move through it. Destroying the Keep gives `VICTORY`; timer expiry or loss of every attacker formation and the Warlord gives `DEFEAT`. Warlord death alone does not end the battle.

## Scenario 01: Fortified Keep Assault

The battle scene is now the first integrated assault: 120 Attacker soldiers and Warlord versus an equivalent Defender army, a six-segment barricade line, two Towers, and the Central Keep. The normal scenario timer is 15 minutes; set `BattleManager.use_test_timer` in the Inspector for the 3-minute debug timer. Defender Spearmen hold behind the barricades until attackers approach, Defender Archers hold and fire from the rear, and Defender Cavalry only responds near the defensive zone.

## Combat testing

The scene has player Spearmen/Cavalry and matching enemy formations. Combat begins when opposing formations are close enough; only living soldiers physically within their unit melee range contribute formation-level damage. Movement and facing orders remain available during engagement; leaving engagement range disengages and stops normal damage.

- **Front**: let the two formations meet while facing each other. Casualties should be similar.
- **Cavalry charge**: select player Cavalry, position it at least 7 units from an enemy and face it toward the enemy, then press **Q**. A completed charge has one strong impact before normal melee resumes.
- **Brace**: select stationary player Spearmen and press **Q**. After a short preparation, press **E** to test a frontal enemy-Cavalry charge. Front charges are countered; flank and rear charges are not.
- **Flank**: press **F**, move the player beside the stationary enemy, and face its side before engaging. The enemy receives 1.3× damage.
- **Rear**: with the enemy stationary, move behind it and face toward its rear. The enemy receives 1.6× damage.

Each formation and structure shows a world-space health bar. Floating damage numbers appear at the contact line; charge impacts are labelled. Select a player formation to view its ability state and current incoming direction. Casualties fall on the side nearest the attacking formation, then survivors close the gap.

During engagement, only nearby soldiers can temporarily leave their exact slots to face and visually strike a nearby enemy. Their movement stays tethered to their assigned formation slot, while CombatResolver remains the authority for all damage and casualties.

## Current architecture

- `scenes/battle/battle_test.tscn` assembles the arena, objective defenses, camera, formations, combat resolver, input controller, and HUD.
- `scenes/formations/formation.tscn` and `scenes/units/soldier.tscn` are reusable scene roots; their scripts generate the placeholder visuals and formation members at runtime.
- `scripts/camera/rts_camera.gd` provides the fixed-angle RTS camera.
- `scripts/formations/formation.gd` owns formation state, aggregate health, formation slots, orders, selection, and casualty reorganization.
- `scripts/battle/combat_resolver.gd` owns simple enemy pursuit, formation combat, structure attack ticks, and tower fire; `scripts/battle/battle_manager.gd` owns the timer and objective results.
- `scripts/units/soldier.gd` makes each visible soldier move directly toward its assigned slot and renders simple fallen casualties.
- `scripts/input/formation_input.gd` raycasts the ground plane and translates mouse gestures into selection and movement orders.

Archers hold their position when a selected target is out of range. In range, they turn toward it and fire periodic visual volleys. They stop firing as soon as they enter melee, where they are deliberately weak. Spearmen and Cavalry retain their existing controls; Cavalry are especially dangerous when they reach exposed Archers.

The Warlord is individually selectable and moves independently of formations. Keep him within 10m of allied formations for Command Aura (+10% damage). Battle Roar gives formations near him at activation +20% damage for 10 seconds, then has a 40-second cooldown. His death removes all buffs and displays `WARLORD FALLEN`, but the battle continues.

This milestone deliberately has no unit-level combat AI, pathfinding, persistence, multiplayer, world map, construction/repair, equipment, advanced line of sight, ammo, or economy.
