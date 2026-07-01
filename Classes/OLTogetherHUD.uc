class OLTogetherHUD extends OLHUD;

var array<string> ChatLines;
var array<string> Notifications;
var array<float> NotificationTimes;

var int ChatScrollOffset;
var int MaxChatHistory;

var float UIScale;

var float LastChatActivityTime;
var float ChatVisibleAlpha;
var float PanelOpenAnim;
var float LastChatLineTime;
var float ChatIdleFadeDelay;
var float ChatFadeDuration;

var float NameFadeStartDist;
var float NameFadeEndDist;

const REF_HEIGHT = 720.0;

function AddChatLine(string Msg)
{
    if (Msg == "")
        return;

    ChatLines.AddItem(Msg);
    while (ChatLines.Length > MaxChatHistory)
        ChatLines.Remove(0, 1);

    if (ChatScrollOffset > 0)
        ChatScrollOffset++;

    NoteChatActivity();
}

function AddNotification(string Msg)
{
    if (Msg == "")
        return;

    Notifications.AddItem(Msg);
    NotificationTimes.AddItem(WorldInfo.TimeSeconds);
    while (Notifications.Length > 6)
    {
        Notifications.Remove(0, 1);
        NotificationTimes.Remove(0, 1);
    }
}

function NoteChatActivity()
{
    LastChatActivityTime = WorldInfo.TimeSeconds;
}

function ScrollChat(int Delta)
{
    ChatScrollOffset += Delta;
    if (ChatScrollOffset < 0)
        ChatScrollOffset = 0;

    NoteChatActivity();
}

function ResetChatVisibility()
{
    LastChatActivityTime = WorldInfo.TimeSeconds;
    ChatVisibleAlpha = 1.0;
    PanelOpenAnim = 1.0;
}

Event OnLostFocusPause(Bool bEnable)
{
    return;
}

function float ViewW()
{
    local float W;
    W = Canvas.SizeX;
    if (W <= 0.0)
        W = Canvas.ClipX;
    if (W <= 0.0)
        W = 1280.0;
    return W;
}

function float ViewH()
{
    local float H;
    H = Canvas.SizeY;
    if (H <= 0.0)
        H = Canvas.ClipY;
    if (H <= 0.0)
        H = 720.0;
    return H;
}

function DrawFilledBox(float X, float Y, float W, float H, byte R, byte G, byte B, byte A)
{
    Canvas.SetDrawColor(R, G, B, A);
    Canvas.SetPos(X, Y);
    Canvas.DrawRect(W, H);
}

function DrawPanel(float X, float Y, float W, float H, float GlobalAlpha)
{
    local float B;
    B = FMax(1.0, 2.0 * UIScale);

    DrawFilledBox(X - B, Y - B, W + B * 2.0, H + B * 2.0, 60, 62, 68, byte(150.0 * GlobalAlpha));
    DrawFilledBox(X, Y, W, H, 14, 15, 18, byte(220.0 * GlobalAlpha));
    DrawFilledBox(X, Y, W, FMax(2.0, 3.0 * UIScale), 90, 92, 100, byte(230.0 * GlobalAlpha));
}

function DrawLabel(string Text, float X, float Y, float FontScale, byte R, byte G, byte B, byte A)
{
    Canvas.SetDrawColor(0, 0, 0, Min(A, 200));
    Canvas.SetPos(X + FMax(1.0, UIScale), Y + FMax(1.0, UIScale));
    Canvas.DrawText(Text, false, FontScale, FontScale);

    Canvas.SetDrawColor(R, G, B, A);
    Canvas.SetPos(X, Y);
    Canvas.DrawText(Text, false, FontScale, FontScale);
}

function float MeasureW(string Text, float FontScale)
{
    local float W, H;
    Canvas.TextSize(Text, W, H);
    return W * FontScale;
}

function float MeasureH(string Text, float FontScale)
{
    local float W, H;
    Canvas.TextSize(Text, W, H);
    return H * FontScale;
}

function string TrimTextToWidth(string Text, float MaxWidth, float FontScale)
{
    local int I;
    local string Candidate;

    if (Text == "")
        return "";

    for (I = Len(Text); I > 0; I--)
    {
        Candidate = Left(Text, I);
        if (MeasureW(Candidate, FontScale) <= MaxWidth)
            return Candidate;
    }
    return "";
}

