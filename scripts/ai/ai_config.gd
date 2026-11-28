class_name AIConfig
extends RefCounted
## Central tuning for infantry behaviour under fire. Every number the
## suppression model uses lives here, so balancing does not mean hunting for
## magic constants across the AI code. Values are abstract game parameters.

# ------------------------------------------------------------------ suppression levels
## Suppression (0–100) thresholds of levels 1..3. Level 4 (panic) also needs
## accumulated stress or low morale — never a single burst.
const LEVEL_AT := [15.0, 40.0, 68.0]
const PANIC_SUPP := 88.0
const PANIC_STRESS := 60.0          # ...and stress above this, or morale below PANIC_MORALE
const PANIC_MORALE := 30.0
const LEVEL_NAMES_UK := ["спокійний", "напружений", "під вогнем", "притиснутий", "паніка"]
static var LEVEL_NAMES = LEVEL_NAMES_UK   # the current language (Loc.localize_all)

# what each level does (index = level)
const LEVEL_ACC := [1.0, 0.88, 0.65, 0.4, 0.1]        # hit chance multiplier
const LEVEL_ROF := [1.0, 1.15, 1.5, 2.2, 4.0]         # pause between bursts multiplier
const LEVEL_SPEED := [1.0, 0.92, 0.8, 0.65, 0.5]      # movement speed multiplier
## chance per AI tick (~0.45 s) that a soldier in cover rises to look / shoot;
## the rest of the time he stays below the parapet and sees nothing
const LEVEL_PEEK := [1.0, 0.85, 0.4, 0.12, 0.0]
## chance per tick that he obeys a move / assault order across open ground
## (multiplied by personal discipline)
const LEVEL_MOVE := [1.0, 1.0, 0.45, 0.08, 0.0]

# ------------------------------------------------------------------ gain
## How much cover reduces suppression gain, by threat kind. A trench stops
## bullets but the crack of rounds overhead and blast still frighten.
const COVER_PROTECT := {"bullet": 0.45, "crack": 0.25, "blast": 0.35, "wound": 0.0}
## sustained fire escalates: recent incoming intensity ("heat") multiplies gain
const HEAT_DECAY := 6.0             # heat units per second
const HEAT_GAIN_DIV := 160.0        # gain multiplier = 1 + heat / HEAT_GAIN_DIV
## every weapon's "supp" value is scaled by this (one burst is many rounds)
const GAIN_SCALE := 0.32
## gain saturates: each event moves suppression a share of the way to 100
const SATURATION := 115.0
const HEAT_MAX := 120.0
## rounds passing close overhead / beside (along the last metres of a burst)
const CRACK_RADIUS := 2.6
const CRACK_LENGTH := 25.0
const CRACK_FACTOR := 0.45          # share of the weapon's "supp" value
## near-miss radius around the impact point, by weapon sound class
const NEAR_MISS_RADIUS := {"rifle": 3.5, "mg": 5.0, "hmg": 6.0}
## explosions: suppression = power * BLAST_SUPP * falloff, up to BLAST_REACH × radius
const BLAST_SUPP := 0.75
const BLAST_REACH := 3.5          # × radius, plus BLAST_REACH_POWER × power metres
const BLAST_REACH_POWER := 0.09
const BLAST_FLINCH := 22.0          # gain above this makes the soldier drop for a moment

# ------------------------------------------------------------------ recovery
## after the last threat event suppression does not fall at once
const HOLD_BASE := 2.5              # s
const HOLD_PER_LEVEL := 1.5         # s extra per level
const DECAY_BASE := 4.0             # per second once the hold is over
const DECAY_COVER_BONUS := 2.0      # extra per second in good cover (>= 0.4)
const DECAY_SUPPORT := 1.25         # multiplier with >= 2 calm comrades within SUPPORT_RANGE
const DECAY_LEADER := 1.15          # multiplier with own leader within SUPPORT_RANGE
const SUPPORT_RANGE := 9.0
## long-term stress: builds while under fire, fades slowly; slows recovery and
## keeps the soldier cautious after the shooting stops
const STRESS_GAIN := 0.5           # per second per (level >= 2) * suppression/100
const STRESS_DECAY := 0.9           # per second when level <= 1
const STRESS_SLOWS := 0.5           # decay *= 1 - stress/100 * STRESS_SLOWS
const STRESS_FLOOR := 0.35          # suppression cannot fall below stress * this
const MORALE_PER_SUPP := 0.025

# ------------------------------------------------------------------ individual traits
## grit: personal resistance to suppression; discipline: will to obey under fire
const GRIT_RANGE := Vector2(0.8, 1.2)
const DISCIPLINE_RANGE := Vector2(0.75, 1.25)

