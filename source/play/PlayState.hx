package play;

import audio.GameSound;
import backend.Conductor;
import data.dialogue.DialogueRegistry;
import data.song.Highscore;
import data.song.SongRegistry;
import data.song.SongData.SongTimeChange;
import data.stage.StageRegistry;
import data.subtitle.SubtitleData;
import play.subtitle.SubtitleManager;
import data.subtitle.SubtitleRegistry;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.input.keyboard.FlxKey;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.util.FlxSignal;
import flixel.system.FlxAssets.FlxGraphicAsset;
import graphics.GameCamera;
import openfl.Assets;
import play.camera.CamZoomManager;
import play.camera.FollowCamera;
import play.character.Character;
import play.dialogue.Dialogue;
import play.notes.Note;
import play.notes.StrumNote;
import play.notes.Strumline;
import play.notes.SustainNote;
import play.ui.Countdown;
import play.ui.Countdown.CountdownStep;
import play.ui.IHudItem;
import play.ui.HealthIcon;
import play.ui.HudTimer;
import play.ui.HealthBar;
import play.ui.HudDisplay;
import play.save.Preferences;
import play.song.Song;
import play.song.SongModule;
import play.song.SongModuleHandler;
import play.stage.Stage;
import play.ui.RatingsGroup;
import scripting.events.ScriptEvent;
import scripting.events.ScriptEventDispatcher;
import ui.MusicBeatState;
import ui.debug.AnimationDebug;
import ui.debug.CharacterDebug;
import ui.menu.freeplay.FreeplayState;
import ui.menu.story.StoryMenuState;
import ui.secret.GitarooPause;
import ui.secret.MathGameState;
import ui.select.charSelect.CharacterSelect;
import ui.select.playerSelect.PlayerSelect;
import ui.select.playerSelect.PlayerSelect.SelectedPlayerType;
import util.FileUtil;
import util.MathUtil;
import util.TweenUtil;
import util.tools.Preloader;
import api.Discord.DiscordClient;

/**
 * The parameters used to initalize PlayState.
 */
typedef PlayStateParams = 
{
	/**
	 * The target song to play.
	 */
	var targetSong:Song;

	/**
	 * The variation to play the song in.
	 */
	var targetVariation:String;

	/**
	 * Whether the user's going to be playing as the opponent, or the player in the song.
	 */
	var ?playerType:SelectedPlayerType;
}

@:allow(play.character.Character)
@:allow(play.notes)
class PlayState extends MusicBeatState
{
	/**
	 * STATIC VARIABLES
	 */

	/**
	 * The current instance of PlayState.
	 */
	public static var instance:PlayState;

	/**
	 * The current parameters used for this PlayState.
	 */
	public static var lastParams:PlayStateParams;

	/**
	 * The current parameters used for this PlayState.
	 */
	public static var params:PlayStateParams;
	
	/**
	 * INSTANCE VARIABLES
	 */

	/**
	 * Whether the game is currently paused, or not.
	 * Stops all gameplay functionality.
	 */
	public var paused:Bool = false;

	/**
	 * The current song that's being played.
	 */
	public var currentSong:Song;

	/**
	 * The current variation of the song being played.
	 */
	public var currentVariation:String;

	/**
	 * The current chart that's being played.
	 * Contains all the deta information for the song including the metadata, and chart.
	 */
	public var currentChart(get, never):SongPlayChart;

	function get_currentChart():SongPlayChart
	{
		return currentSong.getChart(currentVariation);
	}

	public var playerType:SelectedPlayerType = PLAYER;

	/**
	 * The current speed of the song.
	 */
	public var songSpeed:Float;
	
	/**
	 * The audio track used to play the current song's vocals.
	 */
	public var vocals:GameSound;
	
	/**
	 * A fade timer used to make the vocals fade in after the player misses.
	 * Used to make sure the vocals don't stay quiet when the player misses causing issues like voicelines, opponent vocals, and etc being quiet.
	 */
	private var vocalsFadeTimer:FlxTween;

	/**
	 * Whether the song's been fully generated, and we have yet to start the song.
	 */
	private var generatedMusic:Bool = false;

	/**
	 * True if we're currently in the countdown.
	 */
	private var startingSong:Bool = false;
	
	/**
	 * Whether the game should skip the countdown, and immediately start the song.
	 */
	private var skipCountdown:Bool = false;
	
	/**
	 * Whether we're currently in some sort of cutscene.
	 * If this is the case, all input should be teased.
	 */
	public var isInCutscene:Bool;

	/**
	 * (Optional) Function called when the song's ready to be started.
	 * Useful for if the song has an opening cutscene, and the countdown should be called later.
	 * The countdown will have to be manually called if this is used.
	 */
	var startCallback:Void->Void;

	/**
	 * (Optional) Function called when the song's complete.
	 * Useful for if the song has dialogue, or an ending cutscene, and it shouldn't end immediately.
	 * State switching is to be done manually if this is used.
	 */
	var endCallback:Void->Void;

	/**
	 * Whether the player's able to pause while playing.
	 */
	var canPause:Bool = true;

	/**
	 * Whether the player has no health and is going to transition to the game over.
	 */
	var isPlayerDying:Bool = false;

	/**
	 * The amount of time that's gone by since the player has entered this state.
	 */
	private var elapsedTime:Float = 0;

	/**
	 * The current scrollType being used right now.
	 * Changes the y position of all of the HUD elements based on this type.
	 */
	public var scrollType(default, set):String;
	
	function set_scrollType(value:String):String
	{
		if (dadStrums != null)
			dadStrums.scrollType = value;

		if (playerStrums != null)
			playerStrums.scrollType = value;

		for (i in [missesDisplay, scoreDisplay, accuracyDisplay, timer, healthBar, ratings])
		{
			if (i == null)
				continue;

			var item = cast(i, IHudItem);
			item.scrollType = value;
		}
		if (iconP1 != null)
			iconP1.y = healthBar.y - (iconP1.height / 2);
			
		if (iconP2 != null)
			iconP2.y = healthBar.y - (iconP2.height / 2);

		return scrollType = value;
	}

	/**
	 * A signal that's called AFTER the main preference change callback is called.
	 */
	public var onPreferenceChangedPost(default, null):FlxTypedSignal<(preference:String, value:Any) -> Void> = new FlxTypedSignal<(preference:String, value:Any) -> Void>();

	/**
	 * The player's current health.
	 * Once this value reaches zero, the user is at a GameOver and all gameplay logic should stop.
	 */
	public var health:Float = 1;
	
	/**
	 * The amount of health the player gains when hitting a note.
	 * Separate variable to allow for scripts to control it.
	 */
	private var healthDrainer:Float = 0.04;

	/**
	 * The amount of health the player losses when missing a note.
	 * Separate variable to allow for scripts to control it.
	 */
	private var healthGainer:Float = 0.023;

	/**
	 * The player's current health displayed from the HUD.
	 * This interpolates to the player's current health to help with give nice smoothing effects. 
	 */
	public var healthLerp:Float = 1;
	
	/**
	 * Whether the player's able to miss any note without penalizing them.
	 */
	public var noMiss:Bool;
	
	/**
	 * Whether the user's able to press a note key, and have it not penalize them.
	 */
	public var ghostTapping:Bool = true;


	// DISPLAYS //

	/**
	 * The current score the user has on the song.
	 */
	private var songScore:Int = 0;

	/**
	 * The player's current combo.
	 * Gets reset to 0 whenever the player misses.
	 */
	private var combo:Int = 0;

	/**
	 * The amount of misses the user has on the song.
	 */
	public var misses:Int = 0;

	/**
	 * The player's current accuracy on the song.
	 */
	private var accuracy:Float = 0;

	/**
	 * The total amount of notes the user has hit.
	 * This is increased based a rating the player gets.
	 */
	private var totalNotesHit:Float = 0;

	/**
	 * The ACTUAL total of amount of notes the player has hit.
	 * Gets updated everytime the accuracy gets updated. 
	 */
	private var totalPlayed:Int = 0;


	// CAMERA //

	/**
	 * The current zoom the game camera is on.
	 * Interpolates between this, and the current camera zoom value for a smooth lerp effect.
	 */
	private var defaultCamZoom:Float = 1.05;

	/**
	 * The current zoom the HUD camera is on.
	 * Interpolates between this, and the current camera zoom value for a smooth lerp effect.
	 */
	private var defaultHUDZoom:Float = 1.0;
	
	/**
	 * The zoom manager used for the game camera.
	 */
	private var camGameZoom:CamZoomManager;

	/**
	 * The zoom manager used for the HUD camera.
	 */
	private var camHUDZoom:CamZoomManager;

	/**
	 * Whether the game is allowed to do any camera zooming.
	 * Disables the camera zooming for all cameras including the game, and hud camera.
	 */
	public var camZooming(default, set):Bool = true;
	
	public function set_camZooming(value:Bool)
	{
		camGameZoom.canZoom = value;
		camHUDZoom.canZoom = value;
		camZooming = value;
		return value;
	}
	