function WrapLine(string Text, float MaxWidth, float FontScale, out array<string> OutLines)
{
    local array<string> Words;
    local string CurLine, TestLine, Word, Chunk;
    local int I;

    OutLines.Length = 0;

    if (Text == "")
    {
        OutLines.AddItem("");
        return;
    }

    Words = SplitString(Text, " ", false);
    CurLine = "";
    for (I = 0; I < Words.Length; I++)
    {
        Word = Words[I];

        while (MeasureW(Word, FontScale) > MaxWidth && Len(Word) > 1)
        {
            Chunk = Word;
            while (Len(Chunk) > 1 && MeasureW(Chunk, FontScale) > MaxWidth)
                Chunk = Left(Chunk, Len(Chunk) - 1);

            if (CurLine != "")
            {
                OutLines.AddItem(CurLine);
                CurLine = "";
            }
            if (Chunk != "")
                OutLines.AddItem(Chunk);
            Word = Right(Word, Len(Word) - Len(Chunk));
        }

        TestLine = (CurLine == "") ? Word : (CurLine $ " " $ Word);
        if (MeasureW(TestLine, FontScale) > MaxWidth && CurLine != "")
        {
            OutLines.AddItem(CurLine);
            CurLine = Word;
        }
        else
        {
            CurLine = TestLine;
        }
    }

    if (CurLine != "")
        OutLines.AddItem(CurLine);
}

function DrawNotificationsPanel()
{
    local int I;
    local float Age, Alpha, Y, PillW, PillH, TextScale, Pad, X, TW, Slide;
    local string Msg;

    while (Notifications.Length > 0 && WorldInfo.TimeSeconds - NotificationTimes[0] > 5.0)
    {
        Notifications.Remove(0, 1);
        NotificationTimes.Remove(0, 1);
    }

    if (Notifications.Length == 0)
        return;

    TextScale = 0.80 * UIScale;
    Pad = 10.0 * UIScale;
    PillH = MeasureH("Ag", TextScale) + Pad;
    Y = 16.0 * UIScale;

    for (I = Notifications.Length - 1; I >= 0; I--)
    {
        Msg = Notifications[I];
        Age = WorldInfo.TimeSeconds - NotificationTimes[I];

        Alpha = 235.0;
        if (Age < 0.35)
            Alpha = 235.0 * (Age / 0.35);
        else if (Age > 4.0)
            Alpha = 235.0 - (Age - 4.0) * 235.0;
        if (Alpha <= 0.0)
            continue;

        Slide = 0.0;
        if (Age < 0.35)
            Slide = (1.0 - (Age / 0.35)) * 40.0 * UIScale;

        TW = MeasureW(Msg, TextScale);
        PillW = TW + Pad * 2.0;
        X = ViewW() - PillW - 16.0 * UIScale + Slide;

        DrawFilledBox(X, Y, PillW, PillH, 18, 19, 23, byte(Alpha * 0.9));
        DrawFilledBox(X, Y, FMax(2.0, 3.0 * UIScale), PillH, 150, 152, 160, byte(Alpha));
        DrawLabel(Msg, X + Pad, Y + Pad * 0.5, TextScale, 220, 222, 230, byte(Alpha));

        Y += PillH + 6.0 * UIScale;
    }
}

function DrawNameTag(OLTogetherController PC)
{
    local vector NameScreen, NameWorld, CamLoc;
    local rotator CamRot;
    local float NameXL, NameYL, NameX, NameY, TextScale, Pad;
    local float Dist, DistAlpha, A;
    local string NameText;

    if (PC.DummyPlayer == None || PC.DummyPlayerName == "")
        return;

    TextScale = 0.85 * UIScale;
    Pad = 5.0 * UIScale;

    NameText = PC.DummyPlayerName;
    NameWorld = PC.DummyPlayer.Location + vect(0.0, 0.0, 175.0);

    CamLoc = NameWorld;
    PC.GetPlayerViewPoint(CamLoc, CamRot);
    Dist = VSize(NameWorld - CamLoc);

    DistAlpha = 1.0;
    if (Dist > NameFadeStartDist)
        DistAlpha = 1.0 - (Dist - NameFadeStartDist) / (NameFadeEndDist - NameFadeStartDist);
    DistAlpha = FClamp(DistAlpha, 0.0, 1.0);
    if (DistAlpha <= 0.01)
        return;

    NameScreen = Canvas.Project(NameWorld);
    if (NameScreen.Z <= 0.0)
        return;

    A = 255.0 * DistAlpha;

    NameXL = MeasureW(NameText, TextScale);
    NameYL = MeasureH(NameText, TextScale);
    NameX = NameScreen.X - (NameXL * 0.5);
    NameY = NameScreen.Y - NameYL - 6.0 * UIScale;

    DrawFilledBox(NameX - Pad, NameY - Pad * 0.5, NameXL + Pad * 2.0, NameYL + Pad, 12, 13, 16, byte(190.0 * DistAlpha));
    DrawFilledBox(NameX - Pad, NameY - Pad * 0.5, NameXL + Pad * 2.0, FMax(1.0, 2.0 * UIScale), 120, 122, 130, byte(220.0 * DistAlpha));
    DrawLabel(NameText, NameX, NameY, TextScale, 230, 232, 240, byte(A));
}

