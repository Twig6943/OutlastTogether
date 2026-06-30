class OLTogetherLink extends TcpLink config(Multiplayer);

var OLTogetherController ControllerOwner;
var bool bIsConnected;
var config string IP;
var config string Port;

exec function SetServer(string NewIP, string NewPort)
{
    if (NewIP != "")
        IP = NewIP;
    if (NewPort != "")
        Port = NewPort;

    bIsConnected = false;
    `log("OLTogetherLink: Set server to " $ IP $ ":" $ Port);
    Resolve(IP);
}

exec function Reconnect()
{
    bIsConnected = false;
    `log("OLTogetherLink: Reconnecting to " $ IP $ ":" $ Port);
    Resolve(IP);
}

event PostBeginPlay()
{
    super.PostBeginPlay();
    LinkMode = MODE_Line;
    ReceiveMode = RMODE_Event;
    Resolve(IP);
}

event Resolved(IpAddr Addr)
{
    Addr.Port = int(Port);
    BindPort();
    Open(Addr);
}

event Opened()
{
    bIsConnected = true;
    `log("OLTogetherLink Connected to Server!");
    if (ControllerOwner != None)
    {
        ControllerOwner.ConnectionStatus = "Connected";
        ControllerOwner.AddChatLine("Connected to server " $ IP $ ":" $ Port);
    }
}

event Closed()
{
    bIsConnected = false;
    `log("OLTogetherLink Disconnected.");
    if (ControllerOwner != None)
    {
        ControllerOwner.ConnectionStatus = "Disconnected";
        ControllerOwner.AddChatLine("Disconnected from server.");
    }
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
