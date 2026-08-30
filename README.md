# Mikaipu

Mikaipu is an experimental real-time strategy game. This repository currently contains a 3D proof of concept for formation movement, explicit facing, formation-level combat, Cavalry charges, and Spearmen Brace.

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
- **Left click**: select exactly one player formation (Spearmen or Cavalry).
- **Right click ground**: move the selected formation while retaining its facing.
- **Right-click drag**: choose its destination (where the drag starts) and facing (from start toward release). A cyan preview appears before release.
- **Escape**: cancel a pending right-click drag.
- **Q**: with Cavalry selected, charge the nearest enemy; with Spearmen selected, toggle Brace.
- **E**: test-only trigger for the enemy Cavalry to charge the nearest player formation.
- **F**: toggle enemy chase. The enemy chases by default; turn it stationary to set up flank and rear tests.
- **G**: toggle local-melee debug lines for active soldiers and their formation slots.
- **R**: restart the battle scene.

## Combat testing

The scene has player Spearmen/Cavalry and matching enemy formations. Combat begins when opposing formations are close enough; only living soldiers physically within their unit melee range contribute formation-level damage. Movement and facing orders remain available during engagement; leaving engagement range disengages and stops normal damage.

- **Front**: let the two formations meet while facing each other. Casualties should be similar.
- **Cavalry charge**: select player Cavalry, position it at least 7 units from an enemy and face it toward the enemy, then press **Q**. A completed charge has one strong impact before normal melee resumes.
- **Brace**: select stationary player Spearmen and press **Q**. After a short preparation, press **E** to test a frontal enemy-Cavalry charge. Front charges are countered; flank and rear charges are not.
- **Flank**: press **F**, move the player beside the stationary enemy, and face its side before engaging. The enemy receives 1.3× damage.
- **Rear**: with the enemy stationary, move behind it and face toward its rear. The enemy receives 1.6× damage.

Each formation shows a world-space health bar, survivor count, and ability state. Floating damage numbers appear at the contact line; charge impacts are labelled. Select either blue player formation to view its ability state and current incoming direction. Casualties fall on the side nearest the attacking formation, then survivors close the gap. `VICTORY` or `DEFEAT` ends combat when a team has no surviving formations.

During engagement, only nearby soldiers can temporarily leave their exact slots to face and visually strike a nearby enemy. Their movement stays tethered to their assigned formation slot, while CombatResolver remains the authority for all damage and casualties.

## Current architecture

- `scenes/battle/battle_test.tscn` assembles the arena, camera, player/enemy formations, combat resolver, input controller, and HUD.
- `scenes/formations/formation.tscn` and `scenes/units/soldier.tscn` are reusable scene roots; their scripts generate the placeholder visuals and formation members at runtime.
- `scripts/camera/rts_camera.gd` provides the fixed-angle RTS camera.
- `scripts/formations/formation.gd` owns formation state, aggregate health, formation slots, orders, selection, and casualty reorganization.
- `scripts/battle/combat_resolver.gd` owns simple enemy pursuit, engagement detection, directional classification, and periodic formation-level damage.
- `scripts/units/soldier.gd` makes each visible soldier move directly toward its assigned slot and renders simple fallen casualties.
- `scripts/input/formation_input.gd` raycasts the ground plane and translates mouse gestures into selection and movement orders.

This milestone deliberately has no unit-level combat AI, pathfinding, persistence, multiplayer, world map, Captain, buildings, archers, or economy.
