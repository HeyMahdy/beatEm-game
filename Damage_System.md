

***

# Damage System: Player → Barrel (Godot 4)

This document explains how the player’s attack damages a barrel and how the barrel is destroyed. It also covers:

- Damage emitter / receiver scripts
- Signals used for damage
- Collision layers & masks setup
- Action container and Y‑sort

Everything here is based on these two scripts:

```gdscript
# barrel.gd
extends StaticBody2D

@onready var damage_receiver := $DamageReceiver

func _ready() -> void:
    damage_receiver.damage_received.connect(on_damage_receive.bind())

func on_damage_receive(damage:int):
    queue_free()
```

```gdscript
# character_body_2d.gd (player)
extends CharacterBody2D

@export var damage : int

@onready var damager_emitter := $DamagerEmitter
# ...

func _ready() -> void:
    damager_emitter.area_entered.connect(on_damage_receiver.bind())
    print("READY — state:", state)

func on_damage_receiver(damager_receiver:DamageReceiver):
    damager_receiver.damage_received.emit(damage)
    print("Damage given:", damage)
```

Plus the `DamageReceiver` script (used by both barrel and enemies):

```gdscript
# damage_receiver.gd (on the DamageReceiver Area2D)
extends Area2D

signal damage_received(damage: int)
```

***

## 1. High‑level Data Flow

1. Player attack hitbox (`DamagerEmitter` – an `Area2D`) overlaps a barrel’s `DamageReceiver` (`Area2D`).
2. The player’s script receives the `area_entered` signal from `DamagerEmitter`.
3. The player calls `damage_receiver.damage_received.emit(damage)`.
4. The barrel’s script has connected to `damage_received`, so its `on_damage_receive(damage)` runs.
5. Barrel reacts by calling `queue_free()` → it is removed from the scene.

So: collision → signal → damage emit → barrel reacts.

***

## 2. Barrel Node Setup

Scene tree (simplified):

- `barrel` (`StaticBody2D`)
  - `DamageReceiver` (`Area2D`)
    - `CollisionShape2D`

Script: `barrel.gd` is attached to the `barrel` node.

```gdscript
extends StaticBody2D

@onready var damage_receiver := $DamageReceiver

func _ready() -> void:
    damage_receiver.damage_received.connect(on_damage_receive.bind())

func on_damage_receive(damage:int):
    queue_free()
```

Key points:

- `damage_receiver` is the child `Area2D` that listens for incoming damage.
- In `_ready()`, the barrel connects to the `DamageReceiver`’s `damage_received` signal.
  - When someone emits `damage_received`, `on_damage_receive()` runs.
- `on_damage_receive(damage:int)` currently ignores the damage value and instantly `queue_free()`s (destroy barrel).

If later you want HP for the barrel, this is where you would subtract damage instead of immediately freeing.

***

## 3. DamageReceiver: Shared Damage Interface

The `DamageReceiver` node is an `Area2D` with a simple script:

```gdscript
extends Area2D

signal damage_received(damage: int)
```

This node:

- Holds the `damage_received` signal.
- Does NOT decide what to do when damage is received.
- Is used by any object that can be damaged (barrels, enemies, etc.).

Each damageable object connects to this signal in its own script and decides how to react.

Example: barrel connects in `_ready()`:

```gdscript
damage_receiver.damage_received.connect(on_damage_receive.bind())
```

So when the player emits `damage_received` on this `Area2D`, the barrel reacts.

***

## 4. Player DamageEmitter Setup

Scene tree (simplified):

- `player` (`CharacterBody2D`)
  - `AnimationPlayer`
  - `DamagerEmitter` (`Area2D`)
    - `CollisionShape2D`

The script `character_body_2d.gd` is attached to `player`. Relevant parts:

```gdscript
@export var damage : int
@onready var damager_emitter := $DamagerEmitter

func _ready() -> void:
    damager_emitter.area_entered.connect(on_damage_receiver.bind())
```

What this does:

- `damager_emitter` is the child `Area2D` used as the attack hitbox.
- In `_ready()`, the player connects the `DamagerEmitter`’s `area_entered` signal to `on_damage_receiver`.

Godot automatically passes the `Area2D` that entered as the argument to `on_damage_receiver`:

```gdscript
func on_damage_receiver(damager_receiver:DamageReceiver):
    damager_receiver.damage_received.emit(damage)
    print("Damage given:", damage)
```

Meaning:

- When `DamagerEmitter` overlaps an `Area2D` that has the `DamageReceiver` script:
  - `damager_receiver` is that `DamageReceiver` node.
  - Player calls `damage_received.emit(damage)` on it.
  - Any script that connected to `damage_received` for this receiver (like `barrel.gd`) will be notified and react.

