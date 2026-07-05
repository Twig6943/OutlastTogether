// OLTogetherVoiceListener.uc
// Local control channel for the desktop voice client (voice_client.py).
// The game listens on 127.0.0.1 and pushes the local player's world position
// and push-to-talk state so the voice client can gate its microphone and
// attenuate incoming audio by distance. Audio itself never travels over this
// link; it flows over UDP to the voice relay.

class OLTogetherVoiceListener extends TcpLink;

var int ListenPort;
var OLTogetherController ControllerOwner;
var OLTogetherVoiceListener ActiveChild;
var bool bClientConnected;

simulated event PostBeginPlay()
{
    super.PostBeginPlay();
    LinkMode    = MODE_Text;
    ReceiveMode = RMODE_Event;
}

function Init(OLTogetherController Controller, int Port)
{
    ControllerOwner = Controller;
    ListenPort      = Port;

    LinkMode    = MODE_Text;
    ReceiveMode = RMODE_Event;

    if (BindPort(ListenPort) > 0)
    {
        Listen();
        `log("OLTogetherVoiceListener: Listening on port " $ ListenPort);
    }
    else
    {
        `log("OLTogetherVoiceListener: FAILED to bind port " $ ListenPort $ " - is another app using it?");
    }
}

event Accepted()
{
    local OLTogetherVoiceListener Parent;
    
    // This event is called on the spawned child connection.
    Parent = OLTogetherVoiceListener(Owner);
    if (Parent != None)
    {
        Parent.ActiveChild = self;
        Parent.bClientConnected = true;
        `log("OLTogetherVoiceListener: Voice client connected.");
    }
}

event Closed()
{
    local OLTogetherVoiceListener Parent;
    
    // Called when the connection drops.
    Parent = OLTogetherVoiceListener(Owner);
    if (Parent != None && Parent.ActiveChild == self)
    {
        Parent.ActiveChild = None;
        Parent.bClientConnected = false;
        `log("OLTogetherVoiceListener: Voice client disconnected.");
    }
}

// Push a control line to the connected voice client. Called from the parent
// listener; forwards through the accepted child connection.
function SendControl(string Line)
{
    if (ActiveChild != None)
        ActiveChild.SendText(Line $ "\n");
}

event ReceivedText(string Text)
{
    // The voice client is push-only from the game's perspective; ignore any
    // inbound chatter but keep the handler so the link stays in event mode.
}

defaultproperties
{
    AcceptClass=class'OLTogetherVoiceListener'
    ListenPort=6700
}