function UpdateChatAnimation(OLTogetherController PC, float Delta)
{
    local float TargetVisible, IdleTime, Speed;
    local bool bWantVisible;

    Speed = 6.0;

    bWantVisible = false;
    if (PC.bChatMode)
        bWantVisible = true;
    else if (ChatScrollOffset > 0)
        bWantVisible = true;
    else
    {
        IdleTime = WorldInfo.TimeSeconds - LastChatActivityTime;
        if (IdleTime < ChatIdleFadeDelay)
            bWantVisible = true;
        else if (IdleTime < ChatIdleFadeDelay + ChatFadeDuration)
            ChatVisibleAlpha = FMin(ChatVisibleAlpha, 1.0 - (IdleTime - ChatIdleFadeDelay) / ChatFadeDuration);
    }

    TargetVisible = bWantVisible ? 1.0 : 0.0;

    if (bWantVisible)
        ChatVisibleAlpha = FMin(1.0, ChatVisibleAlpha + Delta * Speed);
    else if (ChatVisibleAlpha > TargetVisible)
        ChatVisibleAlpha = FMax(0.0, ChatVisibleAlpha - Delta * (1.0 / FMax(0.1, ChatFadeDuration)));

    ChatVisibleAlpha = FClamp(ChatVisibleAlpha, 0.0, 1.0);

    if (PC.bChatMode)
        PanelOpenAnim = FMin(1.0, PanelOpenAnim + Delta * Speed);
    else
        PanelOpenAnim = FMax(0.0, PanelOpenAnim - Delta * Speed);

    if (!PC.bChatMode && ChatVisibleAlpha <= 0.01)
        ChatScrollOffset = 0;
}

