You’re right, that was on me. Let’s fix it.

Below is a **single, clean Markdown document** you can copy‑paste directly into a `.md` file.

***

# Player Movement & Jump System (Godot 4, CharacterBody2D)

This document explains how the **movement and jump** logic works for this `CharacterBody2D` script, so future‑you can quickly remember the design.

```gdscript
extends CharacterBody2D

const Gravity := 600.0

@export var speed : float
@export var damage : int
@export var health : int
@export var height_intensity : float

@onready var animation_player := $AnimationPlayer
@onready var damager_emitter := $DamagerEmitter
@onready var character_sprite :=  $characterSprites

enum State { WALK, IDLE, ATTACK , JUMP , LAND , TAKE_OFF }

var state = State.IDLE
var height := 0.0
var height_speed := 0.0
```

The script is attached to the player’s `CharacterBody2D`. Visuals and hitbox are children:

- `AnimationPlayer` – plays animations and calls methods on specific frames.
- `characterSprites` – main sprite; moved up/down to fake vertical jump.
- `DamagerEmitter` – attack hitbox.

***

## Core Movement & Jump Variables

- `speed`: horizontal move speed on ground.
- `height_intensity`: initial “jump velocity” when leaving the ground.
- `Gravity`: constant pulling `height_speed` down each frame.
- `height`: vertical offset for the sprite only (not real physics).
- `height_speed`: current vertical speed; positive = going up, negative = falling.

Each frame, jump height is applied visually:

```gdscript
character_sprite.position = Vector2.UP * height
```

So the body stays on the ground, but the sprite moves up/down, visually simulating a jump.

***

## State Machine Overview

```gdscript
enum State { WALK, IDLE, ATTACK , JUMP , LAND , TAKE_OFF }
var state = State.IDLE
```

Meaning of states:

- `IDLE` – standing still on ground.
- `WALK` – moving on ground.
- `ATTACK` – doing an attack; movement is blocked.
- `TAKE_OFF` – starting a jump animation, still on ground.
- `JUMP` – in the air; gravity applied.
- `LAND` – landing animation while already back on ground.

All movement, jump, and animation decisions are driven by this `state`.

***

## Per‑Frame Flow (`_process`)

```gdscript
func _process(delta: float) -> void:
    # DEBUG
    print("STATE:", state, " height:", height, " height_speed:", height_speed, " velocity:", velocity)

    handle_input()
    handle_movement()
    handle_animation()
    handle_air_time(delta)
    slip_sprite()
    character_sprite.position = Vector2.UP * height
    move_and_slide()
```

Order each frame:

1. **`handle_input()`** – read player input, set velocity, maybe change state to `ATTACK` / `TAKE_OFF`.
2. **`handle_movement()`** – if not in a special state, decide between `IDLE` and `WALK`.
3. **`handle_animation()`** – choose animation based on current `state`.
4. **`handle_air_time(delta)`** – update jump height while in `JUMP`.
5. **`slip_sprite()`** – flip sprite and hitbox based on X velocity.
6. Apply `height` to the sprite.
7. `move_and_slide()` – move the body horizontally using `velocity`.

***

## Input & Ground Movement

```gdscript
func handle_input():
    var direction := Input.get_vector("ui_left", "ui_right","ui_up", "ui_down")

    if can_move():
        velocity = direction * speed
    else:
        velocity = Vector2.ZERO

    if can_attack() and Input.is_action_just_pressed("attack"):
        print(">>> ATTACK triggered")
        state = State.ATTACK
        
    if can_junp() and Input.is_action_just_pressed("jump"):
        print(">>> JUMP BUTTON PRESSED — switching to TAKE_OFF")
        state = State.TAKE_OFF
```

- Movement input creates a 2D `direction` vector.
- If `can_move()` is true, movement velocity is updated.
- If not, velocity becomes zero (e.g., while attacking).
- Attack input switches to `ATTACK` if grounded.
- Jump input switches state to `TAKE_OFF` if grounded.

Helper methods:

```gdscript
func can_attack() -> bool:
    return state == State.IDLE or state == State.WALK 

func can_move() -> bool:
    return state != State.ATTACK

func can_junp():
    return state == State.IDLE or state == State.WALK
```

- Attack and jump only allowed from `IDLE` / `WALK`.
- Movement blocked only during `ATTACK`.

***

### Ground State Switching (`handle_movement`)

```gdscript
func handle_movement():
    # If we are in a non‑movement state, do not touch the state.
    if state == State.ATTACK or state == State.TAKE_OFF or state == State.JUMP or state == State.LAND:
        return

    # Only here are we allowed to change between IDLE and WALK.
    if velocity.length() == 0:
        state = State.IDLE
    else:
        state = State.WALK
```

- If currently in `ATTACK`, `TAKE_OFF`, `JUMP`, or `LAND`, the function exits without changing state.
- Otherwise, ground state is updated:
  - No velocity → `IDLE`.
  - Some velocity → `WALK`.

This keeps simple ground movement separate from special action states.

***

## Animation State Binding