# ------------------------------------------------------------------ suppressive fire
## machine guns and vehicles keep firing at the last known position of an
## enemy that ducked out of sight
const AREA_FIRE_MEMORY := 12.0      # s since the enemy was last seen there
const AREA_FIRE_RADIUS := 4.0       # tracer scatter around the point
const AREA_FIRE_SUPP := 1.6         # near-miss multiplier for area fire


## Where to aim suppressive fire at a known position: the parapet line for a
## man in a trench (below it he cannot be seen), chest height in the open.
# ------------------------------------------------------------------ grenades
const NADE_MAX_LEVEL := 3              # pinned (level 3+) men do not throw
const NADE_INFO_AGE := 8.0             # s: blind / corner throws need fresh information
const NADE_RANGE_HAND := Vector2(7.0, 26.0)
const NADE_RANGE_GL := Vector2(15.0, 80.0)
const NADE_RANGE_CORNER := Vector2(3.0, 9.0)
const NADE_SAFE_HAND := 7.5            # no comrade within this of the impact point
const NADE_SAFE_GL := 6.0
const NADE_MIN_COVER := 0.3            # target cover needed to be worth a grenade
const NADE_LAST_DIST := 15.0           # the last hand grenade only this close (or clearing a trench)
const NADE_CLAIM_CELL := 5.0           # m: one grenade per such spot ...
const NADE_CLAIM_TIME := 8.0           # ... per this many seconds, per squad
const NADE_WINDOW := 20.0              # s: at most NADE_PER_WINDOW grenades per squad
const NADE_PER_WINDOW := 2
const NADE_CD := Vector2(7.0, 11.0)    # personal cooldown after a throw
const CORNER_INFO_AGE := 20.0          # corner grenade only if an enemy was known there this recently

# ------------------------------------------------------------------ assault
const ASSAULT_LOSS_WINDOW := 45.0      # s: recent losses counted over this
const ASSAULT_PAUSE_LOSSES := 0.25     # share of the squad lost recently -> pause and dig in
const ASSAULT_PAUSE_TIME := 20.0       # s
const ASSAULT_ABORT_LEFT := 0.5        # active share at or below which the assault is called off
const ASSAULT_BOUND := 14.0            # m per bound
const ASSAULT_BOUND_UNDER_FIRE := 8.0  # m per bound when the squad is under fire
const CASUALTY_SHOCK := 16.0           # suppression to comrades within CASUALTY_SHOCK_R of a man going down
const CASUALTY_SHOCK_R := 12.0


# ------------------------------------------------------------------ intelligence (commander's fog)
const INTEL_CONFIRM_Q := 0.6          # sighting quality needed for an exact, CONFIRMED contact
const INTEL_FUZZ_MAX := 22.0          # m: position error of a sighting at quality 0
const INTEL_HEARD_ERR := 18.0         # m: position error of a contact known only by gunfire
const INTEL_CONFIRM_HOLD := 3.0       # s a contact stays CONFIRMED after the last look
const INTEL_PROBABLE_STATIC := 25.0   # s PROBABLE for a target that was still ...
const INTEL_PROBABLE_MOVING := 9.0    # ... or moving when last seen
const INTEL_LAST_STATIC := 110.0      # s more as LAST KNOWN position
const INTEL_LAST_MOVING := 35.0
const INTEL_LOST_TIME := 40.0         # s a LOST contact is still shown (faint) before it is forgotten
const INTEL_DESTROYED_SHOW := 45.0    # s the "hit" mark stays
const INTEL_FOLIAGE_CUT := 0.35       # lifetimes shorter by this share in full foliage
## the enemy's own sources
const ENGINE_HEARING := 120.0         # m: an enemy soldier hears a moving vehicle
const RER_AREA := 45.0                # m: a radio-recon fix reveals only troops under the drone ...
const RER_ERROR := 15.0               # ... with this position error