	/**
	 * Whether the game should zoom the cameras fast.
	 */
	public var crazyZooming(default, set):Bool;
	
	public function set_crazyZooming(value:Bool)
	{
		value ? {
			camGameZoom.timeSnap = 1;
			camHUDZoom.timeSnap = 1;
		} : {
			camGameZoom.timeSnap = 4;
			camHUDZoom.timeSnap = 4;
		}
		crazyZooming = value;
		return value;
	}
	
	/**
	 * Whether the game camera's currently focused on the opponent.
	 */
	private var focusOnDadGlobal:Bool = true;

	/**
	 * Whether the game stop all camera movement, and strictly focus on the character it's supposed to.
	 */
	private var forceFocusOnChar:Bool = false;

	/**
	 * Whether the game camera is allowed to move whenever any of the characters hit a note. 
	 */
	private var camMoveOnNoteAllowed:Bool = true;

	/**
	 * The amount of time it takes for the health icons to bop, in milliseconds.
	 */
	private final iconBopTime:Float = 0.1;
	
	/**
	 * The current time of the icon bop.
	 * Used to help make sure the icon bops are framerate independent.
	 */
	private var iconSizeResetTime:Float = 0;

	/**
	 * The current size of the opponent's icon while bopping.
	 */
	private var iconP1BopSize:FlxPoint = FlxPoint.get(150, 150);

	/**
	 * The current size of the player's icon while bopping.
	 */
	private var iconP2BopSize:FlxPoint = FlxPoint.get(150, 150);

	/**
	 * A list of songs that contain shape notes.
	 * TODO: Remove this?
	 */
	private var shapeNoteSongs:Array<String> = [];

	var pressingKey5Global:Bool;

	/**
	 * Optional variable to allow for scripts to customize the opponent character used,.
	 */
	var dadOverride:Null<String> = null;
	
	/**
	 * Optional variable to allow for scripts to customize the girlfriend character used.
	 */
	var gfOverride:Null<String> = null;
	
	/**
	 * Optional variable to allow for scripts to customize the player character used.
	 */
	var bfOverride:Null<String> = null;
	
	/**
	 * Optional variable to allow for scripts to customize the health bar.
	 */
	var healthBarOverride:Null<FlxGraphicAsset> = null;
	

	/**
	 * RENDER OBJECTS
	 */

	/**
	 * The camera used to render the game, and world view.
	 */
	private var camGame:FollowCamera;

	/**
	 * The camera used to render any HUD elements.
	 */
	private var camHUD:GameCamera;

	/**
	 * The camera used to render anything in-between the game, and HUD camera.
	 */
	private var camOther:GameCamera;

	/**
	 * The camera used to render any dialogue.
	 */
	private var camDialogue:GameCamera;

	/**
	 * The previous camera follow before the state left.
	 */
	private static var prevCamFollow:FlxObject;

	/**
	 * The current stage that's rendered on the game render, and (usually) under the characters.
	 */
	private var currentStage:Stage = null;

	/**
	 * The current opponent that's being run on this state.
	 */
	private var dad:Character;

	/**
	 * The current girlfriend character being run on this state.
	 */
	private var gf:Character;

	/**
	 * The current player character being run on this state.
	 */
	private var boyfriend:Character;

	/**
	 * The current character that the user plays as.
	 * Dependent on whether the user's playing as the opponent, or the player for the song.
	 */
	private var playingChar(get, never):Character;

	function get_playingChar():Character
	{
		return playerType == OPPONENT ? dad : boyfriend;
	}
	
	/**
	 * The current current that's against the player.
	 * Dependent on whether the user's playing as the opponent, or the player for the song.
	 */
	private var opposingChar(get, never):Character;

	function get_opposingChar():Character
	{
		return playerType == OPPONENT ? boyfriend : dad;
	}

	/**
	 * The group used to display the ratings for whenever a player hits a note.
	 */
	public var ratings:RatingsGroup;
	
	/**
	 * The object containing the current rendering.
	 */
	public var currentDialogue:Dialogue;


	// UI //

	/**
	 * The group, and manager that holds all of the subtitles for this song.
	 */
	public var subtitleManager:SubtitleManager = null;

	/**
	 * The strumline used for the opponent.
	 */
	public var dadStrums:Strumline;

	/**
	 * The strumline used for the player.
	 */
	public var playerStrums:Strumline;

	/**
	 * The strumline that's being used by the opponent.
	 * If the current opponent is the `Opponent` this'll be `dadStrums`
	 * Else, it'll be `playerStrums`
	 */
	public var opposingStrumline(get, never):Strumline;

	function get_opposingStrumline():Strumline
	{
		return playerType == OPPONENT ? playerStrums : dadStrums;
	}

	/**
	 * The strumline that's being used by the current player.
	 * If the current player is the `Opponent` this'll be `dadStrums`
	 * Else, it'll be `playerStrums`
	 */
	public var playingStrumline(get, never):Strumline;

	function get_playingStrumline():Strumline
	{
		return playerType == OPPONENT ? dadStrums : playerStrums;
	}

	/**
	 * A HUD element used to display the time bar.
	 */
	var timer:HudTimer;
	
	/**
	 * A HUD element used to display the health bar.
	 */
	var healthBar:HealthBar;


	/**
	 * The health icon on the health bar used for the player.
	 */
	var iconP1:HealthIcon;
	
	/**
	 * The health icon on the health bar used for the opponent.
	 */
	var iconP2:HealthIcon;


	/**
	 * The HUD display object used to display the player's current score.
	 */
	var scoreDisplay:HudDisplay;
	
	/**
	 * The HUD display object used to display the player's current misses.
	 */
	var missesDisplay:HudDisplay;
	
	/**
	 * The HUD display object used to display the player's current accuracy.
	 */
	var accuracyDisplay:HudDisplay;
	
	
	// interdimensional
	var noteLimbo:Note;
	var noteLimboFrames:Int;

	/**
	 * Initalizes a new PlayState instance.
	 * @param params The parameters to initalize PlayState with.
	 */
	public function new(?params:PlayStateParams)
	{
		super();

		if (params == null)
		{
			if (lastParams == null)
				throw 'Tried to initalize PlayState with 0 parameters.';
			else
				params = lastParams;
		}

		this.playerType = params?.playerType ?? PLAYER;
		this.currentSong = params?.targetSong ?? null;

		if (currentSong != null && currentSong.hasChart(params?.targetVariation ?? null))
		{
			this.currentVariation = Song.validateVariation(params.targetVariation);
		}
		else
		{
			this.currentVariation = Song.DEFAULT_VARIATION;
		}

		PlayState.params = params;
		PlayState.lastParams = params;
		
		instance = this;
	}

