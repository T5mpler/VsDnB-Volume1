package ui.menu.freeplay;

import audio.GameSound;
import backend.Conductor;
import data.character.CharacterRegistry;
import data.language.LanguageManager;
import data.song.Highscore;
import data.song.SongRegistry;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxObject;
import flixel.group.FlxSpriteGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import play.LoadingState;
import play.PlayState;
import play.PlayStatePlaylist;
import play.ui.HealthIcon;
import play.save.Preferences;
import play.song.Song;
import ui.Alphabet;
import ui.MusicBeatState;
import ui.menu.freeplay.category.Category;
import ui.select.charSelect.CharacterSelect;
import util.FileUtil;

#if desktop
import api.Discord.DiscordClient;
#end

using StringTools;

/**
 * A menu that allows the user to select between any songs from story mode, or any extra songs.
 */
class FreeplayState extends MusicBeatState
{
	/**
	 * Debug feature: Automatically unlocks all songs.
	 */
	public static var unlockAll:Bool = false;

	/**
	 * A list of all of the songs that skip the character select.
	 */
	public static final skipSelect:Array<String> = ['backseat', 'five-nights', 'vs-dave-rap', 'vs-dave-rap-two'];

	/**
	 * Raw list of all secret songs, and their hint text.
	 */
	public static final secretSongs:Map<String, String> = [
		'supernovae' => 'supernovae_hint',
		'glitch' => 'glitch_hint',
		'master' => 'master_hint',
		'kabunga' => 'kabunga_hint',
		'roofs' => 'roofs_hint',
		'vs-dave-rap-two' => 'rapTwo_hint'
	];

	/**
	 * Whether the user's able to interact with the menu.
	 */
	var canInteract:Bool = true;

	/**
	 * Tells whether we're in a category, or we're selecting a song.
	 */
	var InMainFreeplayState:Bool = false;

	/**
	 * A list of all of the songs the user has unlocked. Automatically populated when entering the menu.
	 */
	var songsUnlocked:Array<String> = [];

	/**
	 * A list of all of the songs the user has unlocked IN the category.
	 * Gets populated when the category is open. If any exist, all are unlocked in quick sequence.
	 */
	var unlockableSongs:Array<String> = [];

	var waitingToInteract:Bool = false;

	/**
	 * Invisible object used to move the camera around when selecting a category.
	 */
	var camFollow:FlxObject;

	/**
	 * The previous object used. If this exists, `camFollow` is set to it so the position is saved.
	 */
	var prevCamFollow:FlxObject;

	/**
	 * The menu background.
	 */
	var bg:FlxSprite = new FlxSprite();
	
	/**
	 * The original color of the background.
	 */
	var defColor:FlxColor;


	// CATEGORIES //

	/**
	 * The current pack that is selected by the user.
	 * Static variable so the current selection is saved when the user goes back to the menu.
	 */
	static var CurrentPack:Int = 0;

	/**
	 * List of the ids of all the selectable categories.
	 */
	var categoriesIds:Array<String> = ['main', 'extras', 'joke'];

	/**
	 * A list of all category objects, generated on create.
	 */
	var categories:Array<Category> = [];

	/**
	 * The current data category the user has selected.
	 */
	var currentCategory:Category;

	/**
	 * List of all of the text objects for the categories.
	 */
	var titles:Array<Alphabet> = [];

	/**
	 * List of all of the category icons.
	 */
	var icons:Array<FlxSprite> = [];


	// FREEPLAY //

	/**
	 * The index of the current selected song.
	 */
	var curSelected:Int = 0;
	
	/**
	 * Used to help animate the score text to it's intended score.
	 */
	var lerpScore:Int = 0;

	/**
	 * The actual score of the song.
	 * The score text animates to this via `lerpScore`
	 */
	var intendedScore:Int = 0;
	
	/**
	 * Whether the character text should be shown.
	 * Only true AFTER the user has entered the character select at least once.
	 */
	var showCharText:Bool = true;
	
	/**
	 * Whether a category's currently being loaded, or not.
	 */
	var loadingPack:Bool = false;
	
	/**
	 * The metadata of all of the songs being displayed in the category the user's on.
	 */
	var songs:Array<SongMetadata> = [];
	
	/**
	 * The background under `scoreText`
	 */
	var scoreBG:FlxSprite;

	/**
	 * The text that displays the score of the current song selected.
	 */
	var scoreText:FlxText;