## psychological states (Soldier.psych_state) on top of the suppression levels
const PSY_NAMES_UK := ["СПОКІЙ", "НАПОГОТОВІ", "СТРЕС", "ПРИДУШЕНИЙ", "ПАНІКА", "ВІДНОВЛЕННЯ"]
static var PSY_NAMES = PSY_NAMES_UK   # the current language (Loc.localize_all)
const PSY_SHORT_UK := ["спок.", "напог.", "стрес", "придуш.", "ПАНІКА", "відновл."]
static var PSY_SHORT = PSY_SHORT_UK   # the current language (Loc.localize_all)
const PSY_ALERT_T := 12.0             # s after the last threat a calm man stays alert
const PSY_RECOVER_T := 25.0           # s after level >= 2 ends he is "recovering"
const PSY_STRESSED := 18.0            # stress above this = STRESSED (a strained veteran starts the mission here)
## campaign memory (Campaign soldier "strain" 0..100 carried between missions)
const MEM_WOUND := 18.0
const MEM_LONG_FIRE := 12.0           # >= MEM_LONG_FIRE_T s pinned (level >= 3) in a mission
const MEM_LONG_FIRE_T := 45.0
const MEM_COMRADE := 10.0             # per squad mate killed (max 2 counted)
const MEM_SUCCESS := -12.0            # mission won and he came through
const MEM_PANIC := 10.0               # he panicked
const MEM_CARRY := 0.6                # strain kept from the previous missions
const MEM_BASE_STRESS := 0.45         # stress never falls below strain * this
const MEM_MORALE := 0.15              # max morale -strain * this
const MEM_HARDEN := 0.03              # grit gained by coming through heavy fire unhurt (cap MEM_HARDEN_MAX)
const MEM_HARDEN_MAX := 0.15

## dynamic battlefield (Battlefield)
const CRATER_R := {"mortar": 1.6, "mine": 1.4, "he": 0.9}   # crater radius by explosion kind
const CRATER_HE_POWER := 90.0         # "he" makes a crater only from this power (73 mm, not 30 mm)
const CRATER_MAX_R := 2.4             # repeated hits widen a crater up to this
const CRATER_MAX := 90                # craters per mission (older hits still damage)
const CRATER_DEPTH := 0.3             # depth = r * this (the ground really sinks)
const CRATER_RIM := 0.08              # spoil rim height = r * this
const TREE_FELL := 1.3                # chance scale for a blast to bring a tree down
const TREE_FOLIAGE_LOSS := 0.15       # concealment lost per felled tree in its cells
const CRATER_COVER := 0.38            # cover in a crater cell (r >= 1.4 m)
const CRATER_COVER_SMALL := 0.26
const CRATER_INF_W := 1.2             # A* weight for infantry across a crater
const CRATER_VEH_W := 2.5             # A* weight for vehicles (below the impassable size)
const COVER_HP := {"sandbags": 220.0, "bale": 60.0, "dugout": 420.0, "wall": 150.0, "plank": 70.0}
const WALL_DAMAGED_H := 0.5           # share of height a damaged wall keeps
const WALL_RUBBLE_H := 0.45           # obstacle height of the rubble heap
const WALL_RUBBLE_COVER := 0.35       # cover behind the rubble
const WALL_RUBBLE_W := 1.6            # A* weight across rubble
const COVER_DMG_K := 0.5              # share of blast power that wears a piece of cover
const COVER_DAMAGED_HP := 0.6         # below this share of hp a piece is damaged
const COVER_DAMAGED := 0.6            # cover kept when damaged
const COVER_DESTROYED := 0.2          # cover kept when destroyed (rubble)
const COVER_LOST_SUPP := 14.0         # fear for the men whose cover is blown away
const BUNKER_DAMAGED_HP := 0.5
const BUNKER_DAMAGED_PROT := 0.8      # protection multiplier in a damaged bunker
const WIND_BASE := 0.25               # m/s smoke drift at weather "wind" 1.0
const SMOKE_GROW := 0.35              # radius growth over a cloud's life
const SMOKE_FADE := 0.25              # last share of the life it thins out
const SMOKE_DRONE_BLOCK := 0.85       # drone sees nothing through smoke this dense
const SMOKE_DRONE_VAGUE := 0.35       # above this only an approximate position

## campaign consequences (Campaign.consequences / prepare_mission)
const CQ_INTEL_BASE := 0.3            # intel quality with nothing learned
const CQ_INTEL_RECON := 0.45          # + share of the enemy we had seen
const CQ_INTEL_POW := 0.06            # + per prisoner (max 3)
const CQ_INTEL_FAST := 0.12           # + quick win (under half the time limit)
const CQ_INTEL_DRONE := 0.08          # - per drone lost (max 2)
const CQ_INTEL_FAILED := 0.1          # - the enemy saw us coming and moved
const CQ_ENEMY_ESCAPED := 0.6         # enemy strength + share of the enemy that got away
const CQ_ENEMY_POW := 0.04            # - per prisoner (max 4): broken morale, lost men
const CQ_ENEMY_ROUT := 0.12           # - when we took most of the garrison out
const CQ_ENEMY_FAILED := 0.2          # + reserves brought up after a failed attack
const CQ_ENEMY_SLOW := 0.08           # + a slow battle (over 80 % of the time)
const CQ_ENEMY_MIN := 0.75
const CQ_ENEMY_MAX := 1.4
const CQ_REPAIR_HP := 0.45            # a vehicle back with less hp than this misses a battle
const CQ_COH_LEADER := 0.35           # unit cohesion lost when its commander is killed / missing
const CQ_COH_VETERAN := 0.12          # per experienced / veteran soldier lost
const CQ_COH_REGEN := 0.25            # regained per battle (more after a win)
const CQ_COH_MIN := 0.4