	override public function create():Void
	{
		SoundController?.music?.stop();
		Cursor.visible = false;

		persistentUpdate = true;
		persistentDraw = true;

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		FlxG.fixedTimestep = false;

		createCameras();
		initPreferences();
		initalizeSongData();

		initStage();
		initCharacters();

		initalizeCamera();
		initalizeUI();
		generateSong();
		prepareSong();

		super.create();
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		elapsedTime += elapsed;

		if ((isInCutscene && FlxG.keys.justPressed.ESCAPE) || (!isInCutscene && FlxG.keys.justPressed.ENTER && Countdown.countdownStarted && canPause))
			runPause();

		if (FlxG.keys.justPressed.SEVEN)
		{
			// Pressing seven will enable custom callback functionaility. 
			// Cancelling it will allow custom behavior that isn't going to the chart editor.
			// Not sure if this is necessary to warrant it's own script event.

			var event = new ScriptEvent(PRESS_SEVEN, true);
			dispatchEvent(event);
			
			if (event.eventCanceled)
			{
				return;
			}
		}
		
		health = Math.min(health, 2);
		healthLerp = FlxMath.lerp(healthLerp, health, 0.3);

		iconSizeResetTime = Math.max(0, iconSizeResetTime - elapsed);

		var iconLerp = FlxEase.quartIn(iconSizeResetTime / iconBopTime);

		iconP1.setGraphicSize(Std.int(FlxMath.lerp(150, iconP1BopSize.x, iconLerp)), Std.int(FlxMath.lerp(150, iconP1BopSize.y, iconLerp)));
		iconP1.updateHitbox();

		iconP2.setGraphicSize(Std.int(FlxMath.lerp(150, iconP2BopSize.x, iconLerp)), Std.int(FlxMath.lerp(150, iconP2BopSize.y, iconLerp)));
		iconP2.updateHitbox();

		var iconOffset:Int = 26;
		switch (healthBar?.bar?.fillDirection)
		{
			case LEFT_TO_RIGHT:
				iconP1.x = (healthBar.x + healthBar.width) - (healthBar.width * (FlxMath.remapToRange(healthBar.percent, 0, 100, 100, 0) * 0.01) + iconOffset);
				iconP2.x = (healthBar.x
					+ healthBar.width)
					- (healthBar.width * (FlxMath.remapToRange(healthBar.percent, 0, 100, 100, 0) * 0.01))
					- (iconP2.width - iconOffset);
			default:
				iconP1.x = healthBar.x + (healthBar.width * (FlxMath.remapToRange(healthBar.percent, 0, 100, 100, 0) * 0.01) - iconOffset);
				iconP2.x = healthBar.x + (healthBar.width * (FlxMath.remapToRange(healthBar.percent, 0, 100, 100, 0) * 0.01)) - (iconP2.width - iconOffset);
		}
		
		switch (healthBar?.bar?.fillDirection)
		{
			case LEFT_TO_RIGHT:
				iconP1.changeState(healthBar.percent > 80 ? 'losing' : 'normal');
				iconP2.changeState(healthBar.percent < 20 ? 'losing' : 'normal');
			default:
				iconP1.changeState(healthBar.percent < 20 ? 'losing' : 'normal');
				iconP2.changeState(healthBar.percent > 80 ? 'losing' : 'normal');
		}

		if (FlxG.keys.pressed.CONTROL || FlxG.keys.pressed.SHIFT)
		{
			var controls:Array<Dynamic> = [[FlxKey.ONE, dad], [FlxKey.TWO, boyfriend], [FlxKey.THREE, gf]];
			for (i in controls)
			{
				if (FlxG.keys.firstJustPressed() == i[0])
				{
					if (FlxG.keys.pressed.CONTROL)
						FlxG.switchState(() -> new AnimationDebug(i[1]));
					if (FlxG.keys.pressed.SHIFT)
						FlxG.switchState(() -> new CharacterDebug(cast(i[1], Character).id));
				}
			}
		}

		#if debug
		Conductor.instance.quickWatch();
		if (FlxG.keys.justPressed.ONE)
			endSong();

		if (FlxG.keys.justPressed.TWO) // Go 10 seconds into the future :O
		{
			SoundController.music.pause();
			vocals.pause();
			Conductor.instance.songPosition += 10000;

			for (strumLine in [playerStrums, dadStrums])
			{
				strumLine.clean();
			}
			SoundController.music.time = Conductor.instance.songPosition - Conductor.instance.offsets;
			SoundController.music.play();

			vocals.time = SoundController.music.time;
			vocals.play();
			Conductor.instance.update(Conductor.instance.songPosition);
		}
		#end

		if (!paused && !isInCutscene)
		{
			if (startingSong)
			{
				if (Countdown.countdownStarted)
				{
					// This enables Conductor script events. 
					// Don't apply offsets as they were already applied on the start of the Countdown.
					Conductor.instance.update(Conductor.instance.songPosition + FlxG.elapsed * 1000, true, false);
					if (Conductor.instance.songPosition >= 0.0 + Conductor.instance.offsets)
					{
						startSong();
					}
				}
			}
			else
			{
				Conductor.instance.update(Conductor.instance.songPosition + FlxG.elapsed * 1000, true, false);
			}
		}

		if (camGameZoom.canWorldZoom)
			FlxG.camera.zoom = MathUtil.smoothLerp(FlxG.camera.zoom, defaultCamZoom, elapsed, 0.75, 1 / 1000);
		
		if (camHUDZoom.canWorldZoom)
			camHUD.zoom = MathUtil.smoothLerp(camHUD.zoom, defaultHUDZoom, elapsed, 0.75, 1 / 1000);

		if (health <= 0 && !isPlayerDying)
		{
			gameOver();
		}

		playingStrumline.forEachNote(function(note:Note)
		{
			if (Conductor.instance.songPosition >= note.strumTime && !note.phoneHit && note.noteStyle == 'phone')
			{
				note.phoneHit = true;
				opposingChar.playAnim(opposingChar.animation.exists('throw') ? 'throw' : 'smash', true);
			}
		});
		
		handleInputs();
		processNotes(elapsed);
	}

	override function destroy():Void
	{
		performCleanup();
		
		super.destroy();
	}
	
	/**
	 * Called whenever the Conductor instance reaches a step.
	 * @param step The step reached.
	 */
	override function stepHit(step:Int):Bool
	{
		if (!super.stepHit(step))
			return false;
		
		for (i in [camGameZoom, camHUDZoom])
		{
			if (i.canZoom && (curStep - Conductor.instance.currentTimeChange.stepTime) % i.timeSnap == 0 && i.useSteps && camZooming)
			{
				i.camera.zoom += i.zoomValue;
			}
		}

		var needsResync:Bool = (Math.abs(vocals.time - SoundController.music.time) >= 20) 
		|| (Math.abs(SoundController.music.time - (Conductor.instance.songPosition - Conductor.instance.offsets)) >= 20);

		if (!startingSong && needsResync && !paused)
			resyncVocals();

		return true;
	}

	/**
	 * Called whenever the Conductor instance reaches a beat.
	 * @param beat The beat that was reached.
	 */
	override function beatHit(beat:Int):Bool
	{
		if (!super.beatHit(beat))
			return false;

		moveCameraSection();

		for (i in [camGameZoom, camHUDZoom])
		{
			if (i.canZoom && Std.int(curBeat - Std.int(Math.round(Conductor.instance.currentTimeChange.beatTime))) % i.timeSnap == 0 && !i.useSteps && camZooming)
			{
				i.camera.zoom += i.zoomValue;
			}
		}

		var funny:Float = Math.max(Math.min(healthBar.value, 1.9), 0.1);

		switch (healthBar.bar.fillDirection)
		{
			case LEFT_TO_RIGHT:
				iconP1BopSize = FlxPoint.get(Std.int(iconP2.width + (50 * ((2 - funny) + 0.1))), Std.int(iconP2.height - (25 * ((2 - funny) + 0.1))));
				iconP2BopSize = FlxPoint.get(Std.int(iconP1.width + (50 * (funny + 0.1))), Std.int(iconP1.height - (25 * funny)));
			default:
				iconP1BopSize = FlxPoint.get(Std.int(iconP1.width + (50 * (funny + 0.1))), Std.int(iconP1.height - (25 * funny)));
				iconP2BopSize = FlxPoint.get(Std.int(iconP2.width + (50 * ((2 - funny) + 0.1))), Std.int(iconP2.height - (25 * ((2 - funny) + 0.1))));
		}
		iconSizeResetTime = iconBopTime;

		return true;
	}

	/**
	 * Called whenever the Conductor instance reaches a measure.
	 * @param measure The measure that was reached.
	 */
	override function measureHit(measure:Int):Bool
	{
		if (!super.measureHit(measure))
			return false;

		return true;
	}

	/**
	 * Called whenever the Conductor instance reaches a new time change.
	 * @param event The time change event that was reached.
	 */
	override function timeChange(event:SongTimeChange)
	{
		if (!super.timeChange(event))
			return false;

		for (i in [camGameZoom, camHUDZoom])
		{
			if (i.timeSignatureAdjust)
			{
				i.timeSnap = event.numerator;
			}
		}
		return true;
	}

	/**
	 * Opens a given substate. Overriden to take into account if the player pauses.
	 * @param SubState The substate to open.
	 */
	override function openSubState(SubState:FlxSubState):Void
	{
		if (paused)
		{
			var event = new ScriptEvent(PAUSE, true);
			dispatchEvent(event);

			if (event.eventCanceled)
				return;

			SoundController?.music?.pause();
			vocals.pause();
			if (currentDialogue != null)
			{
				currentDialogue.pauseMusic();
			}

			changePresence(PAUSED);

			if (Countdown.countdownStarted && !Countdown.finished)
				Countdown.paused = true;
		}

		super.openSubState(SubState);
	}

	/**
	 * Closes the currently active substate. Overriden to take into account if the player pauses.
	 * @param SubState The substate to open.
	 */
	override function closeSubState():Void
	{
		if (paused)
		{
			var event = new ScriptEvent(RESUME, true);
			dispatchEvent(event);
			
			if (event.eventCanceled) return;

			if (SoundController.music != null && !startingSong)
			{
				resyncVocals();
			}

			if (currentDialogue != null)
			{
				currentDialogue.resumeMusic();
			}

			if (Countdown.countdownStarted && !Countdown.finished)
				Countdown.paused = false;

			TweenUtil.resumeTweens();
			FlxTimer.globalManager.forEach(function(t:FlxTimer)
			{
				t.active = true;
			});
			paused = false;

			changePresence(NORMAL(true, false));
		}

		super.closeSubState();
	}

	override function startOutro(onComplete:() -> Void):Void
	{
		canPause = false;
		isInCutscene = true;
		
		super.startOutro(onComplete);
	}

	override function onFocusLost():Void
	{
		if (canPause)
			runPause();
	}

	override function dispatchEvent(event:ScriptEvent):Void
	{
		// Dispatch modules first.
		super.dispatchEvent(event);

		// Dispatch to the song.
		ScriptEventDispatcher.callEvent(this.currentSong, event);

		// Dispatch to any song modules.
		SongModuleHandler.callOnModules(event);

		// Dispatch events to the stage to the stage.
		ScriptEventDispatcher.callEvent(this.currentStage, event);
		
		// Dispatch to all characters.
		this.currentStage.dispatchToCharacters(event);

		// Dispatch to the subtitle manager, in the case of any subtitles.
		if (subtitleManager != null)
		{
			ScriptEventDispatcher.callEvent(this.subtitleManager, event);
		}
		
		// Dispatch script events to the current dialogue.
		if (currentDialogue != null)
		{
			ScriptEventDispatcher.callEvent(this.currentDialogue, event);
		}
	}

