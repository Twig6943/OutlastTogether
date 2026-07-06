// OLTogetherVoiceListener.uc
// Local control channel for the desktop voice client (OutlastTogether.py).
// Pushes full 3D world position + camera yaw so the voice client can apply
// proper inverse-square distance attenuation AND stereo spatial panning.
// Audio itself never travels over this link; it flows over UDP to the voice relay.

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
    
    Parent = OLTogetherVoiceListener(Owner);
    if (Parent != None && Parent.ActiveChild == self)
    {
        Parent.ActiveChild = None;
        Parent.bClientConnected = false;
        `log("OLTogetherVoiceListener: Voice client disconnected.");
    }
}

// Push a control line to the connected voice client.
// Called from the parent listener; forwards through the accepted child connection.
function SendControl(string Line)
{
    if (ActiveChild != None)
        ActiveChild.SendText(Line $ "\n");
}

event ReceivedText(string Text)
{
    // Voice client is push-only from the game's perspective.
}

defaultproperties
{
    AcceptClass=class'OLTogetherVoiceListener'
    ListenPort=6700
}