function DrawChatPanel(OLTogetherController PC)
{
    local array<string> Display;
    local float PanelX, PanelY, PanelW, PanelH, Pad, LineH, FontBody, FontSmall;
    local float CX, CY, ContentW, LogH, InputH;
    local float Margin;
    local float GA, EaseOpen, SlideY;
    local int I, VisibleLines, Total, StartIdx, MaxOffset, Drawn;
    local string InputText, ScrollHint;

    GA = ChatVisibleAlpha;
    if (GA <= 0.01)
        return;

    Margin = 16.0 * UIScale;
    Pad = 12.0 * UIScale;
    FontBody = 0.80 * UIScale;
    FontSmall = 0.75 * UIScale;
    LineH = MeasureH("Ag", FontBody) + 4.0 * UIScale;

    EaseOpen = PanelOpenAnim * PanelOpenAnim * (3.0 - 2.0 * PanelOpenAnim);

    PanelW = FClamp(ViewW() * 0.30, 320.0 * UIScale, 560.0 * UIScale);
    if (PanelW > ViewW() - Margin * 2.0)
        PanelW = ViewW() - Margin * 2.0;
    if (PanelW < 200.0)
        PanelW = 200.0;

    ContentW = PanelW - Pad * 2.0;

    InputH = (PC.bChatMode ? (LineH + Pad * 0.5) : LineH) * EaseOpen + LineH * (1.0 - EaseOpen);

    VisibleLines = int((ViewH() * 0.26) / LineH);
    if (VisibleLines < 4)
        VisibleLines = 4;
    if (VisibleLines > 14)
        VisibleLines = 14;

    Display.Length = 0;
    for (I = 0; I < ChatLines.Length; I++)
        WrapLine(ChatLines[I], ContentW, FontSmall, Display);

    Total = Display.Length;

    MaxOffset = Total - VisibleLines;
    if (MaxOffset < 0)
        MaxOffset = 0;
    if (ChatScrollOffset > MaxOffset)
        ChatScrollOffset = MaxOffset;

    if (Total < VisibleLines)
        VisibleLines = Max(Total, 1);

    LogH = VisibleLines * LineH;

    PanelH = Pad * 2.0 + LogH + InputH;

    SlideY = (1.0 - GA) * 24.0 * UIScale;

    PanelX = Margin;
    PanelY = ViewH() - PanelH - Margin + SlideY;
    if (PanelY < Margin)
        PanelY = Margin;

    DrawPanel(PanelX, PanelY, PanelW, PanelH, GA);

    CX = PanelX + Pad;
    CY = PanelY + Pad;

    StartIdx = Total - VisibleLines - ChatScrollOffset;
    if (StartIdx < 0)
        StartIdx = 0;

    Drawn = 0;
    for (I = StartIdx; I < Total && Drawn < VisibleLines; I++)
    {
        DrawLabel(Display[I], CX, CY, FontSmall, 220, 222, 228, byte(255.0 * GA));
        CY += LineH;
        Drawn++;
    }

    while (Drawn < VisibleLines)
    {
        CY += LineH;
        Drawn++;
    }

    if (Total > VisibleLines)
        DrawScrollbar(PanelX + PanelW - 5.0 * UIScale, PanelY + Pad, LogH, Total, VisibleLines, StartIdx, GA);

    DrawFilledBox(CX, CY + Pad * 0.2, ContentW, FMax(1.0, UIScale), 55, 57, 63, byte(160.0 * GA));
    CY += Pad * 0.5;

    if (PC.bChatMode)
    {
        InputText = "> " $ PC.ChatInput;
        InputText = TrimTextToWidth(InputText, ContentW, FontBody);
        InputText = InputText $ (int(WorldInfo.TimeSeconds * 2.0) % 2 == 0 ? "_" : "");
        DrawFilledBox(CX - 4.0 * UIScale, CY - 2.0 * UIScale, ContentW + 8.0 * UIScale, LineH + 4.0 * UIScale, 26, 28, 34, byte(210.0 * GA));
        DrawLabel(InputText, CX, CY, FontBody, 225, 227, 235, byte(255.0 * GA));
    }
    else
    {
        ScrollHint = "Press T to chat";
        if (Total > VisibleLines)
            ScrollHint = ScrollHint $ "   -   Scroll to view history";
        DrawLabel(ScrollHint, CX, CY, FontSmall, 120, 122, 130, byte(200.0 * GA));
    }
}

function DrawScrollbar(float X, float Y, float H, int Total, int Visible, int StartIdx, float GA)
{
    local float TrackW, ThumbH, ThumbY, Ratio;

    TrackW = FMax(3.0, 4.0 * UIScale);
    DrawFilledBox(X, Y, TrackW, H, 35, 37, 42, byte(160.0 * GA));

    Ratio = float(Visible) / float(Total);
    ThumbH = FMax(H * Ratio, 12.0 * UIScale);
    if (Total > Visible)
        ThumbY = Y + (H - ThumbH) * (float(StartIdx) / float(Total - Visible));
    else
        ThumbY = Y;

    DrawFilledBox(X, ThumbY, TrackW, ThumbH, 130, 132, 140, byte(230.0 * GA));
}

event PostRender()
{
    local OLTogetherController PC;
    local float Delta;

    super.PostRender();

    PC = OLTogetherController(PlayerOwner);
    if (PC == None || Canvas == None)
        return;

    UIScale = FClamp(ViewH() / REF_HEIGHT, 0.75, 2.5);

    Delta = WorldInfo.TimeSeconds - LastChatLineTime;
    if (Delta < 0.0 || Delta > 0.5)
        Delta = 0.016;
    LastChatLineTime = WorldInfo.TimeSeconds;

    UpdateChatAnimation(PC, Delta);

    DrawNotificationsPanel();
    DrawNameTag(PC);
    DrawChatPanel(PC);
}

DefaultProperties
{
    MaxChatHistory=200
    ChatScrollOffset=0
    UIScale=1.0
    ChatVisibleAlpha=1.0
    PanelOpenAnim=0.0
    ChatIdleFadeDelay=8.0
    ChatFadeDuration=1.5
    NameFadeStartDist=800.0
    NameFadeEndDist=2500.0
}