	override function reloadAssets():Void
	{
		performCleanup();

		instance = this;

		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		
		if (subState != null)
		{
			subState.close();
		}
		modding.PolymodManager.reloadAssets();
		lastParams.targetSong = SongRegistry.instance.fetchEntry(currentSong.id);
		LoadingState.loadPlayState(lastParams, true);
	}

	/**
	 * Called whenever the user changes a preferences.
	 * @param preference The id of the preference that was changed.
	 * @param value The new value of the preference.
	 */
	function onPreferenceChange(preference:String, value:Any):Void
	{
		switch (preference)
		{
			case 'downscroll':
				this.scrollType = value ? 'downscroll' : 'upscroll';
			case 'ghostTapping':
				this.ghostTapping = value;
			case 'hitsounds':
				if (value)
				{
					SoundController.cache(Paths.soundPath('note_click'));
				}
			case 'minimalUI':
				Main.fps.visible = value ? false : Preferences.debugUI;
		}
		onPreferenceChangedPost.dispatch(preference, value);
	}

	function performCleanup():Void
	{
		SongModuleHandler.clearModules();

		dispatchEvent(new ScriptEvent(DESTROY, false));

		if (currentDialogue != null)
		{
			currentDialogue.kill();
			remove(currentDialogue);
			currentDialogue = null;
		}

		if (subtitleManager != null)
		{
			this.subtitleManager.kill();
			remove(subtitleManager);
			subtitleManager = null;
		}
		Preferences.onPreferenceChanged.remove(onPreferenceChange);
	}

	/**
	 * Sets up the cameras to use for the PlayState.
	 */
	function createCameras():Void
	{
		camGame = new FollowCamera();

		camOther = new GameCamera();
		camOther.bgColor.alpha = 0;

		camHUD = new GameCamera();
		camHUD.bgColor.alpha = 0;

		camDialogue = new GameCamera();
		camDialogue.bgColor.alpha = 0;

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		FlxG.cameras.add(camDialogue, false);

		FlxG.cameras.setDefaultDrawTarget(camGame, true);
	}

	/**
	 * Initalizes any data from the current song to play, and clears any data from a previous session. 
	 */
	function initalizeSongData():Void
	{
		if (currentChart != null)
		{
			currentChart.cacheInstrumental();
			currentChart.cacheVocals();
		}
		songSpeed = currentChart.speed;

		Conductor.instance.mapTimeChanges(currentChart.timeChanges);
		Conductor.instance.reset();

		Countdown.reset();
		Countdown.paused = false;

		paused = false;

		SongModuleHandler.loadVariationModules(this.currentSong.id, currentVariation);
        SongModuleHandler.forEachModule((module:SongModule) ->
        {
            module.initalize();
        });
		
		// Dispatch create function to song to further initalize it before gameplay starts.
		var event = new ScriptEvent(CREATE, false);

		ScriptEventDispatcher.callEvent(this.currentSong, event);
		SongModuleHandler.callOnModules(event);
	}

	/**
	 * Initalizes any data coming from the user's preferences.
	 */
	function initPreferences():Void
	{
		if (Preferences.hitsounds)
		{
			SoundController.cache(Paths.soundPath('note_click'));
		}
		ghostTapping = Preferences.ghostTapping;
		this.scrollType = Preferences.downscroll ? 'downscroll' : 'upscroll';

		// Sets the offsets of the Conductor.
		Conductor.instance.offsets = Preferences.latencyOffsets;

		Preferences.onPreferenceChanged.add(onPreferenceChange);
	}

	function initStage():Void
	{
		var stageId:String = currentChart?.stage ?? 'stage';

		currentStage = loadStage(stageId);
		if (currentStage != null)
		{
			// Set the camera zoom based off the stage's zoom.
			defaultCamZoom = currentStage.stageZoom;
			
			// Add the stage into the scene.
			this.add(currentStage);
		}
	}

	function loadStage(id:String):Stage
	{
		var stage = StageRegistry.instance.fetchEntry(id);
		
		if (stage != null)
		{			
			// Revive the stage if it was killed.
			if (!stage.alive)
			{
				stage.revive();
			}

			// Load the stage.
			stage.load();
		}
		return stage;
	}

	function removeStage(stage:Stage):Void
	{
		if (stage != null)
		{
			this.remove(stage);
			stage.destroy();
			stage = null;
		}
	}

	/**
	 * Initalizes, and prepares all the characters to be rendered, and ready to use.
	 */
	function initCharacters():Void
	{
		// If this is true it means that the current variation we're on is a custom one.
		var customVariation:Bool = (this.currentVariation == Song.validateVariation(params.targetVariation) && this.currentVariation != Song.DEFAULT_VARIATION);
		
		var customChar:Null<String> = (PlayStatePlaylist.isStoryMode || FreeplayState.skipSelect.contains(currentSong.id.toLowerCase()) || customVariation) ? null : CharacterSelect.selectedCharacter;

		var dadChar = dadOverride != null ? dadOverride : currentChart.opponent;
		dad = Character.create(100, 450, dadChar, OPPONENT);

		var bfChar:String = bfOverride != null ? bfOverride : customChar != null ? customChar : currentChart.player;
		boyfriend = Character.create(770, 450, bfChar, PLAYER);

		var gfVersion:String = (gfOverride != null) ? gfOverride : (boyfriend.skins.exists('gfSkin')) ? boyfriend.skins.get('gfSkin') : currentChart.girlfriend;
		gf = Character.create(400, 130, gfVersion, GF);

		// Add the characters into the stage.
		// This is where they'll be re-positioned, and properly initalized.
		this.currentStage.addCharacter(gf, GF);
		this.currentStage.addCharacter(dad, OPPONENT);
		this.currentStage.addCharacter(boyfriend, PLAYER);

		dispatchEvent(new ScriptEvent(CREATE_POST, false));

		// Cache the opponent and player note skins so they don't cause stutters.
		Preloader.cacheNoteStyle(dad.skins.get('noteSkin'));
		Preloader.cacheNoteStyle(boyfriend.skins.get('noteSkin'));
	}

	/**
	 * Initalizes any game camera data, and  
	 */
	function initalizeCamera():Void
	{
		var camPos:FlxPoint = dad.cameraFocusPoint;
		switch (currentChart.opponent)
		{
			case 'gf':
				dad.setPosition(gf.x, gf.y);
				gf.visible = false;
		}
		camGame.snapToPosition(camPos.x, camPos.y);
		if (prevCamFollow != null)
		{
			camGame.snapToPosition(prevCamFollow.x, prevCamFollow.y);
			prevCamFollow = null;
		}
		camGame.zoom = defaultCamZoom;

		camGameZoom = new CamZoomManager(camGame, 0.015);
		camHUDZoom = new CamZoomManager(camHUD, 0.03);
	}

	/**
	 * Initalizes the HUD, and any necessary user interface.
	 */
	function initalizeUI():Void
	{
		createStrums();
		createHudDisplays();

		healthBar = new HealthBar(0, {
			graphic: healthBarOverride ?? Paths.image('ui/bars/healthBar'),
			opponent: dad,
			player: boyfriend,
			parent: this,
			variable: 'healthLerp',
			min: 0,
			max: 2,
			playerType: this.playerType,
			scrollType: this.scrollType
		});
		healthBar.screenCenter(X);
		healthBar.cameras = [camHUD];
		add(healthBar);

		ratings = new RatingsGroup(boyfriend.skins.get('noteSkin'));
		ratings.x = FlxG.width / 2;
		ratings.cameras = [camHUD];
		add(ratings);
		ratings.scrollType = scrollType;

		iconP1 = new HealthIcon(boyfriend.characterIcon, true);
		iconP1.y = healthBar.y - (iconP1.height / 2);
		iconP1.cameras = [camHUD];
		add(iconP1);

		iconP2 = new HealthIcon(dad.characterIcon, false);
		iconP2.y = healthBar.y - (iconP2.height / 2);
		iconP2.cameras = [camHUD];
		add(iconP2);

		var targetSubtitleId:String = this.currentSong.id + Song.validateVariationPath(this.currentVariation);
		if (SubtitleRegistry.instance.hasEntry(targetSubtitleId))
		{
			subtitleManager = SubtitleRegistry.instance.fetchEntry(targetSubtitleId);
			subtitleManager.cameras = [camOther];
			add(subtitleManager);

			// Initalize the subtitle manager.
			ScriptEventDispatcher.callEvent(subtitleManager, new ScriptEvent(CREATE, false));
		}

		dispatchEvent(new ScriptEvent(CREATE_UI, false));
	}