	/**
	 * A group that holds all of the displayed selectable songs.
	 */
	var grpSongs:FlxTypedGroup<FreeplayAlphabet> = new FlxTypedGroup<FreeplayAlphabet>();

	/**
	 * A group that holds all of the icons for the selectable songs.
	 */
	var grpIcons:FlxTypedGroup<HealthIcon> = new FlxTypedGroup<HealthIcon>();

	/**
	 * The hint text that tells the user about skipping the character select.
	 * Only displays AFTER the user has seen the character select at least once.
	 */
	var characterSelectText:FlxText;

	// HINT TEXTS //
	 
	/**
	 * Is the user able to see the hint texts shown? 
	 */
	var canShowHints:Bool = false;

	/**
	 * Whether the game's currently showing a hint text.
	 * Used for transitions. 
	 */
	var showingHint:Bool;
	
	/**
	 * The group that holds all of the hint text objects for easy transitioning, and rendering.
	 */
	var lockHintGroup:FlxSpriteGroup = new FlxSpriteGroup();

	/**
	 * The border shown in the hint text.
	 */
	var lockHintBorder:FlxSprite;

	/**
	 * The text that displays a secret song's hint text.
	 */
	var lockHintText:FlxText;

	/**
	 * Initalizes any save data relating to this menu.
	 */
	public static function initSave()
	{
		if (FlxG.save.data.locked == null)
		{
			var lockMap:Map<String, String> = new Map<String, String>();

			for (song in secretSongs.keys())
			{
				lockMap[song.toLowerCase()] = 'locked';
			}
			FlxG.save.data.locked = lockMap;
			FlxG.save.flush();
		}
	}

	/**
	 * Queues a song to being unlocked.
	 * @param song The song to unlock.
	 */
	public static function unlockSong(song:String)
	{
		var lockStates:Map<String, String> = FlxG.save.data.locked;
		if (lockStates.exists(song) && lockStates.get(song) != 'unlocked')
		{
			FlxG.save.data.locked.set(song, 'waiting');
			FlxG.save.flush();
		}
	}

	override function create()
	{
		populateUnlocks();

		if (!SoundController.music?.playing ?? true)
		{
			SoundController.playMusic(Paths.music('freakyMenu'));
		}

		#if desktop
		DiscordClient.changePresence("In the Freeplay Menu", null);
		#end

		showCharText = FlxG.save.data.wasInCharSelect;

		bg.loadGraphic(FileUtil.randomizeBG());
		bg.color = 0xFF4965FF;
		defColor = bg.color;
		bg.scrollFactor.set();
		add(bg);

		for (i in 0...categoriesIds.length)
		{
			var category:Category = Category.getCategory(categoriesIds[i]);
			
			var CurrentSongIcon:FlxSprite = new FlxSprite(0, 0).loadGraphic(category.getIcon());
			CurrentSongIcon.centerOffsets(false);
			CurrentSongIcon.x = (1000 * i + 1) + (512 - CurrentSongIcon.width);
			CurrentSongIcon.y = (FlxG.height / 2) - 256;
			CurrentSongIcon.antialiasing = true;

			var NameAlpha:Alphabet = new Alphabet(40, (FlxG.height / 2) - 282, category.getName());
			NameAlpha.screenCenter(X);
			NameAlpha.x += ((1000 * i + 1) + (128 - CurrentSongIcon.width));

			add(CurrentSongIcon);
			icons.push(CurrentSongIcon);
			add(NameAlpha);
			titles.push(NameAlpha);

			categories.push(category);
		}
		currentCategory = categories[CurrentPack];

		camFollow = new FlxObject(0, 0, 1, 1);
		camFollow.setPosition(icons[CurrentPack].x + 256, icons[CurrentPack].y + 256);


		if (prevCamFollow != null)
		{
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0.15);
		FlxG.camera.focusOn(camFollow.getPosition());
		
		add(grpSongs);
		add(grpIcons);

		super.create();
	}
	