## fight in buildings (Buildings)
const BLD_WINDOW_COVER := 0.75        # cover of a man at a window post
const BLD_INSIDE_COVER := 0.15        # ...against fire / grenades from inside the building
const BLD_EYE := 1.45                 # eye / weapon height at a window
const BLD_AIM := 1.3                  # where he is hit at a window
const BLD_ROOF_DRONE := 0.3           # drone detection under a roof
const BLD_STACK_T := 25.0             # s at most waiting for the stack at the door
const BLD_NADE_WAIT := 2.0            # s from the grenade to the entry
const BLD_CLEAR_T := 4.0              # s with no enemy inside = cleared

## vehicle armour by the side that is hit (Vehicle.take_damage)
const ARMOR_FRONT := 0.6              # damage x when hit in the front (±45°)
const ARMOR_SIDE := 1.25              # in the side
const ARMOR_REAR := 1.5               # in the rear
const ARMOR_IMMOB_SIDE := 1.6         # chance to lose a track: side / rear hits x this
const VEH_ASSAULT_SPEED := 0.6        # vehicle assault: speed x (fires on the move)
const VEH_FACE_RATE := 0.55           # rad/s hull turn when holding an aspect to the enemy
const VEH_ESCORT_SPEED := 3.2         # m/s max when infantry follows it on foot
const SUPPRESS_T := 30.0              # s of fire at a point (suppression order)

## pre-registered fire on the open approach (EnemyAI._mortar): a separate
## stock of rounds kept for the plotted field in front of the position
const MORTAR_REGISTERED_STOCK := 0    # rounds (scaled like the main stock by difficulty, campaign)
const MORTAR_REGISTERED_MIN := 2      # men caught in the open that are worth a barrage
const MORTAR_UNPLOTTED_MIN := 5       # off the plotted field: a cluster this big is needed (men; vehicles count 3)
const MORTAR_UNPLOTTED_SPREAD := 14.0 # m dispersion of unplotted fire (plotted: 5)
const CLEAR_SPACING := 3.2            # m between men in a trench-clearing column

## radio net (RadioSystem)
const RADIO_BASE := 0.6               # s: radio procedure
const RADIO_JITTER := 1.0
const RADIO_PER_100M := 0.8           # s per 100 m from the command post (max 2 x this)
const RADIO_JAM_DELAY := 4.0          # s at full jamming at the sender
const RADIO_PINNED_DELAY := 1.8       # s: a pinned squad answers later
const RADIO_NO_LEADER_DELAY := 2.5    # s: the commander is down, someone else reports
const RADIO_GARBLE_JAM := 0.55        # jamming above this loses words
const RADIO_FALSE_CHANCE := 0.03      # per squad per check: "suspicious movement" with nothing there
const RADIO_FALSE_EVERY := 45.0       # s between such checks
const RADIO_MAX_LOG := 600


static func area_aim(p: Vector3) -> Vector3:
	var top: float = W.grid.nat_at(p.x, p.z) + 0.55
	return Vector3(p.x, maxf(p.y + 1.0, top), p.z)


static func level_of(supp: float) -> int:
	var l := 0
	for t in LEVEL_AT:
		if supp >= t:
			l += 1
	return l

# ---------------------------------------------------------------- windows of an occupied building
const WIN_SEE_W := 1.2           # a known enemy can be seen from the window
const WIN_FACE_W := 1.0          # the window faces where the enemies are
const WIN_FLOOR_W := 0.05        # per floor: higher sees further
const WIN_SPACING := 3.5         # men do not crowd neighbouring windows of one floor
const WIN_SPACING_PEN := 0.6
const WIN_THREATS := 6           # this many nearest known enemies are taken into account
const WIN_REVIEW_T := 8.0        # how often the posts are reviewed while holding
const WIN_SWITCH := 0.8          # a free post must be this much better to move a man there
const WIN_SWITCH_MAX := 2        # men moved per review
const WIN_DIST_COST := 0.03      # per metre a man has to walk to a new window