	/**
	 * Initalizes the strumline receptors to be used by the player.
	 */
	function createStrums():Void
	{
		dadStrums = new Strumline({isPlayer: false, noteStyle: dad.skins.get('noteSkin'), scrollType: scrollType, showStrums: false});
		dadStrums.x = 100;
		dadStrums.cameras = [camHUD];
		dadStrums.generateNotes(currentChart.notes);
		add(dadStrums);
		dadStrums.onNoteSpawn.add(onStrumlineNoteSpawn);

		playerStrums = new Strumline({isPlayer: true, noteStyle: boyfriend.skins.get('noteSkin'), scrollType: scrollType, showStrums: false});
		playerStrums.x = FlxG.width - playerStrums.width - 100;
		playerStrums.cameras = [camHUD];
		playerStrums.generateNotes(currentChart.notes);
		add(playerStrums);
		playerStrums.onNoteSpawn.add(onStrumlineNoteSpawn);
		
		opposingStrumline.onNoteHit.add(function(note:Note)
		{
			opponentSing(opposingChar, note);
		});

		playingStrumline.onNoteHit.add(function(note:Note)
		{
			playerSing(this.playingChar, note);
		});
		playingStrumline.onNoteMiss.add(function(note:Note)
		{
			if (!noMiss)
				noteMiss(note.direction, note, this.playingChar);

			muteVocals();
		});

		// Flip the instances of the strumlines so they work properly.
		if (playerType == OPPONENT)
		{
			// Change whether you have to play the opponent or players side based on the user's selected type.
			playingStrumline.isPlayer = true;
			opposingStrumline.isPlayer = false;
			
			this.dad.nativelyPlayable = !dad.nativelyPlayable;
			this.boyfriend.nativelyPlayable = !boyfriend.nativelyPlayable;

			boyfriend.characterType = OPPONENT;
			dad.characterType = PLAYER;
		}
	}

	/**
	 * Creates the HUD display objects that show the player's current scoring.
	 */
	function createHudDisplays():Void
	{
		var char:Character = this.playerType == PLAYER ? dad : boyfriend;

		timer = new HudTimer(0, char, this.scrollType, char.skins.get('noteSkin'));
		timer.screenCenter(X);
		timer.alpha = 0.001;
		timer.cameras = [camHUD];
		add(timer);

		missesDisplay = new HudDisplay(0, {
			name: 'misses',
			parent: this,
			trackerVariable: 'misses',
			startString: '0',
			scrollType: this.scrollType
		});
		missesDisplay.screenCenter(X);

		accuracyDisplay = new HudDisplay(missesDisplay.x - 150, {
			name: 'accuracy',
			parent: this,
			trackerVariable: 'accuracy',
			startString: '100%',
			scrollType: scrollType
		});
		accuracyDisplay.textUpdateFunc = function(value:Float)
		{
			accuracyDisplay.text.text = '${FlxMath.roundDecimal(value, 2)}%';
		}

		scoreDisplay = new HudDisplay(missesDisplay.x + 150, {
			name: 'score',
			parent: this,
			trackerVariable: 'songScore',
			startString: '0',
			scrollType: this.scrollType
		});

		for (i in [scoreDisplay, missesDisplay, accuracyDisplay])
		{
			i.cameras = [camHUD];
			add(i);
		}
	}

	/**
	 * Starts a new dialogue conversation given an id.
	 * @param id The id of the dialogue to open.
	 * @param onComplete Called when the dialogue has been completed.
	 * @param autoBegin Whether to immediately begin the dialogue. If false, `this.currentDialogue.start()` must be called in order for it to start.
	 */
	function startDialogue(id:String, onComplete:Void->Void, autoBegin:Bool = true):Void
	{
		if (!Preferences.cutscenes)
		{
			if (onComplete != null)
				onComplete();

			return;
		}
		
		isInCutscene = true;

		currentDialogue = DialogueRegistry.instance.fetchEntry(id);
		if (currentDialogue != null)
		{
			if (!currentDialogue.alive)
			{
				currentDialogue.revive();
			}
			currentDialogue.camera = camDialogue;
			currentDialogue.scrollFactor.set();
			currentDialogue.alpha = 1.0;
			currentDialogue.onFinish = () -> {
				onDialogueComplete();

				if (onComplete != null)
					onComplete();
			}
			add(currentDialogue);

			ScriptEventDispatcher.callEvent(currentDialogue, new ScriptEvent(CREATE, false));

			// Begin the dialogue, if false a script will have to call it themselves.
			if (autoBegin)
			{
				currentDialogue.start();
			}
		}
	}

	/**
	 * Helper function for opening dialogue at the start of a song.
	 * @param id The id of the dialogue box to open.
	 */
	function beginStartDialogue(id:String, ?onComplete:Void->Void)
	{
		// Start the countdown if no other callback was provided.
		onComplete ??= startCountdown;

		if (!Preferences.cutscenes)
		{
			if (onComplete != null)
				onComplete();

			return;
		}

		camGame.setFollow(gf.cameraFocusPoint.x, gf.cameraFocusPoint.y);

		var black = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		black.scale.set(FlxG.width * 2, FlxG.height * 2);
		black.updateHitbox();
		black.scrollFactor.set();
		black.camera = camHUD;
		add(black);

		FlxTween.tween(black, {alpha: 0}, 1.0, {
			onComplete: (t:FlxTween) ->
			{
				remove(black);
				currentDialogue.start();
			}
		});
		
		startDialogue(id, onComplete, false);
	}

	/**
	 * Handles whenever there's a song with dialogue at the end.
	 * @param id The id of the dialogue to open.
	 * @param finishCallback Called when the dialogue is finished. 
	 */
	function endSongDialogue(id:String, finishCallback:Void->Void):Void
	{
		if (!Preferences.cutscenes)
		{
			if (finishCallback != null)
				finishCallback();

			return;
		}
		
		canPause = true;
		SoundController.music.volume = 0;
		vocals.volume = 0;
		generatedMusic = false;

		for (strumLine in [playerStrums, dadStrums])
		{
			strumLine.canUpdate = false;
		}
		startDialogue(id, finishCallback, true);
	}

	function onDialogueComplete():Void
	{
		isInCutscene = false;

		if (currentDialogue != null)
		{
			currentDialogue.kill();
			remove(currentDialogue);
			currentDialogue = null;
		}
	}

	/**
	 * Initalizes, and starts the song's countdown.
	 */
	function startCountdown():Void
	{
		dadStrums.fadeNotes();
		playerStrums.fadeNotes();

		Countdown.initalize(boyfriend.startsCountdown ? boyfriend : dad);
		Countdown.countdownCamera = camHUD;

		Countdown.onIncrement.add(function(step:CountdownStep)
		{
			if (boyfriend.startsCountdown)
			{
				if (boyfriend.animation.exists(Countdown.countdownAnimStep(step)))
				{
					boyfriend.playAnim(Countdown.countdownAnimStep(step), true);
				}
			}
			else
			{
				if (dad.animation.exists(Countdown.countdownAnimStep(step)))
				{
					dad.playAnim(Countdown.countdownAnimStep(step), true);
				}
			}

			switch (Countdown.cameraType)
			{
				case ALTERNATE:
					focusOnDadGlobal = !focusOnDadGlobal;
					ZoomCam(focusOnDadGlobal);

					dispatchEvent(new CameraScriptEvent(CAMERA_MOVE_SECTION, focusOnDadGlobal, false));
				case LOCKED:
					focusOnDadGlobal = !boyfriend.startsCountdown;
					ZoomCam(focusOnDadGlobal);
			}
		});

		var event = new CountdownScriptEvent(COUNTDOWN_START, START, true);
		dispatchEvent(event);

		if (!event.eventCanceled)
		{
			if (skipCountdown)
			{
				resyncVocals();
				Conductor.instance.update(0);
			}
			Countdown.start(skipCountdown);
		}
	}

	/**
	 * Loads the song, and loads the chart into each strumline.
	 */
	private function generateSong():Void
	{
		if (currentChart == null)
			return;

		// Checks if a voices file exists, and if it doesn't no vocals are played.
		if (Assets.exists(currentChart.getVoicesPath()))
			vocals = new GameSound(VOICES).load(currentChart.getVoicesPath());
		else
			vocals = new GameSound(VOICES);

		SoundController.add(vocals);
		
		generatedMusic = true;
	}

	/**
	 * Prepares to play the song.
	 * Dependent on whether `startCallback` isn't `null`, and the song should start a different way.
	 */
	function prepareSong()
	{
		startingSong = true;

		if (startCallback != null)
		{
			startCallback();
		}
		else
		{
			startCountdown();
		}
	}

	/**
	 * Begins the song, and plays the necessary music.
	 */
	function startSong():Void
	{
		var event = new ScriptEvent(SONG_START, true);
		dispatchEvent(event);

		if (event.eventCanceled)
		{
			return;
		}

		startingSong = false;
		camZooming = true;

		if (timer != null)
			FlxTween.tween(timer, {alpha: 1}, 0.5);

		if (!paused)
		{
			SoundController.playMusic(currentChart.getInstrumentalPath(), 1, false);
			vocals.play();
		}
		changePresence(NORMAL(true, false));

		SoundController.music.onComplete = endSong;
	}

