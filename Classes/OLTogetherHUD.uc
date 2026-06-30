class OLTogetherHUD extends OLHUD;

var array<string> ChatLines;
var array<string> Notifications;
var array<float> NotificationTimes;

function AddChatLine(string Msg)
{
    if (Msg == "")
        return;

    ChatLines.AddItem(Msg);
    while (ChatLines.Length > 6)
        ChatLines.RemoveItem(ChatLines[0]);
}

function AddNotification(string Msg)
{
    local float Now;

    if (Msg == "")
        return;

    Now = WorldInfo.TimeSeconds;
    Notifications.AddItem(Msg);
    NotificationTimes.AddItem(Now);
    while (Notifications.Length > 4)
    {
        Notifications.RemoveItem(Notifications[0]);
        NotificationTimes.RemoveItem(NotificationTimes[0]);
    }
}

Event OnLostFocusPause(Bool bEnable) {
        return;
}

event PostRender()
{
    local OLTogetherController PC;
    local float BoxWidth;
    local float BoxHeight;
    local float Padding;
    local float X;
    local float Y;
    local float LineHeight;
    local float Age;
    local float NameXL;
    local float NameYL;
    local float NameX;
    local float NameY;
    local float ViewWidth;
    local float ViewHeight;
    local float MaxBoxHeight;
    local int Alpha;
    local int I;
    local color White;
    local color Background;
    local color MessageColor;
    local string RoleName;
    local string Status;
    local string NameText;
    local vector NameScreen;
    local vector NameWorld;
    local int TotalLines;

    super.PostRender();

    PC = OLTogetherController(PlayerOwner);
    if (PC == None)
        return;

    White.R = 255;
    White.G = 255;
    White.B = 255;
    White.A = 255;
    Background.R = 0;
    Background.G = 0;
    Background.B = 0;
    Background.A = 180;
    ViewWidth = Canvas.SizeX;
    if (ViewWidth <= 0.0)
        ViewWidth = Canvas.ClipX;
    if (ViewWidth <= 0.0)
        ViewWidth = 1280.0;

    ViewHeight = Canvas.SizeY;
    if (ViewHeight <= 0.0)
        ViewHeight = Canvas.ClipY;
    if (ViewHeight <= 0.0)
        ViewHeight = 720.0;

    LineHeight = 18.0;
    Padding = 12.0;
    BoxWidth = 420.0;
    if (BoxWidth > ViewWidth - 32.0)
        BoxWidth = ViewWidth - 32.0;
    if (BoxWidth < 220.0)
        BoxWidth = 220.0;

    while (Notifications.Length > 0 && WorldInfo.TimeSeconds - NotificationTimes[0] > 5.0)
    {
        Notifications.RemoveItem(Notifications[0]);
        NotificationTimes.RemoveItem(NotificationTimes[0]);
    }

    TotalLines = 2 + Notifications.Length + ChatLines.Length + (PC.bChatMode ? 1 : 0);
    if (TotalLines < 4)
        TotalLines = 4;
    BoxHeight = Padding * 2.0 + TotalLines * LineHeight;
    MaxBoxHeight = ViewHeight - 32.0;
    if (BoxHeight > MaxBoxHeight)
        BoxHeight = MaxBoxHeight;

    X = 16.0;
    if (X + BoxWidth > ViewWidth - 16.0)
        X = ViewWidth - BoxWidth - 16.0;
    if (X < 16.0)
        X = 16.0;
    Y = ViewHeight - BoxHeight - 16.0;
    if (Y < 16.0)
        Y = 16.0;

    Canvas.SetDrawColor(Background.R, Background.G, Background.B, Background.A);
    Canvas.SetPos(X - 10.0, Y - 10.0);
    Canvas.DrawRect(BoxWidth + 20.0, BoxHeight + 20.0);

    Canvas.SetDrawColor(White.R, White.G, White.B, White.A);
    Canvas.SetPos(X, Y);
    Canvas.DrawText("OLTogether Chat", false, 0.95, 0.95);
    Y += LineHeight;

    Canvas.SetPos(X, Y);
    Canvas.DrawText("Role: " $ ((PC.MyRole == 0) ? "Host" : "Client"), false, 0.85, 0.85);
    Y += LineHeight;

    Canvas.SetPos(X, Y);
    Canvas.DrawText("Server: " $ PC.ServerIP $ ":" $ PC.ServerPort, false, 0.80, 0.80);
    Y += LineHeight;

    Canvas.SetPos(X, Y);
    Canvas.DrawText("Status: " $ (PC.ConnectionStatus != "" ? PC.ConnectionStatus : "Disconnected"), false, 0.80, 0.80);
    Y += LineHeight;

    Canvas.SetPos(X, Y);
    Canvas.DrawText("Ping: " $ (PC.PingMs > 0 ? string(PC.PingMs) $ " ms" : "n/a"), false, 0.80, 0.80);
    Y += LineHeight;

    if (PC.bChatMode)
    {
        Canvas.SetPos(X, Y);
        Canvas.DrawText("Chat: " $ PC.ChatInput $ (int(WorldInfo.TimeSeconds * 2.0) % 2 == 0 ? "_" : ""), false, 0.75, 0.75);
        Y += LineHeight;
    }

    if (PC.DummyPlayer != None && PC.DummyPlayerName != "")
    {
        NameText = PC.DummyPlayerName;
        NameWorld = PC.DummyPlayer.Location + vect(0.0, 0.0, 130.0);
        if (OLHero(PC.DummyPlayer) != None && OLHero(PC.DummyPlayer).HeadMesh != None)
        {
            NameWorld = OLHero(PC.DummyPlayer).HeadMesh.Bounds.Origin;
            if (NameWorld.Z < PC.DummyPlayer.Location.Z + 80.0)
                NameWorld.Z = PC.DummyPlayer.Location.Z + 135.0;
        }
        NameScreen = Canvas.Project(NameWorld);
        if (NameScreen.Z > 0.0)
        {
            Canvas.TextSize(NameText, NameXL, NameYL);
            NameX = NameScreen.X - (NameXL * 0.5);
            NameY = NameScreen.Y - NameYL - 6.0;

            Canvas.SetDrawColor(0, 0, 0, 180);
            Canvas.SetPos(NameX - 4.0, NameY - 2.0);
            Canvas.DrawRect(NameXL + 8.0, NameYL + 4.0);

            Canvas.SetDrawColor(White.R, White.G, White.B, White.A);
            Canvas.SetPos(NameX, NameY);
            Canvas.DrawText(NameText, false, 0.80, 0.80);
        }
    }

    if (Notifications.Length > 0)
    {
        Canvas.SetPos(X, Y);
        Canvas.DrawText("Notifications:", false, 0.80, 0.80);
        Y += LineHeight;
        for (I = 0; I < Notifications.Length; I++)
        {
            Age = WorldInfo.TimeSeconds - NotificationTimes[I];
            Alpha = 255;
            if (Age > 4.0)
                Alpha = int(255.0 - (Age - 4.0) * 255.0);
            if (Alpha < 0)
                Alpha = 0;

            MessageColor.R = White.R;
            MessageColor.G = White.G;
            MessageColor.B = White.B;
            MessageColor.A = Alpha;

            Canvas.SetDrawColor(MessageColor.R, MessageColor.G, MessageColor.B, MessageColor.A);
            Canvas.SetPos(X, Y);
            Canvas.DrawText(Notifications[I], false, 0.75, 0.75);
            Y += LineHeight;
        }
        Canvas.SetDrawColor(White.R, White.G, White.B, White.A);
    }

    if (ChatLines.Length > 0)
    {
        Canvas.SetPos(X, Y);
        Canvas.DrawText("Chat:", false, 0.80, 0.80);
        Y += LineHeight;
        for (I = 0; I < ChatLines.Length; I++)
        {
            Canvas.SetDrawColor(White.R, White.G, White.B, White.A);
            Canvas.SetPos(X, Y);
            Canvas.DrawText(ChatLines[I], false, 0.75, 0.75);
            Y += LineHeight;
        }
    }
}

DefaultProperties
{
}