	override function update(elapsed:Float)
	{
		super.update(elapsed);
		
		Conductor.instance.update(Conductor.instance.songPosition + FlxG.elapsed * 1000);
		Conductor.instance.quickWatch();
		
		// Selector Menu Functions
		if (!InMainFreeplayState)
		{
			if (canInteract && (controls.LEFT_P || FlxG.mouse.wheel < 0))
				UpdatePackSelection(-1);
			if (canInteract && (controls.RIGHT_P || FlxG.mouse.wheel > 0))
				UpdatePackSelection(1);

			if (controls.BACK && canInteract)
			{
				FlxG.switchState(() -> new MainMenuState());
			}
			if (controls.ACCEPT && !loadingPack && canInteract)
			{
				canInteract = false;
				SoundController.play(Paths.sound('confirmMenu'), 0.7);

				new FlxTimer().start(0.2, function(Dumbshit:FlxTimer)
				{
					loadingPack = true;
					LoadProperPack();

					for (item in icons)
					{
						FlxTween.tween(item, {alpha: 0, y: item.y - 200}, 0.2, {ease: FlxEase.cubeInOut});
					}
					for (item in titles)
					{
						FlxTween.tween(item, {alpha: 0, y: item.y - 200}, 0.2, {ease: FlxEase.cubeInOut});
					}

					new FlxTimer().start(0.2, function(Dumbshit:FlxTimer)
					{
						for (item in icons)
						{
							item.visible = false;
						}
						for (item in titles)
						{
							item.visible = false;
						}
						GoToActualFreeplay();
						InMainFreeplayState = true;
						loadingPack = false;
					});
				});
			}
			return;
		}
		else
		{
			// Freeplay Functions
			var upP = controls.UP_P || FlxG.mouse.wheel > 0;
			var downP = controls.DOWN_P || FlxG.mouse.wheel < 0;
			var accepted = controls.ACCEPT;

			onUpdate(elapsed);

			if (upP && canInteract)
			{
				changeSelection(-1);
			}
			if (downP && canInteract)
			{
				changeSelection(1);
			}

			if (controls.BACK && canInteract)
			{
				loadingPack = true;
				canInteract = false;
				
				FlxTween.cancelTweensOf(lockHintGroup);
				FlxTween.tween(lockHintGroup, {y: FlxG.height}, 0.5, {ease: FlxEase.expoOut, onComplete: function(t:FlxTween) {
					for (spr in lockHintGroup.members) {
						lockHintGroup.remove(spr);
						spr = null;
					}
					lockHintGroup.clear();
					remove(lockHintGroup);
				}});
				
				for (i in grpSongs)
				{
					i.unlockY = true;

					FlxTween.tween(i, {y: 5000, alpha: 0}, 0.3, {
						onComplete: function(twn:FlxTween)
						{
							for (item in icons)
							{
								item.visible = true;
								FlxTween.tween(item, {alpha: 1, y: item.y + 200}, 0.2, {ease: FlxEase.cubeInOut});
							}
							for (item in titles)
							{
								item.visible = true;
								FlxTween.tween(item, {alpha: 1, y: item.y + 200}, 0.2, {ease: FlxEase.cubeInOut});
							}

							if (scoreBG != null)
							{
								FlxTween.tween(scoreBG, {y: scoreBG.y - 100}, 0.3, {
									ease: FlxEase.expoInOut,
									onComplete: function(spr:FlxTween)
									{
										scoreBG = null;
									}
								});
							}

							if (scoreText != null)
							{
								FlxTween.tween(scoreText, {y: scoreText.y - 100}, 0.3, {
									ease: FlxEase.expoInOut,
									onComplete: function(spr:FlxTween)
									{
										scoreText = null;
									}
								});
							}
							if (showCharText && characterSelectText != null)
							{
								FlxTween.tween(characterSelectText, {alpha: 0}, 0.3, {
									ease: FlxEase.expoInOut,
									onComplete: function(spr:FlxTween)
									{
										characterSelectText = null;
									}
								});
							}
							InMainFreeplayState = false;
							loadingPack = false;

							for (i in grpSongs)
							{
								remove(i);
							}
							for (i in grpIcons.members)
							{
								remove(i);
							}
							
							if (Preferences.flashingLights)
								FlxTween.color(bg, 0.25, bg.color, defColor);

							// MAKE SURE TO RESET EVERYTHIN!
							songs = [];
							curSelected = 0;
							canInteract = true;
							
							grpSongs.members = [];
							grpSongs.clear();
							
							grpIcons.members = [];
							grpIcons.clear();
						}
					});
				}
			}
			if (accepted && canInteract && !songs[curSelected].locked)
			{
				for (song in grpSongs)
				{
					song.menuItemTween?.cancel();
				}
				switch (songs[curSelected].song.id)
				{
					case 'backseat':
						FlxG.switchState(() -> new ui.select.playerSelect.BackseatSelect());
					default:
						SoundController.music.fadeOut(1, 0);
						
						var song = songs[curSelected].song;
						
						PlayStatePlaylist.reset();
						PlayStatePlaylist.isStoryMode = false;
						PlayStatePlaylist.storyWeek = songs[curSelected].week;

						if (FlxG.keys.pressed.CONTROL || skipSelect.contains(song.id.toLowerCase()))
						{
							CharacterSelect.selectedCharacter = null;
							LoadingState.loadAndSwitchState(() -> new PlayState({
								targetSong: song,
								targetVariation: ''
							}));
						}
						else
						{
							if (!FlxG.save.data.wasInCharSelect)
							{
								FlxG.save.data.wasInCharSelect = true;
								FlxG.save.flush();
							}
							LoadingState.loadAndSwitchState(() -> new CharacterSelect({targetSong: song}));
						}
				}
			}
		}

		if (SoundController.music.volume < 0.7)
		{
			SoundController.music.volume += 0.5 * FlxG.elapsed;
		}

		lerpScore = Math.floor(FlxMath.lerp(lerpScore, intendedScore, 0.4));

		if (Math.abs(lerpScore - intendedScore) <= 10)
			lerpScore = intendedScore;

		if (scoreText != null)
			scoreText.text = LanguageManager.getTextString('freeplay_score') + ': $lerpScore';

		positionHighscore();
	}