	/**
	 * Handles all necessary inputs.
	 * Responsible for managing controls, and player inputs.
	 */
	private function handleInputs():Void
	{
		if (isInCutscene)
			return;

		var upP = controls.UP_P;
		var rightP = controls.RIGHT_P;
		var downP = controls.DOWN_P;
		var leftP = controls.LEFT_P;

		var upR = controls.UP_R;
		var rightR = controls.RIGHT_R;
		var downR = controls.DOWN_R;
		var leftR = controls.LEFT_R;
		
		var key5 = controls.KEY5 && shapeNoteSongs.contains(currentSong.id.toLowerCase());

		var controlArray:Array<Bool> = [leftP, downP, upP, rightP];
		var releaseArray:Array<Bool> = [leftR, downR, upR, rightR];

		if (pressingKey5Global != key5)
		{
			pressingKey5Global = key5;

			playingStrumline.forEachStrum(function(strum:StrumNote)
			{
				strum.style = pressingKey5Global ? 'shape' : strum.baseStyle;
			});
		}
		
		playingStrumline.forEachStrum(function(strum:StrumNote)
		{
			strum.pressingKey5 = key5;
		});

		if (noteLimbo != null && noteLimbo.exists)
		{
			if (noteLimbo.hasBeenHit)
			{
				if ((key5 && noteLimbo.noteStyle == 'shape') || (!key5 && noteLimbo.noteStyle != 'shape'))
				{
					playingStrumline.hitNote(noteLimbo);
					noteLimbo = null;
				}
			}
			else
			{
				noteLimbo = null;
			}
		}
		if (noteLimboFrames != 0)
		{
			noteLimboFrames--;
		}
		else
		{
			noteLimbo = null;
		}

		if (controlArray.contains(true) && generatedMusic)
		{
			for (ind => control in controlArray)
			{
				if (control)
				{
					playingStrumline.pressKey(ind);

					var strum:StrumNote = playingStrumline.strums.members[ind];
					
					if (strum != null && !strum.animation.curAnim.name.startsWith('confirm'))
					{
						strum.playPress();
					}
				}
			}

			var possibleNotes:Array<Note> = playingStrumline.getPossibleNotes();

			haxe.ds.ArraySort.sort(possibleNotes, function(a, b):Int
			{
				var notetypecompare:Int = Std.int(a.strumTime - b.strumTime);

				if (notetypecompare == 0)
				{
					return Std.int(a.strumTime - b.strumTime);
				}
				return notetypecompare;
			});

			if (possibleNotes.length > 0)
			{
				// Jump notes
				var lastHitNote:Int = -1;
				var lastHitNoteTime:Float = -1;

				for (note in possibleNotes)
				{
					if (controlArray[note.direction % 4]) // further tweaks to the conductor safe zone offset multiplier needed.
					{
						if (lastHitNoteTime > Conductor.instance.songPosition - Conductor.instance.safeZoneOffset
							&& lastHitNoteTime < Conductor.instance.songPosition +
							(Conductor.instance.safeZoneOffset * 0.08)) // reduce the past allowed barrier just so notes close together that aren't jacks dont cause missed inputs
						{
							if ((note.direction % 4) == (lastHitNote % 4))
							{
								lastHitNoteTime = -999999; // reset the last hit note time
								continue; // the jacks are too close together
							}
						}
						if (note.noteStyle == 'shape' && !key5 || note.noteStyle != 'shape' && key5)
						{
							noteLimbo = note;
							noteLimboFrames = 8; // note limbo, the place where notes that could've been hit go.
							continue;
						}
						lastHitNote = note.direction;
						lastHitNoteTime = note.strumTime;
						
						playingStrumline.hitNote(note);
					}
				}
			}
			else if (!ghostTapping)
			{
				badNoteCheck();
			}
		}
		
		if (releaseArray.contains(true))
		{
			for (ind => control in releaseArray)
			{
				if (control)
				{
					playingStrumline.releaseKey(ind);
					playingStrumline.strums.members[ind].playStatic();
				}
			}
		}
	}

	/**
	 * Changes gameplay depending on a note's current state (ones that may have been missed, pressed, etc).
	 * Note states are handled and updated accordingly from `Strumline.hx` 
	 * @param elapsed The time since the last frame.
	 */
	function processNotes(elapsed:Float):Void
	{
		playingStrumline.forEachNote(function(note:Note)
		{
			if (note.tooLate && !note.handledMissed && !noMiss)
			{
				note.handledMissed = true;

				// Loss health and score based the note's hold note.
				if (note.sustainNote != null)
				{
					var lengthSec:Float = note.sustainNote.sustainLength / 1000;
					var scoreLoss:Int = Std.int(Math.min(SustainNote.SCORE_LOSS_MAX, Std.int(SustainNote.SCORE_LOSS_PER_SECOND * lengthSec)));
					var healthLoss:Float = Math.min(SustainNote.HEALTH_LOSS_MAX, SustainNote.HEALTH_LOSS_PER_SECOND * lengthSec);

					health -= healthLoss;
					songScore -= scoreLoss;

					note.sustainNote.handledMiss = true;
				}
			}
		});

		playingStrumline.forEachHoldNote(function(holdNote:SustainNote)
		{
			if (holdNote.hasBeenHit && !holdNote.hasMissed && holdNote.sustainLength > 0)
			{
				var fullHealthGain:Float = (holdNote.fullSustainLength / 1000.0) * SustainNote.HEALTH_GAIN_PER_SECOND;

				// The maximum amount of health the player can gain from this hold note is bigger than the cap.
				// Increment the health in accordance to the cap.
				if (fullHealthGain > SustainNote.HEALTH_GAIN_MAX)
				{
					var maxHealthMultipler:Float = SustainNote.HEALTH_GAIN_MAX / fullHealthGain;

					// Increment the health by the multiplier.
					// This makes it so the amount of health gained is actually the max.
					health += elapsed * maxHealthMultipler * SustainNote.HEALTH_GAIN_PER_SECOND;
				}
				else
				{
					health += elapsed * SustainNote.HEALTH_GAIN_PER_SECOND;
				}

				// No gaining score on no miss.
				if (!noMiss)
					songScore += Std.int(elapsed * SustainNote.SCORE_GAIN_PER_SECOND);
				
				return;
			}
			
			// Hold note was dropped as player was holding it.
			if (holdNote.hasMissed && !holdNote.handledMiss && !noMiss)
			{
				holdNote.handledMiss = true;

				// Penalize the player for dropping the hold note before it was completed.
				if (holdNote.sustainLength > SustainNote.PENALTY_MINIMUM)
				{
					var lengthRemainingSec:Float = holdNote.sustainLength / 1000.0;
					var healthLoss:Float = Math.min(lengthRemainingSec * SustainNote.HEALTH_LOSS_PER_SECOND, SustainNote.HEALTH_LOSS_MAX);
					var scoreLoss:Int = Std.int(lengthRemainingSec * SustainNote.SCORE_LOSS_PER_SECOND);
					var character:Character = holdNote.character ?? this.playingChar;
					
					var event = new HoldNoteScriptEvent(NOTE_HOLD_DROP, holdNote, character, healthLoss, combo, constructMissSound(), true);
					dispatchEvent(event);

					if (event.eventCanceled)
						return;

					combo = 0;
					health -= event.healthChange;
					songScore -= scoreLoss;

					event.missSound.play();
					
					muteVocals();
				}
				else
				{
					// Hold note is too short to be penalized, so just drop it, and make invisible.
					holdNote.visible = false;
				}
			}
		});
	}

	/**
	 * Zooms the camera to the given character.
	 * @param focusondad Whether to focus on the opponent, or the player.
	 */
	function ZoomCam(focusondad:Bool):Void
	{
		if (focusondad)
		{
			camGame.setFollow(dad.cameraFocusPoint.x, dad.cameraFocusPoint.y);
			camGame.cameraNoteOffset = dad.cameraNoteOffset;
		}
		else
		{
			camGame.setFollow(boyfriend.cameraFocusPoint.x, boyfriend.cameraFocusPoint.y);
			camGame.cameraNoteOffset = boyfriend.cameraNoteOffset;
		}
		dispatchEvent(new CameraScriptEvent(CAMERA_MOVE, focusOnDadGlobal, false));
	}

	/**
	 * Moves the camera based on the current measure of the song.
	 */
	function moveCameraSection():Void
	{
		var currentSection = currentChart.notes[curMeasure];
		if (generatedMusic && currentSection != null && !forceFocusOnChar)
		{
			focusOnDadGlobal = !currentSection.mustHitSection;
			ZoomCam(!currentSection.mustHitSection);

			dispatchEvent(new CameraScriptEvent(CAMERA_MOVE_SECTION, !currentSection.mustHitSection, false));
		}
	}

