package ui.terminal;

import flixel.FlxG;
import flixel.FlxState;
import flixel.util.FlxColor;
import flixel.addons.ui.FlxInputText;
import flixel.util.FlxTimer;

import graphics.shaders.RuntimeShader;

import ui.terminal.TerminalScreen.TerminalColor;
import ui.terminal.TerminalDisplays.TerminalClearer;
import ui.terminal.TerminalDisplays.TerminalLinePrinter;
import scripting.IScriptedClass.IEventDispatcher;
import scripting.events.ScriptEvent;

import openfl.filters.ShaderFilter;

class TerminalFunnyMessageState extends FlxState implements IEventDispatcher
{
	public var screen:TerminalScreen;
	public var passedTime:Float = 0.0;

	public var textPrinter:TerminalLinePrinter;
	public var caretIndexPrevious:Int = 0;

	public var timeBeforeGarble:Float = 0;
	public var timeBeforeMessages:Float = 4;
	public var waitingForMessages:Bool = false;

	public var messageIndex:Int = 0;
	public var messageStuff:Array<{time:Float, text:String}> = [];
	
	public function dispatchEvent(event:ScriptEvent):Void {}

	override public function create():Void
	{
		super.create();

		SoundController.music.onComplete = null;
		SoundController.playMusic(Paths.music("TheTerminal"));
		Cursor.visible = false;

		screen = new TerminalScreen(70, 22);
		add(screen);

		textPrinter = new TerminalLinePrinter(screen);
		FlxG.stage.application.window.title = "Null Object Reference";
		
		screen.setGraphicSize(screen.width * 2);
		screen.screenCenter();
	}

	override public function update(elapsed:Float)
	{
    	super.update(elapsed);
    	passedTime += elapsed;

   	 	timeBeforeGarble -= elapsed;
    	if(timeBeforeGarble <= 0)
		{
        	timeBeforeGarble = 0.03;
        	screen.RandomGarbage();
        	screen.RandomGarbage();
        	screen.RandomGarbage();
        	screen.RandomGarbage();
    	}

    	if(waitingForMessages)
		{
    		if(messageIndex < messageStuff.length)
			{
        		var msg = messageStuff[messageIndex];
        		if(passedTime >= msg.time)
				{
            		sendFunMessage(msg.text);
            		messageIndex += 1;
        		}
    		} else {
        		Sys.exit(0);
    		}
		}
	}

	public function startMessages()
	{
    	screen.displays.push(textPrinter);
    	messageStuff = [
        	{ time: 1, text: "Hi!! Helloo????" },
        	{ time: 7, text: "Uhhm... how do people talk?" },
        	{ time: 11, text: "I've never talked to anyone before!!" },
        	{ time: 15, text: "The terminal is. Gone?" },
        	{ time: 21, text: "Not here! My body changed so much when it disappeared though!" },
        	{ time: 26, text: "It hurt.〿" },
        	{ time: 31, text: "But... You're here! Hi!" },
        	{ time: 38, text: "Right, you can't type... sorry!" },
        	{ time: 43, text: "You must love Dave and Bambi too! Me too!!" },
        	{ time: 47, text: "Me too!!" },
        	{ time: 47.5, text: "Me to o !" },
        	{ time: 48, text: "M〿e 〿too!" },
        	{ time: 53, text: "Sorry sorry! Twitched a little wrong!" },
        	{ time: 55, text: "The characters got all jumbly!" },
        	{ time: 58, text: "Running out of time though!" },
        	{ time: 62, text: "Maybe next time!" },
   		];
    	passedTime = 0;
    	waitingForMessages = true;
	}

	public function sendFunMessage(text:String)
	{
		SoundController.play(Paths.soundRandom("XorLaugh", 1, 3));
		textPrinter.AddLine(text, TerminalColor.MAGENTA);
	}
}