	function onUpdate(elapsed:Float)
	{
		for (song in grpSongs)
		{
			if (song.onUpdate != null)
				song.onUpdate(elapsed);
		}
	}
	
	override function stepHit(step:Int)
	{
		if (!super.stepHit(step)) 
			return false;
		
		for (song in grpSongs.members)
		{
			if (song.onStepHit != null)
				song.onStepHit();
		}
		return true;
	}

	override function beatHit(beat:Int)
	{
		if (!super.beatHit(beat)) 
			return false;
		
		for (song in grpSongs.members)
		{
			if (song.onBeatHit != null)
				song.onBeatHit();
		}
		return true;
	}
	
	override function measureHit(measure:Int)
	{
		if (!super.measureHit(measure)) 
			return false;

		for (song in grpSongs.members)
		{
			if (song.onMeasureHit != null)
				song.onMeasureHit();
		}
		return true;
	}

	public function LoadProperPack()
	{
		for (song in currentCategory.getSongs())
		{
			addSong(song);
		}
	}

	public function GoToActualFreeplay()
	{
		populateUnlockableSongs();

		for (i in 0...songs.length)
		{
			var songText:FreeplayAlphabet = new FreeplayAlphabet(songs[i]);
			songText.menuItemGroup = cast grpSongs.members;
			songText.targetY = i;
			songText.alpha = 0;
			songText.y += 1000;
			grpSongs.add(songText);

			var icon:HealthIcon = new HealthIcon(songs[i].locked ? 'lock' : songs[i].songCharacter);
			icon.sprTracker = songText;
			icon.scrollFactor.set();
			grpIcons.add(icon);

			switch (songs[i].song.id)
			{
				case "polygonized":
					songText.onUpdate = function(elapsed:Float)
					{
						songText.forEachCharacter(function(char:AlphaCharacter) {
							char.offset.x = FlxG.random.int(-3, 3);
							char.offset.y = FlxG.random.int(-3, 3);
						});
					}
				case "interdimensional":
					songText.onUpdate = function(elapsed:Float) {
						var index = 0;
						songText.forEachCharacter(function(char:AlphaCharacter) {
							char.offset.x = Math.cos(FlxG.game.ticks / 750) * 8 * (index % 2 == 0 ? 1 : -1);
							char.offset.y = Math.sin(FlxG.game.ticks / 500) * 5 * (index % 2 == 0 ? 1 : -1);
							index++;
						});
					}
				case 'escape-from-california':
					songText.text = "Escape From\nCalifornia";
					songText.alignment = FlxTextAlign.CENTER;
			}
		}

		scoreText = new FlxText(FlxG.width * 0.7, 0, 0, "", 32);
		scoreText.setFormat(Paths.font("comic.ttf"), 32, FlxColor.WHITE, LEFT);
		scoreText.antialiasing = true;
		scoreText.y = -225;
		scoreText.scrollFactor.set();

		scoreBG = new FlxSprite(scoreText.x - 6, 0).makeGraphic(1, 42, 0xFF000000);
		scoreBG.alpha = 0.6;
		scoreBG.scrollFactor.set();
		add(scoreBG);

		if (showCharText)
		{
			characterSelectText = new FlxText(FlxG.width, FlxG.height, 0, LanguageManager.getTextString("freeplay_skipChar"), 18);
			characterSelectText.setFormat("Comic Sans MS Bold", 18, FlxColor.WHITE, FlxTextAlign.LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			characterSelectText.borderSize = 1.5;
			characterSelectText.antialiasing = true;
			characterSelectText.scrollFactor.set();
			characterSelectText.alpha = 0;
			characterSelectText.x -= characterSelectText.textField.textWidth + 10;
			characterSelectText.y -= characterSelectText.textField.textHeight;
			characterSelectText.x += 150;
			add(characterSelectText);

			FlxTween.tween(characterSelectText, {x: characterSelectText.x - 150, alpha: 1}, 0.5, {ease: FlxEase.expoInOut});
		}
		
		add(scoreText);
		
		// Add Hint Text
		lockHintGroup.scrollFactor.set();
		add(lockHintGroup);

		lockHintBorder = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		lockHintBorder.scale.set(FlxG.width, 150);
		lockHintBorder.updateHitbox();
		lockHintBorder.alpha = 0.6;
		lockHintGroup.add(lockHintBorder);

		lockHintText = new FlxText(0, 0, FlxG.width, '');
		lockHintText.setFormat(Paths.font('comic_normal.ttf'), 24, FlxColor.WHITE, FlxTextAlign.CENTER);
		lockHintText.screenCenter(X);
		lockHintGroup.add(lockHintText);

		lockHintGroup.screenCenter(X);
		lockHintGroup.y = FlxG.height;
		
		FlxTween.tween(scoreBG, {y: 0}, 0.5, {ease: FlxEase.expoInOut});
		FlxTween.tween(scoreText, {y: -5}, 0.5, {ease: FlxEase.expoInOut});

		for (i in 0...grpSongs.length)
		{
			FlxTween.tween(grpSongs.members[i], {y: 0, alpha: i == curSelected ? 1 : 0.6}, 0.5, {
				ease: FlxEase.expoInOut,
				onComplete: function(twn:FlxTween)
				{
					grpSongs.members[i].unlockY = false;
				}
			});
		}

		new FlxTimer().start(0.5, function(t:FlxTimer)
		{
			updateSongPositions();
			
			// There's songs to be unlocked.
			var canUnlockSongs:Bool = unlockableSongs.length > 0;

			canInteract = !canUnlockSongs;
			canShowHints = !canUnlockSongs;

			if (canUnlockSongs)
			{
				unlockNextAvailableSong();
			}
		});
		changeSelection();
	}

	function changeSelection(change:Int = 0)
	{
		SoundController.play(Paths.sound('scrollMenu'), 0.4);

		curSelected += change;

		if (curSelected < 0)
			curSelected = songs.length - 1;

		if (curSelected >= songs.length)
			curSelected = 0;

		#if !switch
		intendedScore = Highscore.getScore(songs[curSelected].song.id);
		#end
		var bullShit:Int = 0;

		for (i in 0...grpIcons.members.length)
		{
			grpIcons.members[i].alpha = 0.6;
		}

		grpIcons.members[curSelected].alpha = 1;

		for (item in grpSongs.members)
		{
			item.targetY = bullShit - curSelected;
			bullShit++;

			item.alpha = 0.6;

			if (item.targetY == 0)
			{
				item.alpha = 1;
			}	
		}
		updateSongPositions();

		if (Preferences.flashingLights)
			FlxTween.color(bg, 0.25, bg.color, songs[curSelected].color);

		if (canShowHints)
		{
			if (songs[curSelected].locked)
			{
				lockHintText.text = LanguageManager.getTextString(secretSongs.get(songs[curSelected].song.id));
				lockHintText.screenCenter(X);

				if (!showingHint)
				{
					showingHint = true;

					FlxTween.cancelTweensOf(lockHintGroup);
					FlxTween.tween(lockHintGroup, {y: FlxG.height - lockHintGroup.height}, 0.5, {ease: FlxEase.expoOut});
				}
			}
			else
			{
				if (showingHint)
				{
					showingHint = false;

					FlxTween.cancelTweensOf(lockHintGroup);
					FlxTween.tween(lockHintGroup, {y: FlxG.height}, 0.5, {ease: FlxEase.expoOut});
				}
			}
		}
	}

	public function UpdatePackSelection(change:Int)
	{
		CurrentPack += change;

		if (CurrentPack == -1)
			CurrentPack = categories.length - 1;

		if (CurrentPack == categories.length)
			CurrentPack = 0;

		currentCategory = categories[CurrentPack];

		camFollow.x = icons[CurrentPack].x + 256;
	}

	public function addSong(song:CategorySong)
	{
		var songData:Song = SongRegistry.instance.fetchEntry(song.id);
		var songIcon:String = song.icon ?? CharacterRegistry.instance.fetchData(songData.getChart(Song.DEFAULT_VARIATION).opponent).icon;

		songs.push(new SongMetadata(songData, song.week ?? -1, songIcon, song.color[0]));
	}

	public function addWeek(songs:Array<CategorySong>)
	{
		for (song in songs)
		{
			addSong(song);
		}
	}

	/**
	 * Updates the positions of each song in the menu based on the current selection.
	 */
	function updateSongPositions():Void
	{
		for (item in grpSongs.members)
		{
			item.setupMenuTween(item.targetY);
		}
	}

	/**
	 * Manually positions the highscore display shown in the UI when selecting a song.
	 */
	function positionHighscore()
	{
		if (scoreText != null)
			scoreText.x = FlxG.width - scoreText.width - 6;

		if (scoreBG != null)
		{
			scoreBG.scale.x = FlxG.width - scoreText.x + 6;
			scoreBG.x = FlxG.width - (scoreBG.scale.x / 2);
		}
	}

	/**
	 * Stores all of the songs the user has unlocked, but hasn't shown.
	 */
	function populateUnlocks():Void
	{
		var lockSave:Map<String, String> = FlxG?.save?.data?.locked ?? new Map<String, String>();
		
		for (song => state in lockSave)
		{
			if (state == 'waiting')
			{
				songsUnlocked.push(song);
			}
		}
	}

	/**
	 * Stores all of the songs the user has unlocked, specific to the category they're currently on.
	 */
	function populateUnlockableSongs():Void
	{
		unlockableSongs = [];

		for (song in songs)
		{
			// The song in THIS category exists in the unlocked songs list, push into the array.
			if (songsUnlocked.contains(song.song.id.toLowerCase()))
			{
				unlockableSongs.push(song.song.id.toLowerCase());
				songsUnlocked.remove(song.song.id.toLowerCase());
			}
		}
	}

	/**
	 * Gets the index for a song from of its category.
	 * @param song The lower-case version of the song to check.
	 * @return The category index of the song.
	 */
	function getSongIndex(song:String):Int
	{
		for (i in 0...songs.length)
		{
			if (songs[i].song.id.toLowerCase() == song)
				return i;
		}
		return -1;
	}

	/**
	 * Picks a random song from the list of songs that can be locked, and unlocks them.
	 */
	function unlockNextAvailableSong():Void
	{
		if (unlockableSongs.length > 0)
		{
			var songToUnlock:String = FlxG.random.getObject(unlockableSongs);

			playUnlockSequence(songToUnlock);
			unlockableSongs.remove(songToUnlock);
		}
		else
		{
			// No more songs need to be unlocked.
			waitingToInteract = true;
		}
	}

	/**
	 * Plays sequence that happens when a song is about to be unlocked.
	 * @param song The song to play the sequence for, and unlock.
	 */
	function playUnlockSequence(song:String)
	{
		var index:Int = getSongIndex(song);

		// Song either doesn't exist, or isn't in this category.
		if (index == -1)
			return;

		var selectChange:Int = index - curSelected;

		// Change the selection to the current unlocking song.
		changeSelection(selectChange);

		var songIcon:HealthIcon = grpIcons.members[index];
		var songText:FreeplayAlphabet = grpSongs.members[index];
		var songMetadata:SongMetadata = songs[index];
		
		SoundController.play(Paths.sound('freeplay/unlockRiser'), 0.8);

		FlxTween.tween(songIcon.scale, {x: 1.1, y: 1.1}, 2, {
			onComplete: (t:FlxTween) -> 
			{
				SoundController.play(Paths.sound('freeplay/unlock_lockBreak'), 0.8);
				
				// Change the icon to the unlock icon.
				songIcon.frames = Paths.getSparrowAtlas('freeplay/freeplay_unlock');
				songIcon.animation.addByPrefix('unlock', 'freeplay_unlock', 24, false);
				songIcon.animation.play('unlock', true);

				// Reset the scale.
				songIcon.scale.set(1, 1);

				// Quick un-lock the next song in the list.
				// If there's no song that needs to be unlocked, it'll automatically resume back the controls.
				new FlxTimer().start(0.5, (t:FlxTimer) -> 
				{
					unlockNextAvailableSong();
				});

				new FlxTimer().start(1, (t:FlxTimer) ->
				{
					// Song is unlocked now. Change the unlock state.
					@:privateAccess
					songMetadata.locked = false;
					FlxG.save.data.locked.set(songMetadata.song.id.toLowerCase(), 'unlocked');
					FlxG.save.flush();

					// Do a quick succession with the text showing.
					var listLength:Array<Int> = [for (i in 0...songMetadata.song.songName.length) i];

					new FlxTimer().start(0, (t:FlxTimer) ->
					{
						if (listLength.length > 0)
						{
							var index:Int = listLength.shift();

							var char:String = songMetadata.song.songName.charAt(index);
							var splitText:Array<String> = songText.text.split('');

							splitText[index] = char;

							songText.text = splitText.join('');

							var unlockPop:GameSound = SoundController.play(Paths.sound('freeplay/unlockPop'), 0.8);
							unlockPop.pitch = FlxG.random.float(0.8, 1.1);

							t.reset(0.05);
						}
						else
						{
							// Change the visuals to show it's unlocked.
							songIcon.char = songMetadata.songCharacter;

							var confetti:FlxSprite = new FlxSprite();
							confetti.frames = Paths.getSparrowAtlas('freeplay/icon_confetti');
							confetti.animation.addByPrefix('confetti', 'icon_confetti', 24, false);
							confetti.animation.play('confetti', true);
							confetti.animation.onFinish.addOnce((anim:String) ->
							{
								remove(confetti);
							});
							confetti.scrollFactor.set();
							confetti.setPosition(songIcon.x + (songIcon.width - confetti.width) / 2, songIcon.y + (songIcon.height - confetti.height) / 2);
							add(confetti);
							
							// Unlock controls now that all unlock animations have played.
							if (waitingToInteract)
							{
								canInteract = true;
								canShowHints = true;
							}
						}
					});
				});
			}
		});
	}
}

class SongMetadata
{
	public var song:Song = null;
	public var week:Int = 0;
	public var songCharacter:String = "";
	public var locked(default, null):Bool;