	/**
	 * Moves the camera based on the note direction that was hit.
	 * @param note The direction of the note that was hit.
	 * @param char The character that hit the note.
	 */
	function cameraMoveOnNote(note:Int, char:Character):Void
	{
		if (char == null)
			return;

		var amount:Array<Float> = new Array<Float>();
		var followAmount:Float = (Preferences.cameraNoteMovement && camMoveOnNoteAllowed) ? 20 : 0;
		switch (note)
		{
			case 0:
				amount[0] = -followAmount;
				amount[1] = 0;
			case 1:
				amount[0] = 0;
				amount[1] = followAmount;
			case 2:
				amount[0] = 0;
				amount[1] = -followAmount;
			case 3:
				amount[0] = followAmount;
				amount[1] = 0;
		}
		camGame.cameraNoteOffset.set(amount[0], amount[1]);
	}


	/**
	 * Resyncs the vocals to make sure they're matched up with the instrumental.
	 */
	function resyncVocals():Void
	{
		vocals.pause();
		SoundController.music.play();
		vocals.time = SoundController.music.time;
		vocals.play();
		
		Conductor.instance.update();

		changePresence(NORMAL(true, false));
	}

	/**
	 * Called when the song finishes.
	 * If `endSongCallback` isn't `null`, you'll need to handle state switching through scripts.
	 */
	function endSong():Void
	{
		canPause = false;
		camZooming = false;
		if (MathGameState.failedGame)
		{
			MathGameState.failedGame = false;
		}

		SoundController.music.volume = 0;
		vocals.volume = 0;
		SoundController.music.onComplete = null;
		
		var event = new ScriptEvent(SONG_END, true);
		dispatchEvent(event);

		if (event.eventCanceled)
			return;
		
		if (timer != null)
		{
			timer.canUpdate = false;
		}

		if (currentChart.validScore)
		{
			Highscore.saveScore(currentSong.id, songScore);
		}
		
		function endSongCallback(func:Void->Void)
		{
			if (endCallback != null)
				endCallback();
			else
				func();
		}

		if (PlayStatePlaylist.isStoryMode)
		{
			PlayStatePlaylist.campaignScore += songScore;

			if (PlayStatePlaylist.songList.length <= 0)
			{
				transIn = FlxTransitionableState.defaultTransIn;
				transOut = FlxTransitionableState.defaultTransOut;

				if (currentChart.validScore)
				{
					Highscore.saveWeekScore(PlayStatePlaylist.storyWeek, PlayStatePlaylist.campaignScore);
				}
				
				endSongCallback(() -> {
					SoundController.playMusic(Paths.music('freakyMenu'));
					FlxG.switchState(() -> new StoryMenuState());
				});
			}
			else
			{
				endSongCallback(() -> {
					nextSong();
				});
			}
		}
		else
		{
			endSongCallback(() -> {
				SoundController.playMusic(Paths.music('freakyMenu'));
				FlxG.switchState(() -> new FreeplayState());
			});
		}
	}


	/**
	 * Prepares to transition to the next song in the queue.
	 */
	function nextSong()
	{
		SoundController.music.stop();

		FlxTransitionableState.skipNextTransIn = true;
		FlxTransitionableState.skipNextTransOut = true;
		prevCamFollow = camGame.camFollow;

		var nextSongId:String = PlayStatePlaylist.songList.shift().toLowerCase();
		var nextSong:Song = SongRegistry.instance.fetchEntry(nextSongId);

		LoadingState.loadPlayState({targetSong: nextSong, targetVariation: currentVariation}, true);
	}

	/**
	 * Attempts to pause the game. If the countdown hasn't started or we aren't able to pause, don't pause.
	 */
	function runPause():Void
	{
		if (!canPause || paused || (!Countdown.countdownStarted && !isInCutscene))
			return;

		var event = new ScriptEvent(PAUSE, true);
		dispatchEvent(event);

		if (event.eventCanceled) return;

		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		TweenUtil.pauseTweens();
		FlxTimer.globalManager.forEach(function(t:FlxTimer)
		{
			t.active = false;
		});
		
		// 1 / 1000 chance for Gitaroo Man easter egg
		if (FlxG.random.bool(0.1))
		{
			FlxG.switchState(() -> new GitarooPause(params));
		}
		else
		{
			openSubState(new PauseSubState());
		}
	}

	/**
	 * Judges a note, and brings a popup score based on the result.
	 * @param strumtime The time to judge.
	 * @param note The note that was hit.
	 */
	private function popUpScore(strumtime:Float, note:Note):Void
	{
		var noteDiff:Float = Math.abs(strumtime - Conductor.instance.songPosition);
		vocals.volume = 1;

		var score:Int = 350;

		var daRating:String = "sick";

		if (noteDiff > Conductor.instance.safeZoneOffset * 2)
		{
			daRating = 'shit';
			totalNotesHit -= 2;
			score = 10;
		}
		else if (noteDiff < Conductor.instance.safeZoneOffset * -2)
		{
			daRating = 'shit';
			totalNotesHit -= 2;
			score = 25;
		}
		else if (noteDiff > Conductor.instance.safeZoneOffset * 0.45)
		{
			daRating = 'bad';
			score = 100;
			totalNotesHit += 0.2;
		}
		else if (noteDiff > Conductor.instance.safeZoneOffset * 0.25)
		{
			daRating = 'good';
			totalNotesHit += 0.65;
			score = 200;
		}
		if (daRating == 'sick')
		{
			totalNotesHit += 1;
		}

		if (!noMiss)
		{
			songScore += score;
		}
		ratings.ratingPopup(daRating, combo, note.noteStyle);

		changePresence(NORMAL(true, false));
	}

	function onStrumlineNoteSpawn(note:Note)
	{
		dispatchEvent(new NoteScriptEvent(NOTE_SPAWN, note, note.character, 0.0, 0, null, false));
	}

	/**
	 * Handles logic for when the player misses a note.
	 * @param direction The direction of the miss.
	 * @param note The note that was missed.
	 */
	function noteMiss(direction:Int = 1, note:Note, char:Character):Void
	{
		var event = new NoteScriptEvent(NOTE_MISS, note, char, healthDrainer, combo, constructMissSound());
		dispatchEvent(event);

		if (event.eventCanceled)
			return;

		health -= event.healthChange;
		
		if (event.note.noteStyle == 'phone')
		{
			var hitAnimation:Bool = event.note.character.animation.exists("hit");

			event.note.character.playAnim(hitAnimation ? 'hit' : 'singRIGHTmiss', true);

			if (event.note.strum != null)
			{
				FlxTween.cancelTweensOf(event.note.strum);
				event.note.strum.alpha = 0.01;
				FlxTween.tween(event.note.strum, {alpha: 1}, 2, {ease: FlxEase.expoIn});
			}
			health -= 0.07;
		}

		// Play the miss sound.
		event.missSound.play();

		misses++;
		combo = 0;
		songScore -= 100;

		updateAccuracy();
	}

	/**
	 * Called whenever the player presses the key of a note direction when there's no notes nearby.
	 * @param direction The direction pressed.
	 * @param char The character associated with the press.
	 */
	function ghostNoteMiss(direction:Int, char:Character):Void
	{
		var event = new GhostNoteScriptEvent(direction, char, healthDrainer, combo, constructMissSound());
		dispatchEvent(event);

		if (event.eventCanceled)
			return;
		
		health -= event.healthChange;

		// Play the miss sound.
		event.missSound.play();

		combo = 0;
		songScore -= 100;
	}

	/**
	 * Constructs a default miss sound for the game to play.
	 * @return A `GameSound` miss sound.
	 */
	function constructMissSound():GameSound
	{
		var defaultMiss:GameSound = new GameSound().load(Paths.soundRandom('missnote', 1, 3));
		defaultMiss.volume = FlxG.random.float(0.1, 0.2);

		return defaultMiss;
	}
	
	/**
	 * Resets the vocals fade timer, and completely unmutes the vocals.
	 * Called whenever either player sings.
	 */
	function unmuteVocals():Void
	{
		FlxTween.cancelTweensOf(vocals);

		vocalsFadeTimer?.cancel();
		vocalsFadeTimer = null;
		
		vocals.volume = 1;
	}

	/**
	 * Completely unmutes the vocals and runs a tween bringing a fade in.
	 * Called when the player misses a note.
	 */
	function muteVocals():Void
	{
		FlxTween.cancelTweensOf(vocals);

		vocalsFadeTimer?.cancel();
		vocalsFadeTimer = null;
		
		vocals.volume = 0;
		
		vocalsFadeTimer = FlxTween.tween(vocals, {volume: 1}, 0.5, {
			startDelay: 2.0,
			onComplete: (t:FlxTween) -> {
				vocalsFadeTimer = null;
			}
		});
	}

	/**
	 * Used to handle whenever the player presses inputs when there's no note in sight.
	 * Also known as, ghost tapping.
	 */
	function badNoteCheck():Void
	{
		var upP = controls.UP_P;
		var rightP = controls.RIGHT_P;
		var downP = controls.DOWN_P;
		var leftP = controls.LEFT_P;

		var controlArray:Array<Bool> = [leftP, downP, upP, rightP];

		for (i in 0...controlArray.length)
		{
			if (controlArray[i])
			{
				if (!noMiss)
					ghostNoteMiss(i, playingChar);
			}
		}
	}