# ---------------------------------------------------------------- living reactions
## The first threat after a quiet spell (shots at him, a first contact of the
## squad) is answered after a short, individual delay: men do not all react
## on the same frame. Veterans (vet_speed) and disciplined men are quicker.
const REACT_CALM_T := 8.0        # quiet for this long = the next threat is a surprise
const REACT_MIN := 0.2
const REACT_MAX := 1.2
## A comrade falls close by (the fright itself is CASUALTY_SHOCK in
## DamageSystem): stress, the cover is re-thought at once, and the spot where
## he fell is avoided a while.
const COMRADE_R := 9.0
const COMRADE_STRESS := 8.0
const DANGER_SPOT_T := 20.0

# ---------------------------------------------------------------- enemy: reinforcements
const REINF_AFTER := 360.0         # default wave: s after the fight starts
const REINF_MEN := ["leader", "rifleman", "rifleman", "mg", "at", "rifleman"]
const REINF_UNSEEN_R := 110.0      # nobody of ours this close to the entry when they come
const REINF_VEH_DELAY := 25.0      # the vehicle follows its infantry, s

# ---------------------------------------------------------------- enemy: recon drone
const RECON_DELAY := [40.0, 70.0]   # after the enemy is alerted, s
const RECON_SORTIES := 2
const RECON_TIME := 300.0           # one sortie, s
const RECON_GAP := 90.0             # between sorties, s
const RECON_ALT := 70.0             # over the ground, m
const RECON_SPEED := 9.0
const RECON_ORBIT_R := 35.0
const RECON_FOOTPRINT := 90.0       # sees our men within this (horizontal), m
const RECON_DETECT := 0.45          # detection chance per second at best
const RECON_ERROR := 4.0            # position error of a report, m
const RECON_RELAY := 20.0           # seen → known to the enemy command, s
const RECON_HEARD := 150.0          # our men notice it within this, m
const RECON_SHOOT_R := 120.0
const RECON_HIT := 0.0012           # per shooter per half-second (a small target 70 m up)
const RECON_HIT_MG := 0.003

# ---------------------------------------------------------------- enemy: organised withdrawal
## When the position collapses the enemy does not run all at once: smoke,
## one man per team (the MG first) stays and fires while the rest pull back,
## then he follows — when his time is up or he is pinned.
const WD_COVER_MIN := 20.0
const WD_COVER_MAX := 40.0

# ---------------------------------------------------------------- enemy: shifting forces
## A team that sees more of our men close by than it can hold asks for help;
## the enemy commander sends a pair from the calmest team nearby. Only what
## his teams have actually seen counts.
const SHIFT_R := 70.0            # our men within this of a team press it
const SHIFT_SEEN_T := 12.0       # seen this recently
const SHIFT_MIN_SEEN := 3        # at least this many of ours seen
const SHIFT_RATIO := 1.3         # ours seen / its active men
const SHIFT_CALM_T := 30.0       # a donor team has seen nobody close for this long
const SHIFT_DIST := 150.0        # the donor is at most this far
const SHIFT_MEN := 2             # men sent each time
const SHIFT_KEEP := 2            # the donor keeps at least this many
const SHIFT_CD := 60.0           # between two shifts
const SHIFT_MAX := 3             # shifts per battle

# ---------------------------------------------------------------- leader down
## The squad leader is down: a spell without command (orders wait, no new
## bounds), then the most experienced man takes over.
const LEADER_LOSS_MIN := 10.0
const LEADER_LOSS_MAX := 20.0

# ---------------------------------------------------------------- ammunition
const AMMO_DEFENDER_K := 1.5     # the enemy in a prepared position has more magazines (a stock there)
const AMMO_LOW_MAGS := 1         # this many spare magazines or fewer: save ammunition
const AMMO_LOW_BURST := 2        # longest burst when saving ammunition

# ---------------------------------------------------------------- field of view
## A man notices a NEW enemy best in front of him; to the side and behind less
## likely (known enemies are not forgotten when he turns).
const FOV_FRONT := 1.05          # half-angle of the front sector, rad (60°)
const FOV_SIDE := 1.92           # half-angle front + sides, rad (110°)
const FOV_SIDE_K := 0.55
const FOV_REAR_K := 0.3

# ---------------------------------------------------------------- cover choice
const COVER_CHECKS := 8          # best candidates checked against the threat for real
const COVER_BODY_H := 0.55       # height of a man lying / crouching in cover
const COVER_PEEK_H := 1.25       # eye height when he rises to shoot
const COVER_HIDDEN_W := 1.4      # bonus for a spot hidden from the threat
const COVER_VIEW_W := 0.3        # bonus for seeing the threat when rising (fighters only)
const COVER_HYSTERESIS := 0.35   # a new spot must beat the current one by this much

