Game name: Timeless
Gameplay: tactica, Isometric, 2D, roguelite
You control 3 Mercs to go in and steal artifacts in a vault / museum. You have 60s to move in and out of the area. Each turn takes 10s. think of it as a global action point reservoir. Each turn, each character has 10s and the global timer go down by 10. Lets say in cases where you have 60s, then each character effectively have 6 turns with 10s worth of actions. For missions when you have 55 seconds for example, each character has 5 turns with 10s worth of actions, then the last turn they only have 5s worth of actions
On your turn, you can perform one of these actions:
-	Move
-	Pick up
-	Takedown
-	Hack
-	Use item
-	Escape
Each playable character will have the following attributes:
-	Agility (AGI)
-	Strength (STR)
-	Intelligence (INT)
They will affect the speed in which they perform each action.
-	Move: Affected positively by AGI, negatively by weight. Weight’s effect is mitigated by Strength. Base move speed is 5m/s. Each point of AGI increases this by 10% (10m/s at 10 AGI). Changing direction also takes time with 1s for a full 360 circle. Movement needs to be calculated so that it is a smooth curve and does not have sharp bends.
-	Effective_movespeed=Base_movespeed*(1+0.1AGI)
-	Pick up: Picking up stuff will add weight, which will decrease overall speed, which can be mitigated by strength. The act of pick up itself also cost some time and this is mitigated by INT. Every kg you picked up slow your overall speed down by 1% (increase time takes to do stuff by 1%).
-	(Effective_time=time*(1+0.01*Effective_weight). Each point in STR reduce the effectiveness of the weight. Effective_weight = weight / (1+0.1STR)
-	Takedown: STR will reduce the time needed for takedown. Original takedown time is dictated by the enemy type (guard – 5s, clerk-3s). take down can only be done if the target is within 0.5m.
-	Effective_takedown_time=Takedown_time/(1+0.1STR)
-	Hack: INT will reduce the time needed for hacking (Camera = Trip_wire= 4s. Red button = 6s. Closed_window=5s. Closed_door=6s.) Effective_hacking_time=Hacking_time/(1+0.1int). Hacking is special in that the range to perform this action is 5m*(1+0.1INT).
-	Use item: INT will reduce the time needed for using item. Effective_item_using_time=base_item_using_time/(1+0.1int)
-	Escape: Instant but need to be used within 1m of an exit.
-	Picking lock (3 types): Glass lock (break it open – animation) AGI + STR, Digital lock AGI+INT, Mechanical lock: AGIx2. Each lock has 3 levels (level 1, 5s. level 2: 10s, level 3: 20s). Each point in stat will decrease the time needed to open lock. Effective_lock_open_time=Base_lock_open_time/(1+0.05*stats1 + 0.05*stat2).
Character is spawned in 1 of 4 classes. 
-	Brawler: 3 Str, 0 int, 1 agi
-	Cat burglar: 3 agi, 0 str, 1 int +1 random 
-	Hacker: 3 int, 1 str, 0 agi (+1 random Hacker quirk)
-	Apprentice: 1 str, 1 int, 1 agi + 1 unassigned point (+1 unpicked quirk)
When a character level up, they get an unassigned stat point and can pick a quirk (random 3 quirks shows up). These quirks can be rerolled once with money. For now let’s start without quirks or level up.
In the map, characters moved in a coordinate system that calculates real distance and convert it to real time cost. 
There are also guards that move at a flat 1.25m/s. These guards will wander around on a patrol route with a cone vision (long cone, a bit narrow vision (60 degree, 10m cone, semi circle at the end of the cone).
Guards only need to successfully shoot or tase you once to neutralize that character. Neutralized characters can be picked up by other characters but will put the weight of the neutralized character on the picking up character.
Test map is an isometric square with 40m edges. With 4 doors at the middle of each wall, 2 windows evenly spaced on each side of each door (8 windows in total). The windows are closed. In the middle of the room there is a locked chest (with a painting inside (10kg obj) Worth 3$). There is no level up/ quirks or item right now.
We have 3 playable characters (press tab to switch between them) top right corner there is a timer. Start at 60s and goes down by 10s each time we press commit.
There are 3 guards standing randomly at 10m distance from the locked chest.
Turn order: There are 3 phases:
-	Planning: player can move their characters around by right clicking on the ground, or right click on object and choose an option. For guards and clerk, that would be take down. For objects, it would be either unlocked and Pick up with lock (if locked – will add the weight of the lock to the object) or pick up (if not locked). For enemies, it would be take down. For camera or trip_wires or other hackable items, it would be hack. If they right click and choose an action on a target is not within 0.5m, calculate the distance and best move path then move the character that way. If an action takes longer than the amount of time the character have left, it will be performed partially using up all the time that he has in this turn and next turn, he will still be doing that with an option of continuing it (which would consume the left over time from the last turn) or stop it (which will reset the action). For example, if the character have 2.5S left and is trying to takedown a guard that need 5s to be taken down (provided they are within 0.5m of each other), then the player will still in the motion of taking the guard down using the 2.5s left. But then next turn there would be a pop up selection when we select this character saying : continue the current action? If the player says yes then consume the required amount of time. If the player says no then stop that action, reset the progress (the guard is now fully reset, would need 5s to take him down again) and the player does not spend that time. All actions taken in this phase can be undo 1 at a time by pressing Undo (`). Or undo all at the same time by pressing reset (R)
-	Once the player are satisfy with their planning, they can click Commit, would start the enemies action (using logic above, each enemy also have 10s worth of action).
-	We then go to the next turn.

Player UI: When a character is selected, there will be an avatar at the bottom of the screen with their time left (green neon, like a health bar) that goes down every time they take an action. This bar represent 10.0s and goes down according to the time the character used. Undoing actions will refund this time and refill the bar. Inside the bar there is a number in black that shows the time left this turn. If the player hover their mouse over the avatar, a small table will pop up to show all the speed affecting status. For now it is just weight: -x%. Also it will show how much money this character is carrying (the worth of all items that he is holding).
When a player right click on the ground, it would show up the box that says: move here (x.x seconds – the actual time that it takes to get there based on the distance and the movespeed). When a player right click on an target within 0.5m distance (or 5m in case of hacking) to choose an options, the box would pop up and says : (“ABCD – x.x seconds” ABCD  is the actual action (see planning note) and x.x seconds is the actual time it takes to do that action after all calculations. If a player right click on a target outside of the of the actionable range, the box would show up says Move here (x.x seconds ) and ABCD (y.y seconds).


