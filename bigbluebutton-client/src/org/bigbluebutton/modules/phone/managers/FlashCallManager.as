 package org.bigbluebutton.modules.phone.managers
{
  import com.asfusion.mate.events.Dispatcher;
  
  import flash.external.ExternalInterface;
  import flash.media.Microphone;
  
  import org.bigbluebutton.core.UsersUtil;
  import org.bigbluebutton.core.model.MeetingModel;
  import org.bigbluebutton.modules.phone.PhoneOptions;
  import org.bigbluebutton.modules.phone.events.FlashCallConnectedEvent;
  import org.bigbluebutton.modules.phone.events.FlashCallDisconnectedEvent;
  import org.bigbluebutton.modules.phone.events.FlashEchoTestHasAudioEvent;
  import org.bigbluebutton.modules.phone.events.FlashEchoTestNoAudioEvent;
  import org.bigbluebutton.modules.phone.events.FlashEchoTestStartedEvent;
  import org.bigbluebutton.modules.phone.events.FlashEchoTestStoppedEvent;
  import org.bigbluebutton.modules.phone.events.FlashErrorEvent;
  import org.bigbluebutton.modules.phone.events.FlashJoinVoiceConferenceCommand;
  import org.bigbluebutton.modules.phone.events.FlashJoinedVoiceConferenceEvent;
  import org.bigbluebutton.modules.phone.events.FlashLeaveVoiceConferenceCommand;
  import org.bigbluebutton.modules.phone.events.FlashLeftVoiceConferenceEvent;
  import org.bigbluebutton.modules.phone.events.FlashMicSettingsEvent;
  import org.bigbluebutton.modules.phone.events.FlashStartEchoTestCommand;
  import org.bigbluebutton.modules.phone.events.FlashStopEchoTestCommand;
  import org.bigbluebutton.modules.phone.events.FlashVoiceConnectionStatusEvent;
  import org.bigbluebutton.modules.phone.events.JoinVoiceConferenceCommand;
  import org.bigbluebutton.modules.phone.events.LeaveVoiceConferenceCommand;

  public class FlashCallManager
  {
    private static const LOG:String = "Phone::FlashCallManager - ";
    
    private static const INITED:String = "initialized state";
    private static const CONNECTED:String = "connected state";
    private static const DO_ECHO_TEST:String = "do echo test state";
    private static const CALLING_INTO_ECHO_TEST:String = "calling into echo test state";
    private static const IN_ECHO_TEST:String = "in echo test state";
    private static const JOIN_VOICE_CONFERENCE:String = "join voice conference state";
    private static const CALLING_INTO_CONFERENCE:String = "calling into conference state";
    private static const IN_CONFERENCE:String = "in conference state";
    
    private var state:String = INITED;
    
    private var options:PhoneOptions;
    private var echoTestDone:Boolean = false;
    private var doingEchoTest:Boolean = false;
    private var micNames:Array = new Array();
    private var dispatcher:Dispatcher = new Dispatcher();
    private var connectionManager:ConnectionManager;
    private var streamManager:StreamManager;
    
    private var useMicIndex:int = -1;
    private var useMicName:String = "unknown";
    
    public function FlashCallManager() {
      micNames = Microphone.names;
      connectionManager = new ConnectionManager();
      streamManager = new StreamManager(connectionManager);
      initConnectionManager();
    }
        
    private function initConnectionManager():void {
      var options:PhoneOptions = new PhoneOptions();
      var uid:String = String(Math.floor(new Date().getTime()));
      var uname:String = encodeURIComponent(UsersUtil.getMyExternalUserID() + "-bbbID-" + UsersUtil.getMyUsername()); 
      connectionManager.setup(uid, UsersUtil.getMyUserID(), uname , UsersUtil.getInternalMeetingID(), options.uri);
    }
    
    private function isWebRtcSupported():Boolean {
      return (ExternalInterface.available && ExternalInterface.call("isWebrtcCapable"));
    }

    private function isConnected():Boolean {
      return connectionManager.isConnected();
    }
    
    private function connect():void {
        connectionManager.connect();
    }
        
    private function doEchoTest():void {
      dispatcher.dispatchEvent(new FlashMicSettingsEvent(micNames));
    }
        
    private function startCall():void {
      if (options.skipCheck || echoTestDone) {
        trace(LOG + "Calling into voice conference. skipCheck=[" + options.skipCheck + "] echoTestDone=[" + echoTestDone + "]");
        callIntoVoiceConference();
      } else {
        trace(LOG + "Performing echo test. echoTestDone=[" + echoTestDone + "]");
        doEchoTest();
      }      
    }
    
    private function autoJoin():void {
      if (options.autoJoin) {
        trace(LOG + "Auto joining into conference");
        startCall();
      }      
    }
       
    private function callIntoVoiceConference():void {
      if (isConnected()) {
        var destination:String = MeetingModel.getInstance().meeting.voiceConference;
        if (destination != null && destination != "") {
          trace(LOG + "Calling into voice conference =[" + destination + "]");
          state = CALLING_INTO_CONFERENCE;
          connectionManager.doCall(destination);             
        } else {
          trace(LOG + "Invalid voice conference [" + destination + "]");
          dispatcher.dispatchEvent(new FlashErrorEvent(FlashErrorEvent.INVALID_VOICE_DESTINATION));
        }
      } else {
        trace(LOG + "Need to connect before we can join the voice conference.");
        state = JOIN_VOICE_CONFERENCE;
        connect();
      }
    }
    
    private function callIntoEchoTest():void {
      if (isConnected()) {
        var destination:String = options.echoTestApp;
        if (destination != null && destination != "") {
          trace(LOG + "Calling into echo test =[" + destination + "]");
          state = CALLING_INTO_ECHO_TEST;
          connectionManager.doCall(destination);
        } else {
          trace(LOG + "Invalid echo test destination [" + destination + "]");
          dispatcher.dispatchEvent(new FlashErrorEvent(FlashErrorEvent.INVALID_ECHO_TEST_DESTINATION));
        }
      } else {
        trace(LOG + "Need to connect before we can call into echo test.");
        state = DO_ECHO_TEST;
        connect();
      }
    }
    
    private function printMics():void {
      for (var i:int = 0; i < micNames.length; i++) {
        trace(LOG + "*** MIC [" + i + "] = [" + micNames[i] + "]");
      }
    }
    
    public function userRequestedHangup():void {
      streamManager.stopStreams();
      connectionManager.disconnect(true);
    }
    
    public function initialize():void {      
      printMics();
      options = new PhoneOptions();
      if (options.useWebrtcIfAvailable && !isWebRtcSupported()) {
          autoJoin();
      } else {
        autoJoin();
      }
    }
    
    private function hangup():void {
      connectionManager.doHangUp();
    }
    
    public function handleFlashStartEchoTestCommand(event:FlashStartEchoTestCommand):void {
      trace(LOG + "handling FlashStartEchoTestCommand. mic index=[" + event.micIndex + "] name=[" + event.micName + "]");
      useMicIndex = event.micIndex;
      useMicName = event.micName;
      trace(LOG + "Setting up preferred micriphone.");
      streamManager.usePreferredMic(event.micIndex, event.micName);
      callIntoEchoTest();
    }
    
    public function handleFlashStopEchoTestCommand(event:FlashStopEchoTestCommand):void {
      hangup();
    }
    
    public function handleFlashEchoTestHasAudioEvent(event:FlashEchoTestHasAudioEvent):void {
      if (state == IN_ECHO_TEST) {
        hangup();
      }
      echoTestDone = true;
      callIntoVoiceConference();
    }
    
    public function handleFlashEchoTestNoAudioEvent(event:FlashEchoTestNoAudioEvent):void {
      if (state == IN_ECHO_TEST) {
        hangup();
      }
      echoTestDone = false;      
    }
    
    public function handleFlashCallConnectedEvent(event:FlashCallConnectedEvent):void {
      
      switch (state) {
        case CALLING_INTO_CONFERENCE:
          trace(LOG + "Successfully joined the voice conference.");
          state = IN_CONFERENCE;
          dispatcher.dispatchEvent(new FlashJoinedVoiceConferenceEvent());
          streamManager.callConnected(event.playStreamName, event.publishStreamName, event.codec);
          break;
        case CALLING_INTO_ECHO_TEST:
          state = IN_ECHO_TEST;
          trace(LOG + "Successfully call into the echo test application.  [" + event.publishStreamName + "] : [" + event.playStreamName + "] : [" + event.codec + "]");
          streamManager.callConnected(event.playStreamName, event.publishStreamName, event.codec);
          
          trace(LOG + "Successfully call into the echo test application.");
          dispatcher.dispatchEvent(new FlashEchoTestStartedEvent());
          break;
      }      
    }
    
    public function handleFlashCallDisconnectedEvent(event:FlashCallDisconnectedEvent):void {
      switch (state) {
        case IN_CONFERENCE:
          state = INITED;
          dispatcher.dispatchEvent(new FlashLeftVoiceConferenceEvent());
          break;
        case IN_ECHO_TEST:
          state = INITED;
          dispatcher.dispatchEvent(new FlashEchoTestStoppedEvent());
          break;
      }
    }
    
    public function handleJoinVoiceConferenceCommand(event:JoinVoiceConferenceCommand):void {
      startCall();
    }
    
    public function handleLeaveVoiceConferenceCommand(event:LeaveVoiceConferenceCommand):void {
      hangup();
    }
    
    public function handleFlashVoiceConnectionStatusEvent(event:FlashVoiceConnectionStatusEvent):void {
      trace(LOG + "Connection status event. status=[" + event.status + "]");
      if (event.status == FlashVoiceConnectionStatusEvent.CONNECTED) {
        switch (state) {
          case JOIN_VOICE_CONFERENCE:
            callIntoVoiceConference();
            break;
          case DO_ECHO_TEST:
            callIntoEchoTest();
            break;
        }
      }
    }
  }
}