```gdscript
func handle_animation() -> void:
    match state:
        State.WALK:      animation_player.play("walk")
        State.IDLE:      animation_player.play("idle")
        State.ATTACK:    animation_player.play("punch")
        State.JUMP:      animation_player.play("jump")
        State.TAKE_OFF:  animation_player.play("take_off")
        State.LAND:      animation_player.play("land")
```

- Every frame, the active `state` decides which animation to play.
- Short one‑shot animations (`punch`, `take_off`, `land`) use **Call Method tracks** to notify the script when important frames are reached (see below).

***

## Jump Lifecycle

Jump is split into multiple states:

1. **Jump button pressed** while grounded:
   - `handle_input()` sets `state = State.TAKE_OFF`.
   - `handle_animation()` starts the `"take_off"` animation.

2. **Animation frame event**:
   - At a specific frame in `"take_off"`, AnimationPlayer’s **Call Method** track calls `on_takeoff_complete()`.

3. **Airborne phase**:
   - After `on_takeoff_complete()`, the state is `JUMP`.
   - `handle_air_time(delta)` updates `height` and applies gravity.

4. **Hitting the ground**:
   - When `height` goes below 0, `handle_air_time()` clamps it to 0 and sets `state = LAND`.

5. **Landing animation**:
   - `handle_animation()` plays `"land"`.
   - At the end of `"land"`, another Call Method track calls `on_land_complete()`.

6. **Back to idle**:
   - `on_land_complete()` resets state to `IDLE`.

This keeps timing (exact moment of takeoff and landing end) inside the animation file instead of hardcoding in the script.

***

## Take‑off Completion (`on_takeoff_complete`)

```gdscript
func on_takeoff_complete() -> void:
    print(">>> TAKE_OFF animation complete — switching to JUMP")
    state = State.JUMP
    height_speed = height_intensity
```

**How it is called:**

- In the `"take_off"` animation, there is a **Call Method** track.
- At the key frame where the character should actually leave the ground, that track calls `on_takeoff_complete()` on this script.

**What it does:**

1. `state = State.JUMP`  
   - Marks the moment where the character is considered airborne.
   - From now, movement is handled as a jump (no walking state changes).

2. `height_speed = height_intensity`  
   - Sets the initial vertical speed.
   - On upcoming frames, `handle_air_time(delta)` uses this to increase `height`, then reduces `height_speed` with gravity.

This cleanly separates *visual anticipation* (bending legs during `"take_off"`) from the moment the actual jump physics start.

***

## Air Time & Gravity (`handle_air_time`)

```gdscript
func handle_air_time(delta : float):
    if state == State.JUMP:
        print("JUMPING — height:", height, " speed:", height_speed)

        height += height_speed * delta
        if height < 0:
            print(">>> HIT GROUND — switchin g to LAND")
            height = 0
            state = State.LAND
        else:
            height_speed -= Gravity * delta
```

Only active when `state == State.JUMP`:

- Each frame:
  - Increase `height` by `height_speed * delta` (moving sprite up/down).
  - If `height < 0`, clamp to `0` and switch to `LAND`.
  - If still above ground, subtract `Gravity * delta` from `height_speed` (simulating gravity).

The function does **not** switch to `IDLE` directly. Instead:

- When `height` hits 0, it switches to `LAND`.
- The `"land"` animation then plays, and the final return to `IDLE` happens via `on_land_complete()`.

***

## Landing Completion (`on_land_complete`)

```gdscript
func on_land_complete() -> void:
    print(">>> LAND animation complete — switching to IDLE")
    state = State.IDLE
```

**How it is called:**

- In the `"land"` animation, another **Call Method** track is set up.
- At the last relevant frame (when landing visually finishes), it calls `on_land_complete()`.

**What it does:**

- Sets `state` back to `IDLE`.
- This ends the jump cycle and re‑enables normal ground behavior:
  - `handle_movement()` can again toggle between `IDLE` and `WALK`.
  - `can_attack()` and `can_junp()` allow new actions.

So the sequence is:

- `JUMP` (air time) → `LAND` (on ground, landing anim) → `IDLE` (via `on_land_complete()`).

***

## Sprite Facing and Hitbox Direction

```gdscript
func slip_sprite():
    if velocity.x > 0:
        character_sprite.flip_h = false
        damager_emitter.scale.x = 1
    elif velocity.x < 0:
        character_sprite.flip_h = true
        damager_emitter.scale.x = -1
```

- When moving right (`velocity.x > 0`):
  - Sprite not flipped.
  - Damage emitter scaled positive on X (attack points right).

- When moving left (`velocity.x < 0`):
  - Sprite flipped horizontally.
  - Damage emitter mirrored to the left.

This keeps movement direction and attack direction aligned.

***

## Quick Mental Model (Future Reminder)

- **Ground:**  
  - `velocity` + `handle_movement()` → `IDLE` vs `WALK`.
- **Actions:**  
  - `ATTACK` and `TAKE_OFF` temporarily override normal movement states.
- **Jump:**  
  - Input sets `TAKE_OFF`.  
  - `"take_off"` animation → *Call Method* → `on_takeoff_complete()` → `JUMP`.  
  - `handle_air_time()` animates `height` and gravity until ground → `LAND`.  
  - `"land"` animation → *Call Method* → `on_land_complete()` → `IDLE`.

***