This is how the player can damage different objects by reusing the same interface.

***

## 5. Collision Layers & Masks (who can hit whom)

You have:

- Player’s `DamagerEmitter` (`Area2D`)
- Barrel’s `DamageReceiver` (`Area2D`)

Both use Godot’s collision layers/masks (seen on the right in your screenshots).

Typical logic:

- The `DamagerEmitter`:
  - Layer: e.g. `EnemyDamagerEmitter` or similar.
  - Mask: includes `DestructablesDamageReceiver`, `EnemyDamageReceiver`, etc.
  - Means: the emitter “looks for” things that are on these receiver layers.

- The `DamageReceiver` on the barrel:
  - Layer: something like `DestructablesDamageReceiver`.
  - Mask: usually doesn’t matter much here (it’s an Area2D that mostly just receives).

Because:

- The emitter’s MASK must include the receiver’s LAYER.
- When the shapes overlap and layers/masks match, Godot triggers `area_entered` on the emitter.

So in your setup:

1. Barrel’s `DamageReceiver` node is put on the collision layer `DestructablesDamageReceiver`.
2. Player’s `DamagerEmitter` mask includes `DestructablesDamageReceiver`.
3. When the emitter overlaps the barrel’s `DamageReceiver`, `area_entered(damage_receiver)` fires.

If layers/masks are wrong, you will NOT get `area_entered`, so this is the first place to check when damage “stops working”.

***

## 6. Action Container & Y‑Sort in World

Your main world scene (simplified):

- `world` (root, likely `Node2D`)
  - `stage` (background / ground, with Y‑Sort ON)
  - `actionContainer`
    - `player`
    - `barrel`
    - (other interactable actors)

Key points:

- `actionContainer` holds all interactive actors (player, barrels, enemies).
- Y‑Sort is enabled on the parent (e.g. on `stage` or `actionContainer`), meaning:
  - Children are drawn according to their local `y` position.
  - Lower on the screen (bigger y) = drawn on top.
- This affects only rendering order, not physics or signals.

Important for damage:

- Y‑Sort does NOT change collision or signals, only draw order.
- You can move player and barrel around; as long as:
  - `DamagerEmitter` and `DamageReceiver` layers/masks are set correctly, and
  - They overlap in 2D space,
  - The damage signal logic works regardless of Y‑Sort.

So: `actionContainer` + Y‑Sort = purely visual sorting of characters/props by vertical position.

***

## 7. Signal Flow: Step‑by‑Step Example

Let’s trace a single hit:

1. Player presses attack:
   - Player state becomes `ATTACK`.
   - `AnimationPlayer` plays `"punch"`.
   - `DamagerEmitter` is positioned near the player’s hand (and maybe enabled only during hit frames).

2. `DamagerEmitter` overlaps a barrel’s `DamageReceiver`:
   - Collision layers/masks match → Godot triggers `area_entered` on `DamagerEmitter`.

3. `area_entered` signal fires:
   - In `_ready()`, we connected:
     ```gdscript
     damager_emitter.area_entered.connect(on_damage_receiver.bind())
     ```
   - So `on_damage_receiver(damager_receiver)` is called.
   - `damager_receiver` is the barrel’s `DamageReceiver` node.

4. Player script emits damage:
   ```gdscript
   func on_damage_receiver(damager_receiver:DamageReceiver):
       damager_receiver.damage_received.emit(damage)
       print("Damage given:", damage)
   ```
   - `damage` is the exported damage value from the player.
   - The `DamageReceiver` broadcasts `damage_received(damage)`.

5. Barrel script reacts:
   - In `_ready()`:
     ```gdscript
     damage_receiver.damage_received.connect(on_damage_receive.bind())
     ```
   - So when the signal is emitted, `on_damage_receive(damage)` runs.

6. Barrel destroys itself:
   ```gdscript
   func on_damage_receive(damage:int):
       queue_free()
   ```
   - Barrel node is removed from the tree → visually disappears and no longer collides.

***

## 8. Why Use Signals Instead of Direct Calls?

Advantages of this pattern:

- Player doesn’t need to know what it hit (barrel, enemy, destructible). It just says:
  - “Whatever you are, take `damage`.”
- Each object decides how to react:
  - Barrel: destroy immediately.
  - Enemy: subtract HP, maybe trigger hurt animation.
- You can add new damageable objects without changing the player script — as long as they have a `DamageReceiver` and connect to `damage_received`.

