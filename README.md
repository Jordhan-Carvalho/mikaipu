# Mikaipu

Mikaipu is an experimental real-time strategy game. This repository currently contains a 3D proof of concept for formation movement, explicit facing, and basic formation-level Spearmen combat.

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
- **Left click**: select or deselect the formation.
- **Right click ground**: move the selected formation while retaining its facing.
- **Right-click drag**: choose its destination (where the drag starts) and facing (from start toward release). A cyan preview appears before release.
- **Escape**: cancel a pending right-click drag.
- **F**: toggle enemy chase. The enemy chases by default; turn it stationary to set up flank and rear tests.
- **R**: restart the battle scene.

## Combat testing

The player formation starts blue; the enemy Spearmen formation starts red and approaches automatically. Combat begins when the formations are close enough and they exchange formation-level damage every 0.5 seconds. Only living soldiers within their formation's 1.75-unit melee range of an enemy contribute damage. If late-battle survivors are too far apart to fight, the chase-enabled enemy closes the remaining gap until contact is restored. Movement and facing orders remain available during engagement; moving outside combat range disengages the formations and stops damage.

- **Front**: let the two formations meet while facing each other. Casualties should be similar.
- **Flank**: press **F**, move the player beside the stationary enemy, and face its side before engaging. The enemy receives 1.3× damage.
- **Rear**: with the enemy stationary, move behind it and face toward its rear. The enemy receives 1.6× damage.

Each formation shows a world-space health bar and survivor count. Floating damage numbers appear at the contact line; debug builds include their directional modifier. Select the blue formation to view its alive count, combat state, and current incoming direction. Casualties fall on the side nearest the attacking formation, then survivors close the gap. `VICTORY` or `DEFEAT` ends combat when one formation reaches zero soldiers.

## Current architecture

- `scenes/battle/battle_test.tscn` assembles the arena, camera, player/enemy formations, combat resolver, input controller, and HUD.
- `scenes/formations/formation.tscn` and `scenes/units/soldier.tscn` are reusable scene roots; their scripts generate the placeholder visuals and formation members at runtime.
- `scripts/camera/rts_camera.gd` provides the fixed-angle RTS camera.
- `scripts/formations/formation.gd` owns formation state, aggregate health, formation slots, orders, selection, and casualty reorganization.
- `scripts/battle/combat_resolver.gd` owns simple enemy pursuit, engagement detection, directional classification, and periodic formation-level damage.
- `scripts/units/soldier.gd` makes each visible soldier move directly toward its assigned slot and renders simple fallen casualties.
- `scripts/input/formation_input.gd` raycasts the ground plane and translates mouse gestures into selection and movement orders.

This milestone deliberately has no unit-level combat AI, pathfinding, persistence, multiplayer, world map, Captain, buildings, archers, cavalry, or economy.