	/**
	 * Updates the player's accuracy in accordance to the amount of notes they've hit.
	 */
	function updateAccuracy():Void
	{
		totalPlayed += 1;
		accuracy = totalNotesHit / totalPlayed * 100;

		changePresence(NORMAL(true, false));
	}
	
	/**
	 * Queues any necessary logic for whenever the user gets a game over.
	 */
	function gameOver():Void
	{
		isPlayerDying = true;

		persistentUpdate = false;
		persistentDraw = false;
		paused = true;

		vocals.stop();
		SoundController.music.stop();

		removeSignals();
		changePresence(GAMEOVER);

		var event = new ScriptEvent(GAME_OVER, true);
		dispatchEvent(event);

		if (!event.eventCanceled)
		{
			openSubState(new GameOverSubstate(playingChar.getScreenPosition().x, playingChar.getScreenPosition().y, playingChar));
		}
	}

	/**
	 * Switches the opponent character to the given character id.
	 * @param newChar The character to switch to.
	 * @param position The new position of the character.
	 * @param reposition Whether to reposition the character based on it's offsets.
	 * @param updateColor Whether to update any UI based on this Character.create's color.
	 */
	function switchDad(newChar:String, position:FlxPoint, reposition:Bool = true, updateColor:Bool = true):Void
	{
		if (reposition)
		{
			position.x -= dad.globalOffset[0];
			position.y -= dad.globalOffset[1];
		}
		this.currentStage.remove(dad);

		if (Preloader.trackedCharacters.exists(newChar))
		{
			dad = Preloader.trackedCharacters.get(newChar);
		}
		else
		{
			dad = Character.create(position.x, position.y, newChar, OPPONENT);
		}

		this.currentStage.addCharacter(dad, dad.characterType, position, reposition);

		iconP2.char = dad.characterIcon;

		healthBar.updateColors(dad, boyfriend);
		if (timer != null)
		{
			timer.updatePieColor(dad.characterColor);
		}
	}

	/**
	 * Switches the player character to the given character id.
	 * @param newChar The character to switch to.
	 * @param position The new position of the character.
	 * @param reposition Whether to reposition the character based on it's offsets.
	 * @param updateColor Whether to update any UI based on this Character.create's color.
	 */
	function switchBF(newChar:String, position:FlxPoint, reposition:Bool = true, updateColor:Bool = true):Void
	{
		if (reposition)
		{
			position.x -= boyfriend.globalOffset[0];
			position.y -= boyfriend.globalOffset[1];
		}
		this.currentStage.remove(boyfriend);

		if (Preloader.trackedCharacters.exists(newChar))
		{
			boyfriend = Preloader.trackedCharacters.get(newChar);
		}
		else
		{
			boyfriend = Character.create(position.x, position.y, newChar, PLAYER);
		}
		this.currentStage.addCharacter(boyfriend, boyfriend.characterType, position, reposition);
		
		iconP1.char = boyfriend.characterIcon;

		healthBar.updateColors(dad, boyfriend);
	}

	/**
	 * Switches the player character to the given character id.
	 * @param newChar The character to switch to.
	 * @param position The new position of the character.
	 * @param reposition Whether to reposition the character based on it's offsets.
	 */
	function switchGF(newChar:String, position:FlxPoint, ?reposition:Bool = true):Void
	{
		if (reposition)
		{
			position.x -= gf.globalOffset[0];
			position.y -= gf.globalOffset[1];
		}
		this.currentStage.remove(gf);

		if (Preloader.trackedCharacters.exists(newChar))
		{
			gf = Preloader.trackedCharacters.get(newChar);
		}
		else
		{
			gf = Character.create(position.x, position.y, newChar, GF);
		}

		this.currentStage.addCharacter(gf, gf.characterType, position, reposition);
	}

	/**
	 * Toggles all strumlines visibility, and does a fade effect.
	 * @param invisible Whether they should be invisible, or not.
	 */
	function makeInvisibleNotes(invisible:Bool):Void
	{
		for (i in [playerStrums, dadStrums])
		{
			i.forEachStrum(function(strumNote:StrumNote)
			{
				FlxTween.cancelTweensOf(strumNote);
				FlxTween.tween(strumNote, {alpha: (invisible ? 0 : 1)}, 1);
			});
		}
	}

	/**
	 * Changes the scroll speed of the song based on a given ease.
	 * @param multiplier The speed to multiply based on the song's base speed.
	 * @param time The duration to which the speed at.
	 * @param easeType How the speed of the song should ease to the target.
	 * @param onComplete Called when the tween associated with the speed change is complete.
	 */
	function changeScrollSpeed(multiplier:Float, time:Float, easeType:EaseFunction, ?onComplete:Void->Void):Void
	{
		FlxTween.cancelTweensOf(songSpeed);
		var newSpeed = currentChart.speed * multiplier;
		time <= 0 ? {
			songSpeed = newSpeed;
			if (onComplete != null)
				onComplete();
		} : {
			FlxTween.tween(this, {songSpeed: newSpeed}, time, {
				ease: easeType,
				onComplete: function(tween:FlxTween)
				{
					if (onComplete != null)
						onComplete();
				}
			});
		}
	}

	/**
	 * Changes the Discord Rich Presence based on a specific type.
	 * @param type The type to change it based off.
	 */
	function changePresence(type:api.Discord.RPCType):Void
	{
		if (currentChart == null)
			return;

		var icon:String = DiscordClient.getSongIcon(currentSong.id, currentChart.opponent);

		var detailsText:String = PlayStatePlaylist.isStoryMode ? 'Story Mode: Week ${PlayStatePlaylist.storyWeek}' : 'Freeplay';
		var mainDetails:String = '${currentChart.songName}';
		var statsDetails:String = '\nAcc: ${FlxMath.roundDecimal(accuracy, 2)}% | Score: ${songScore} | Misses: ${misses}';

		var timeDetails:Null<Float> = SoundController.music.length - SoundController.music.time;

		switch (type)
		{
			case NORMAL(stats, time):
				statsDetails = stats ? statsDetails : '';
				timeDetails = time ? timeDetails : null;

				DiscordClient.changePresence('$detailsText - $mainDetails', statsDetails, icon, timeDetails != null, timeDetails);
			case PAUSED:
				var pausedText = '(PAUSED) $detailsText - $mainDetails';

				DiscordClient.changePresence('$pausedText', statsDetails, icon);
			case GAMEOVER:
				DiscordClient.changePresence('(GAME OVER) ${mainDetails}', statsDetails, icon);
			case CUSTOM(details, state, smallImageKey, hasStartTimestamp, endTimestamp, largeImageKey):
				DiscordClient.changePresence(details, state, smallImageKey, hasStartTimestamp, endTimestamp, largeImageKey);
		}
	}

	/**
	 * Handles singing for an opponent character.
	 * @param char The opponent character to sing.
	 * @param note The note that was hit by the opponent.
	 */
	function opponentSing(char:Character, note:Note):Void
	{
		if (char == null || note == null)
			return;

		var event = new NoteScriptEvent(OPPONENT_NOTE_HIT, note, char, 0.0, combo, null);
		dispatchEvent(event);

		// Cancelling this event will make the opponent not sing.
		if (event.eventCanceled)
			return;

		var altAnim:String = '';
		if (event.note.noteStyle == 'phone-alt')
		{
			altAnim = '-alt';
		}

		switch (event.note.noteStyle)
		{
			case 'phone':
				char.playAnim('smash', true);
			default:
				char.sing(event.note.direction, false, altAnim);
		}

		cameraMoveOnNote(event.note.direction, char);
		unmuteVocals();
	}

	/**
	 * Handles the singing for a player character.
	 * @param char The character to sing.
	 * @param note The note that was hit by the opponent.
	 */
	function playerSing(char:Character, note:Note):Void
	{
		var event = new NoteScriptEvent(PLAYER_NOTE_HIT, note, char, healthGainer, combo + 1, null);
		dispatchEvent(event);

		// Cancelling this event will make the player not sing.
		if (event.eventCanceled)
			return;
		
		switch (event.note.noteStyle)
		{
			default:
				event.character.sing(event.note.direction);
			case 'phone':
				var hitAnimation:Bool = event.character.animation.exists('dodge');
				var heyAnimation:Bool = event.character.animation.exists('hey');

				event.character.playAnim(hitAnimation ? 'dodge' : (heyAnimation ? 'hey' : 'singUPmiss'), true);
				gf.playAnim('cheer', true);
				
				if (!note.phoneHit)
				{
					opposingChar.playAnim(opposingChar.animation.exists('throw') ? 'throw' : 'smash', true);
				}
		}
		gf.playComboAnimation(event.comboCount);

		combo++;
		health += event.healthChange; // This allows to be able to change how health the player gains from the note.
		
		popUpScore(event.note.strumTime, event.note);
		cameraMoveOnNote(event.note.direction, event.character);

		unmuteVocals();

		if (Preferences.hitsounds)
		{
			SoundController.play(Paths.sound('note_click'), Preferences.hitsoundsVolume);
		}
		updateAccuracy();
	}
}
