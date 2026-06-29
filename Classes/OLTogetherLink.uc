class OLTogetherLink extends TcpLink
config(Multiplayer)

var OLTogetherController ControllerOwner;
var bool bIsConnected;
var config string IP;
var config string Port;

event PostBeginPlay()
{
    super.PostBeginPlay();
    LinkMode = MODE_Line;
    ReceiveMode = RMODE_Event;
    Resolve(IP);
}

event Resolved(IpAddr Addr)
{
    Addr.Port = Port;
    BindPort();
    Open(Addr);
}

event Opened()
{
    bIsConnected = true;
    `log("OLTogetherLink Connected to Server!");
}

event Closed()
{
    bIsConnected = false;
    `log("OLTogetherLink Disconnected.");
}

event ReceivedLine(string Line)
{
    if (ControllerOwner != None)
    {
        ControllerOwner.OnReceiveData(Line);
    }
}

DefaultProperties
{
    IP="127.0.0.1"
    Port="7777"
}