	public var color:FlxColor;

	public function new(song:Song, week:Int, songCharacter:String, color:FlxColor)
	{
		this.song = song;
		this.week = week;
		this.songCharacter = songCharacter;
		this.color = color;

		locked = (FlxG.save.data.locked.exists(this.song.id.toLowerCase())
			&& FlxG.save.data.locked.get(this.song.id.toLowerCase()) != 'unlocked')
			&& !FreeplayState.unlockAll;
	}
}


class FreeplayAlphabet extends Alphabet
{
	public var metadata:SongMetadata;

	public var onUpdate:Float->Void;
	public var onStepHit:Void->Void;
	public var onBeatHit:Void->Void;
	public var onMeasureHit:Void->Void;

	public function new(metadata:SongMetadata)
	{
		this.metadata = metadata;
		
		var displayString:String = metadata.song.songName;
		if (metadata.locked)
		{
			var words:Array<String> = metadata.song.songName.split(' ');
			var questionWords:Array<String> = [];
			var questionString = '';
			for (word in words)
			{
				var questionWord:String = '';
				for (letter in 0...word.length)
				{
					questionWord += switch (word.charAt(letter))
					{
						case ' ', '-': ' ';
						default: '?';
					}
				}
				questionWords.push(questionWord);
			}
			for (i in 0...questionWords.length)
			{
				questionString += questionWords[i] + (i != questionWords.length - 1 ? ' ' : '');
			}
			displayString = questionString;
		}

		super(0, 0, displayString);

		unlockY = true;
		isMenuItem = true;
		scrollFactor.set();
	}
}
