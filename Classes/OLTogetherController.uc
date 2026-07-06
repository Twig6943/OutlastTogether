class OLTogetherController extends OLPlayerController;
var OLTogetherLink ConnectionLink;
var OLTogetherVoiceListener VoiceListener;
var float LastVoiceControlSendTime;
var bool bLastSentTalking;
var Pawn RemotePawn;
var int PlayerRole;
var float LastStateSendTime;
var float LastPingSendTime;
var int RoundTripPingMs;
var string ServerAddress, ServerPort, ConnectionState, RoomAuthToken;
var string VoiceHost, VoicePort;
var string LocalPlayerName, RemotePlayerName, LastSentPlayerName;
var bool bPlayerNameAnnounced;
var float LastPlayerNameSendTime;
var bool bChatMode;
var string ChatText;
var OLTogetherSettings Settings;
var bool bSettingsMenuOpen;
var bool bSpeedrunMode, bSpeedrunReady, bSpeedrunCountdownActive, bPeerIsReady;
var bool bSpeedrunSequenceActive, bSpeedrunControlsLocked, bHideLocalPawnDuringSpeedrun;
var float SpeedrunStartTime, SpeedrunFinishTime, SpeedrunSequenceStartTime, SpeedrunStartDelay;
var float SpeedrunCountdownStartTime, SpeedrunCountdownElapsed;
var int SpeedrunCountdownValue;
var vector SpeedrunLockLocation;
var rotator SpeedrunLockRotation;
var float SpeedrunOverlayAlpha, SpeedrunOverlayPulse;
var bool bInStartNewGame, bStartedAtCheckpoint;
var float DisconnectedSince, LastReconnectAttempt;
var bool bWasConnected;
var vector LastReceivedLoc, LastReceivedVel;
var rotator LastReceivedRot;
var bool bHasReceivedData;
var bool bLastRemoteCamcorder;
var int LastRemoteCamcorderState;
var name LastMovementAnim;
var float InterpSpeed;
var int LastLocomotionMode, LastDoorInputDir, LastLeanInputDir, RemoteHealth;
var bool bRemotePawnCrouched, bLocalRunning, bRemoteTalking, bMicTransmitting;
var float AnimLockEndTime;
var name LastCrouchLeanAnim;
var config name BindSpeedrunReady, BindForceStart, BindPushToTalk, BindOpenSettings;
function string ParseUrlFallback(string Url, string Key, string Parsed)
{
    if (Parsed == "")
        return GetUrlOptionValue(Url, Key);
    return Parsed;
}
function string GetUrlOptionValue(string Url, string OptionName)
{
    local array<string> Segments;
    local string KeyPrefix;
    local int Idx, FoundAt;
    KeyPrefix = OptionName $ "=";
    Segments = SplitString(Url, "?", true);
    for (Idx = 0; Idx < Segments.Length; Idx++)
    {
        FoundAt = InStr(Segments[Idx], KeyPrefix);
        if (FoundAt == 0)
            return Right(Segments[Idx], Len(Segments[Idx]) - Len(KeyPrefix));
    }
    return "";
}
function string ResolveUrl(string Url, string Key)
{
    local string V;
    V = WorldInfo.Game.ParseOption(Url, Key);
    if (V == "")
        V = GetUrlOptionValue(Url, Key);
    return V;
}
event PostBeginPlay()
{
    local string Url, V, PortStr;
    local int ControlPort;
    super.PostBeginPlay();
    Url = WorldInfo.GetLocalURL();
    V = ResolveUrl(Url, "Role");
    PlayerRole = int(V);
    ServerAddress = "127.0.0.1";
    ServerPort = "7777";
    LocalPlayerName = "";
    V = ResolveUrl(Url, "ServerIP");
    if (V != "") ServerAddress = V;
    V = ResolveUrl(Url, "ServerPort");
    if (V != "") ServerPort = V;
    V = ResolveUrl(Url, "PlayerName");
    if (V != "") LocalPlayerName = V;
    if (LocalPlayerName == "")
        LocalPlayerName = "Player" @ (PlayerRole == 0 ? "Host" : "Client");
    bSpeedrunMode = (ResolveUrl(Url, "SpeedrunMode") == "1");
    V = ResolveUrl(Url, "PushToTalk");
    if (V == "1")
        Settings.bPushToTalk = true;
    RoomAuthToken = ResolveUrl(Url, "RoomToken");
    VoiceHost = ResolveUrl(Url, "VoiceHost");
    VoicePort = ResolveUrl(Url, "VoicePort");
    ConnectionState = "Connecting...";
    LastPingSendTime = 0.0;
    LastReconnectAttempt = -999.0;
    RoundTripPingMs = 0;
    bPlayerNameAnnounced = false;
    LastSentPlayerName = "";
    LastPlayerNameSendTime = -999.0;
    bChatMode = false;
    ChatText = "";
    LastLocomotionMode = 0;
    LastDoorInputDir = 0;
    Settings = new(self) class'OLTogetherSettings';
    if (Settings != None)
    {
        Settings.SeedDefaults();
        ApplySettings();
    }
    bMicTransmitting = (Settings == None || !Settings.bPushToTalk);
    ConnectionLink = Spawn(class'OLTogetherLink', self);
    if (ConnectionLink != None)
    {
        ConnectionLink.ControllerOwner = self;
        ConnectionLink.IP = ServerAddress;
        ConnectionLink.Port = ServerPort;
        ConnectionLink.SetServer(ServerAddress, ServerPort);
    }
    LastVoiceControlSendTime = -999.0;
    PortStr = ResolveUrl(Url, "ControlPort");
    if (PortStr != "")
        ControlPort = int(PortStr);
    else
        ControlPort = 6700;

    VoiceListener = Spawn(class'OLTogetherVoiceListener', self);
    if (VoiceListener != None)
        VoiceListener.Init(self, ControlPort);
}
function HideSpeedrunPawn()
{
    if (RemotePawn != None)
    {
        RemotePawn.SetHidden(true);
    }
    bHideLocalPawnDuringSpeedrun = true;
}
function ShowSpeedrunPawn()
{
    if (RemotePawn != None)
    {
        RemotePawn.SetHidden(false);
    }
    bHideLocalPawnDuringSpeedrun = false;
}
function ResetSpeedrunState()
{
    bSpeedrunControlsLocked = false;
    IgnoreMoveInput(false);
    IgnoreLookInput(false);
    bSpeedrunReady = false;
    bPeerIsReady = false;
}
function ResetSpeedrunSequence()
{
    bSpeedrunCountdownActive = false;
    bSpeedrunSequenceActive = false;
    SpeedrunStartTime = WorldInfo.TimeSeconds;
    SpeedrunCountdownStartTime = 0.0;
    ResetSpeedrunState();
    ShowSpeedrunPawn();
    AddNotification("GO!");
}
function CountDownTickCommon(name TickName)
{
    local float T;
    T = WorldInfo.TimeSeconds - SpeedrunCountdownStartTime;
    SpeedrunCountdownElapsed = T;
    SpeedrunOverlayPulse += 0.06;
    SpeedrunOverlayAlpha = FMin(SpeedrunOverlayAlpha + 0.04, 0.85);
    SpeedrunCountdownValue = 5 - int(T);
    if (SpeedrunCountdownValue < 1)
        SpeedrunCountdownValue = 1;
    if (T >= 5.0)
    {
        SpeedrunCountdownValue = 0;
        SpeedrunCountdownElapsed = 5.0;
        ClearTimer(TickName);
        ResetSpeedrunSequence();
        if (ConnectionLink != None)
            ConnectionLink.SendText("SRUN,GO\n");
    }
}
function BeginSpeedrunCountdown(name TickName)
{
    SpeedrunCountdownValue = 5;
    SpeedrunCountdownStartTime = WorldInfo.TimeSeconds;
    SpeedrunCountdownElapsed = 0.0;
    SpeedrunOverlayPulse = 0.0;
    SetTimer(0.02, true, TickName);
}
event PlayerTick(float DeltaTime)
{
    local string Packet;
    local vector ProjectedLoc, EasedLoc, VelForAnim;
    local rotator EasedRot;
    local AIController SpawnedAI;
    local OLHero RemoteHero, MyHero;
    local int DoorState, LeanState, ExtraState, ExtraKind;
    local float GapToRemote;
    local bool bFadeNow;
    super.PlayerTick(DeltaTime);
    if (bSpeedrunControlsLocked)
    {
        if (bIgnoreMoveInput == 0) IgnoreMoveInput(true);
        if (bIgnoreLookInput == 0) IgnoreLookInput(true);
    }
    if (ConnectionLink != None && !ConnectionLink.bIsConnected && Settings != None && Settings.bAutoReconnect
        && WorldInfo.TimeSeconds - LastReconnectAttempt > FMax(1.0, Settings.ReconnectDelay))
    {
        LastReconnectAttempt = WorldInfo.TimeSeconds;
        ConnectionLink.Reconnect();
    }
    if (ConnectionLink != None && ConnectionLink.bIsConnected)
    {
        if (!bPlayerNameAnnounced || LocalPlayerName != LastSentPlayerName || WorldInfo.TimeSeconds - LastPlayerNameSendTime > 1.0)
        {
            ConnectionLink.SendText("NAME," $ LocalPlayerName $ "\n");
            bPlayerNameAnnounced = true;
            LastSentPlayerName = LocalPlayerName;
            LastPlayerNameSendTime = WorldInfo.TimeSeconds;
        }
        if (WorldInfo.TimeSeconds - LastPingSendTime > 1.0)
        {
            LastPingSendTime = WorldInfo.TimeSeconds;
            ConnectionLink.SendText("PING," $ string(int(WorldInfo.TimeSeconds * 1000.0)) $ "\n");
        }
        if (bMicTransmitting != bLastSentTalking)
        {
            bLastSentTalking = bMicTransmitting;
            ConnectionLink.SendText("TALK," $ int(bMicTransmitting) $ "\n");
        }
    }
    if (ConnectionLink != None && ConnectionLink.bIsConnected && Pawn != None && WorldInfo.TimeSeconds - LastStateSendTime > 0.05)
    {
        LastStateSendTime = WorldInfo.TimeSeconds;
        MyHero = OLHero(Pawn);
        DoorState = 0;
        if (MyHero != None)
        {
            switch (int(MyHero.SpecialMove))
            {
                case 28: case 29: case 30: case 31: case 32:
                    DoorState = int(MyHero.DoorOpeningType); break;
                case 33: case 34:
                    DoorState = int(MyHero.DoorClosingType); break;
            }
        }
        LeanState = (bLeanInputLeft != 0) ? 1 : (bLeanInputRight != 0) ? 2 : 0;
        ExtraState = 0;
        ExtraKind = 0;
        if (MyHero != None)
        {
            ExtraState = int(MyHero.bLeftAnim);
            ExtraKind = int(MyHero.ActiveLedgeTransitionType);
        }
        Packet = "LOC,"
            $ Pawn.Location.X $ "," $ Pawn.Location.Y $ "," $ Pawn.Location.Z $ ","
            $ Rotation.Pitch $ "," $ Rotation.Yaw $ ","
            $ Pawn.Velocity.X $ "," $ Pawn.Velocity.Y $ "," $ Pawn.Velocity.Z $ ","
            $ int(Pawn.bIsCrouched) $ ","
            $ (MyHero != None ? int(MyHero.bCamcorderDesired) : 0) $ ","
            $ (MyHero != None ? int(MyHero.CamcorderState) : 0) $ ","
            $ (MyHero != None ? int(MyHero.LocomotionMode) : 0) $ ","
            $ (MyHero != None ? int(MyHero.SpecialMove) : 0) $ ","
            $ DoorState $ "," $ LeanState $ "," $ ExtraState $ "," $ ExtraKind $ ","
            $ (MyHero != None ? int(MyHero.PreciseHealth) : 100);
        ConnectionLink.SendText(Packet $ "\n");
    }
    if (VoiceListener != None && VoiceListener.bClientConnected && Pawn != None && WorldInfo.TimeSeconds - LastVoiceControlSendTime > 0.05)
    {
        LastVoiceControlSendTime = WorldInfo.TimeSeconds;
        // Full 3D position + camera yaw (in degrees) for 3D spatial audio.
        // UE3 rotator Yaw is in unreal-units (65536 = 360 deg); convert to degrees.
        VoiceListener.SendControl(
            "POS,"
            $ Pawn.Location.X $ ","
            $ Pawn.Location.Y $ ","
            $ Pawn.Location.Z $ ","
            $ (Rotation.Yaw * (360.0 / 65536.0))
        );
        VoiceListener.SendControl("PTT," $ int(bMicTransmitting));
        if (Settings != None)
            VoiceListener.SendControl("PROX," $ int(Settings.VoiceProximityNear) $ "," $ int(Settings.VoiceProximityFar));
    }
    if (RemotePawn == None && Pawn != None)
    {
        RemotePawn = Spawn(class'OLTogetherHero',,, Pawn.Location, Pawn.Rotation,, true);
        if (RemotePawn != None)
        {
            RemotePawn.SetPhysics(PHYS_Walking);
            RemotePawn.SetCollision(false, false, false);
            RemotePawn.bCollideWorld = false;
            SpawnedAI = Spawn(class'AIController');
            if (SpawnedAI != None)
                SpawnedAI.Possess(RemotePawn, false);
            RemoteHero = OLHero(RemotePawn);
            if (RemoteHero != None)
            {
                if (RemoteHero.Mesh != None)
                {
                    RemoteHero.Mesh.SetHidden(true);
                    RemoteHero.Mesh.SetOwnerNoSee(true);
                    RemoteHero.Mesh.bUpdateSkelWhenNotRendered = true;
                    RemoteHero.Mesh.bTickAnimNodesWhenNotRendered = true;
                }
                if (RemoteHero.ShadowProxy != None)
                {
                    RemoteHero.ShadowProxy.SetOwnerNoSee(false);
                    RemoteHero.ShadowProxy.SetHidden(bHideLocalPawnDuringSpeedrun);
                    RemoteHero.ShadowProxy.bUpdateSkelWhenNotRendered = true;
                    RemoteHero.ShadowProxy.bTickAnimNodesWhenNotRendered = true;
                }
                if (RemoteHero.HeadMesh != None)
                {
                    RemoteHero.HeadMesh.SetHidden(bHideLocalPawnDuringSpeedrun);
                    RemoteHero.HeadMesh.SetOwnerNoSee(false);
                }
                if (RemoteHero.CameraMeshShadowProxy != None)
                {
                    RemoteHero.CameraMeshShadowProxy.SetHidden(true);
                    MyHero = OLHero(Pawn);
                    if (MyHero != None && MyHero.CameraMesh != None)
                        RemoteHero.CameraMeshShadowProxy.SetSkeletalMesh(MyHero.CameraMesh.SkeletalMesh);
                }
            }
        }
    }
    if (RemotePawn != None && bHasReceivedData)
    {
        ProjectedLoc = LastReceivedLoc;
        ProjectedLoc.X += LastReceivedVel.X * DeltaTime;
        ProjectedLoc.Y += LastReceivedVel.Y * DeltaTime;
        ProjectedLoc.Z += LastReceivedVel.Z * DeltaTime;
        LastReceivedLoc = ProjectedLoc;
        if (LastLocomotionMode >= 2 && LastLocomotionMode <= 6)
            EasedLoc = LastReceivedLoc;
        else
            EasedLoc = VInterpTo(RemotePawn.Location, ProjectedLoc, DeltaTime, InterpSpeed);
        RemotePawn.SetLocation(EasedLoc);
        EasedRot = RInterpTo(RemotePawn.Rotation, LastReceivedRot, DeltaTime, InterpSpeed);
        EasedRot.Pitch = 0;
        RemotePawn.SetRotation(EasedRot);
        if (OLTogetherHero(RemotePawn) != None)
            OLTogetherHero(RemotePawn).RemotePitch = LastReceivedRot.Pitch;
        VelForAnim = LastReceivedVel;
        if (LastLocomotionMode != 3)
            VelForAnim.Z = 0;
        RemotePawn.Velocity = VelForAnim;
        RemotePawn.Acceleration = VelForAnim;
        UpdateDummyMovementAnim();
        RemoteHero = OLHero(RemotePawn);
        if (RemoteHero != None)
        {
            if (LastLocomotionMode == 0 && LastLeanInputDir != 0 && (bRemotePawnCrouched || VSize(VelForAnim) < 50.0))
                RemoteHero.CurrentLean = (LastLeanInputDir == 1) ? -1.0 : 1.0;
            else
                RemoteHero.CurrentLean = 0.0;
        }
        if (RemoteHero != None && Pawn != None)
        {
            if (bHideLocalPawnDuringSpeedrun)
            {
                RemotePawn.SetHidden(true);
            }
            else if (ConnectionLink != None && ConnectionLink.bFadeNearbyPlayers)
            {
                GapToRemote = VSize(EasedLoc - Pawn.Location);
                bFadeNow = (GapToRemote < ConnectionLink.NearbyFadeDistance);
                if (!bFadeNow && RemoteHero.ShadowProxy != None && RemoteHero.ShadowProxy.HiddenGame)
                    bFadeNow = (GapToRemote < ConnectionLink.NearbyFadeDistance + ConnectionLink.NearbyFadeHysteresis);
                if (RemoteHero.ShadowProxy != None)
                    RemoteHero.ShadowProxy.SetHidden(bFadeNow);
                if (RemoteHero.HeadMesh != None)
                    RemoteHero.HeadMesh.SetHidden(bFadeNow);
                if (bFadeNow && RemoteHero.CameraMeshShadowProxy != None)
                    RemoteHero.CameraMeshShadowProxy.SetHidden(true);
            }
        }
    }
}
exec function SetServerAddress(string NewIP)
{
    if (NewIP == "") return;
    ServerAddress = NewIP;
    if (ConnectionLink != None)
        ConnectionLink.SetServer(ServerAddress, ServerPort);
}
exec function SetServerPort(string NewPort)
{
    if (NewPort == "") return;
    ServerPort = NewPort;
    if (ConnectionLink != None)
        ConnectionLink.SetServer(ServerAddress, ServerPort);
}
exec function ConnectToServer()
{
    if (ConnectionLink != None) ConnectionLink.Reconnect();
}
exec function ToggleMouseSmoothing()
{
    if (PlayerInput != None)
    {
        PlayerInput.bEnableMouseSmoothing = !PlayerInput.bEnableMouseSmoothing;
        PlayerInput.SaveConfig();
        AddNotification(PlayerInput.bEnableMouseSmoothing ? "Mouse Smoothing: On" : "Mouse Smoothing: Off");
    }
}
exec function SetMouseSmoothing(bool bEnable)
{
    if (PlayerInput != None)
    {
        PlayerInput.bEnableMouseSmoothing = bEnable;
        PlayerInput.SaveConfig();
    }
}
function ApplySettings()
{
    if (Settings == None) return;
    if (PlayerInput != None)
        PlayerInput.SaveConfig();
}
Function LoadCheckpoint(string Checkpoint)
{
    StartNewGameAtCheckpoint(Checkpoint, false);
}
function SafeLoadCheckpoint(string Checkpoint)
{
    if (Checkpoint != "Admin_Gates")
        Checkpoint = "Admin_Gates";
    LoadCheckpoint(Checkpoint);
}
exec function ToggleSettingsMenu()
{
    local OLTogetherHUD H;
    if (bChatMode) return;
    H = OLTogetherHUD(HUD);
    if (H != None)
    {
        H.ToggleSettingsMenu();
        bSettingsMenuOpen = H.bSettingsOpen;
    }
}
function bool IsSettingsMenuOpen()
{
    local OLTogetherHUD H;
    H = OLTogetherHUD(HUD);
    return H != None && H.bSettingsOpen;
}
function SettingsMenuClick()
{
    local OLTogetherHUD H;
    H = OLTogetherHUD(HUD);
    if (H != None) H.SettingsMenuClick(self);
}
function SettingsMenuInput(name Key)
{
    local OLTogetherHUD H;
    H = OLTogetherHUD(HUD);
    if (H == None) return;
    switch (Key)
    {
        case 'Up':    H.SettingsMoveSelection(-1); break;
        case 'Down':  H.SettingsMoveSelection(1);  break;
        case 'Left':  H.SettingsAdjust(self, -1);  break;
        case 'Right': H.SettingsAdjust(self, 1);   break;
        case 'Enter': H.SettingsAdjust(self, 0);   break;
        case 'Escape':
            if (H.InRebindTab())
            {
                H.SettingsTabTarget = 0.0;
                H.SettingsTabTransitionVariant = Rand(H.NUM_SETTINGS_ANIMS);
                H.SettingsHighlightedRow = 8;
                H.RebindSlotIndex = -1;
                H.HoveredSettingsRow = -1;
            }
            else
            {
                H.CloseSettingsMenu();
                bSettingsMenuOpen = false;
            }
            break;
    }
}
exec function ForceStartSpeedrun()
{
    if (!bSpeedrunMode || PlayerRole != 0) return;
    bPeerIsReady = true;
    bSpeedrunReady = true;
    BeginSpeedrunSequence();
    ToggleSettingsMenu();
}
exec function ToggleSpeedrunReady()
{
    if (!bSpeedrunMode || bSpeedrunSequenceActive) return;
    bSpeedrunReady = !bSpeedrunReady;
    if (bSpeedrunReady)
    {
        ConnectionLink.SendText("SRUN,READY\n");
        AddNotification("Ready - waiting for others...");
        if (bPeerIsReady) BeginSpeedrunSequence();
    }
    else
        ConnectionLink.SendText("SRUN,UNREADY\n");
}
function BeginSpeedrunSequence()
{
    local OLHero HeroRef;
    if (bSpeedrunSequenceActive || SpeedrunStartTime > 0.0) return;
    bSpeedrunSequenceActive = true;
    bSpeedrunCountdownActive = true;
    SpeedrunSequenceStartTime = WorldInfo.TimeSeconds;
    SpeedrunOverlayAlpha = 0.0;
    IgnoreMoveInput(true);
    IgnoreLookInput(true);
    bSpeedrunControlsLocked = true;
    HeroRef = OLHero(Pawn);
    if (HeroRef != None)
    {
        SpeedrunLockLocation = HeroRef.Location;
        SpeedrunLockRotation = HeroRef.Rotation;
    }
    AddNotification("Starting race...");
    if (PlayerRole == 0 && ConnectionLink != None)
        ConnectionLink.SendText("SRUN,SEQ\n");
    SafeLoadCheckpoint("Admin_Gates");
    SetTimer(3.0, false, 'SpeedrunSequenceTeleport');
}
function SpeedrunSequenceTeleport()
{
    HideSpeedrunPawn();
    if (PlayerRole == 0 && ConnectionLink != None)
        ConnectionLink.SendText("SRUN,TP\n");
    SetTimer(1.5, false, 'SpeedrunSequenceStartCountdown');
}
function SpeedrunSequenceStartCountdown()
{
    bSpeedrunControlsLocked = false;
    IgnoreMoveInput(true);
    IgnoreLookInput(true);
    bSpeedrunControlsLocked = true;
    BeginSpeedrunCountdown('SpeedrunCountdownTick');
}
function SpeedrunCountdownTick()
{
    local float T;
    T = WorldInfo.TimeSeconds - SpeedrunCountdownStartTime;
    SpeedrunCountdownElapsed = T;
    SpeedrunOverlayPulse += 0.06;
    SpeedrunOverlayAlpha = FMin(SpeedrunOverlayAlpha + 0.04, 0.85);
    SpeedrunCountdownValue = 5 - int(T);
    if (SpeedrunCountdownValue < 1) SpeedrunCountdownValue = 1;
    if (T >= 5.0)
    {
        SpeedrunCountdownValue = 0;
        SpeedrunCountdownElapsed = 5.0;
        ClearTimer('SpeedrunCountdownTick');
        ResetSpeedrunSequence();
        if (ConnectionLink != None)
            ConnectionLink.SendText("SRUN,GO\n");
    }
}
function BeginSpeedrunSequenceClient()
{
    local OLHero HeroRef;
    if (bSpeedrunSequenceActive) return;
    bSpeedrunSequenceActive = true;
    bSpeedrunCountdownActive = true;
    SpeedrunSequenceStartTime = WorldInfo.TimeSeconds;
    SpeedrunOverlayAlpha = 0.0;
    IgnoreMoveInput(true);
    IgnoreLookInput(true);
    bSpeedrunControlsLocked = true;
    HeroRef = OLHero(RemotePawn);
    if (HeroRef != None)
    {
        SpeedrunLockLocation = HeroRef.Location;
        SpeedrunLockRotation = HeroRef.Rotation;
    }
    AddNotification("Starting race...");
}
function SpeedrunSequenceTeleportClient()
{
    HideSpeedrunPawn();
    SetTimer(1.5, false, 'SpeedrunSequenceStartCountdownClient');
}
function SpeedrunSequenceStartCountdownClient()
{
    BeginSpeedrunCountdown('SpeedrunCountdownTickClient');
}
function SpeedrunCountdownTickClient()
{
    local float T;
    T = WorldInfo.TimeSeconds - SpeedrunCountdownStartTime;
    SpeedrunCountdownElapsed = T;
    SpeedrunOverlayPulse += 0.06;
    SpeedrunOverlayAlpha = FMin(SpeedrunOverlayAlpha + 0.04, 0.85);
    SpeedrunCountdownValue = 5 - int(T);
    if (SpeedrunCountdownValue < 1) SpeedrunCountdownValue = 1;
    if (T >= 5.0)
    {
        SpeedrunCountdownValue = 0;
        SpeedrunCountdownElapsed = 5.0;
        ClearTimer('SpeedrunCountdownTickClient');
        bSpeedrunCountdownActive = false;
        bSpeedrunSequenceActive = false;
        SpeedrunStartTime = WorldInfo.TimeSeconds;
        SpeedrunCountdownStartTime = 0.0;
        ResetSpeedrunState();
        ShowSpeedrunPawn();
        AddNotification("GO!");
    }
}
function SpeedrunRemoteGo()
{
    ClearTimer('SpeedrunCountdownTickClient');
    bSpeedrunCountdownActive = false;
    bSpeedrunSequenceActive = false;
    SpeedrunStartTime = WorldInfo.TimeSeconds;
    SpeedrunCountdownStartTime = 0.0;
    ResetSpeedrunState();
    ShowSpeedrunPawn();
    AddNotification("GO!");
}
function CheckSpeedrunCheckpoint(name CheckpointName)
{
    local string Label;
    local float FT;
    if (!bSpeedrunMode || bSpeedrunSequenceActive || SpeedrunStartTime == 0.0) return;
    Label = string(CheckpointName);
    if (Label == "Lab_BigStairDone" && SpeedrunFinishTime == 0.0)
    {
        FT = WorldInfo.TimeSeconds - SpeedrunStartTime;
        SpeedrunFinishTime = FT;
        AddNotification("Finished! Time: " $ int(FT) $ "." $ int((FT % 1.0) * 100));
    }
}
exec function SetLocalPlayerName(string NewName)
{
    if (NewName == "") return;
    LocalPlayerName = NewName;
    bPlayerNameAnnounced = false;
    LastSentPlayerName = "";
    if (ConnectionLink != None && ConnectionLink.bIsConnected)
        ConnectionLink.SendText("NAME," $ LocalPlayerName $ "\n");
}
exec function Chat(string Message)
{
    if (Message == "") return;
    if (ConnectionLink != None && ConnectionLink.bIsConnected)
    {
        ConnectionLink.SendText("CHAT," $ LocalPlayerName $ ": " $ Message $ "\n");
        AddChatLine("You: " $ Message);
    }
    else
        AddChatLine("Chat failed - not connected.");
}
function AddChatLine(string Msg)
{
    local OLTogetherHUD H;
    if (Msg == "") return;
    H = OLTogetherHUD(HUD);
    if (H != None) H.AddChatLine(Msg);
}
function AddNotification(string Msg)
{
    local OLTogetherHUD H;
    if (Msg == "") return;
    H = OLTogetherHUD(HUD);
    if (H != None) H.AddNotification(Msg);
}
function PlayBodyAnim(name AnimName, float BlendIn, float BlendOut, bool bLoop, float Rate)
{
    local OLHero TH;
    TH = OLHero(RemotePawn);
    if (TH == None) return;
    if (TH.ShadowProxyFullBodyAnimSlot != None)
        TH.ShadowProxyFullBodyAnimSlot.PlayCustomAnim(AnimName, Rate, BlendIn, BlendOut, bLoop, true);
    else if (TH.ShadowProxy != None)
        TH.ShadowProxy.PlayAnim(AnimName, Rate, bLoop, true, BlendIn);
}
function StopBodyAnim(float BlendOut)
{
    local OLHero TH;
    TH = OLHero(RemotePawn);
    if (TH != None && TH.ShadowProxyFullBodyAnimSlot != None)
        TH.ShadowProxyFullBodyAnimSlot.StopCustomAnim(BlendOut);
}
function UpdateDummyMovementAnim()
{
    local OLHero RH;
    local vector FV, FD, SD, VD;
    local float FS, FDt, SDt, YR;
    local name AP;
    RH = OLHero(RemotePawn);
    if (RH == None || RH.ShadowProxy == None) return;
    if (WorldInfo.TimeSeconds < AnimLockEndTime || LastLocomotionMode != 0) return;
    if (!bRemotePawnCrouched)
    {
        if (LastMovementAnim != 'None')
        {
            LastMovementAnim = 'None';
            StopBodyAnim(0.15);
        }
        RH.LocomotionMode = LM_Walk;
        return;
    }
    FV = LastReceivedVel;
    FV.Z = 0;
    FS = VSize(FV);
    if (FS < 20.0)
    {
        AP = (LastLeanInputDir == 1) ? 'player_crouch_lean_left' : (LastLeanInputDir == 2) ? 'player_crouch_lean_right' : 'player_crouch_idle';
    }
    else
    {
        YR = RemotePawn.Rotation.Yaw * (3.1415927 / 180.0);
        FD.X = Cos(YR); FD.Y = Sin(YR); FD.Z = 0;
        SD.X = Cos(YR + 1.5707963); SD.Y = Sin(YR + 1.5707963); SD.Z = 0;
        VD = FV / FS;
        FDt = (VD.X * FD.X) + (VD.Y * FD.Y);
        SDt = (VD.X * SD.X) + (VD.Y * SD.Y);
        AP = (FDt > 0.7) ? 'player_crouch_forward' : (FDt < -0.7) ? 'player_crouch_backward' : (SDt > 0.0) ? 'player_crouch_strafe_right' : 'player_crouch_strafe_left';
    }
    if (AP != LastMovementAnim)
    {
        LastMovementAnim = AP;
        PlayBodyAnim(AP, 0.2, 0.0, true, 1.0);
    }
}
function HideCamcorderProp()
{
    local OLHero RH;
    RH = OLHero(RemotePawn);
    if (RH != None && RH.CameraMeshShadowProxy != None)
        RH.CameraMeshShadowProxy.SetHidden(true);
}
function PlayCamcorderIdleAnim()
{
    local OLHero RH;
    RH = OLHero(RemotePawn);
    if (RH != None && RH.ShadowProxyRightArmAnimSlot != None)
        RH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
            bRemotePawnCrouched ? 'player_crouch_camcorder_idle' : 'player_camcorder_idle', 1.0, 0.05, -1.0, true, true);
}
function FinishInactiveReload()
{
    local OLHero RH;
    RH = OLHero(RemotePawn);
    if (RH == None) return;
    if (RH.CameraMeshShadowProxy != None)
        RH.CameraMeshShadowProxy.SetHidden(true);
    if (RH.ShadowProxyRightArmAnimSlot != None)
        RH.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
    if (RH.ShadowProxyLeftArmAnimSlot != None)
        RH.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
}
function OnReceiveData(string Data)
{
    local array<string> F;
    local vector IL, IV;
    local rotator IR;
    local bool BC, CC;
    local int CS, LM, PL, SM, DD, LD, ED, ET, HP;
    local float SMs, NMs;
    local OLHero RH;
    if (Left(Data, 5) == "CHAT,") { AddChatLine(Right(Data, Len(Data) - 5)); return; }
    if (Left(Data, 5) == "NAME,")
    {
        RemotePlayerName = Right(Data, Len(Data) - 5);
        if (RemotePlayerName == "") RemotePlayerName = "Player";
        return;
    }
    if (Left(Data, 5) == "PONG,")
    {
        F = SplitString(Data, ",", true);
        if (F.Length >= 2)
        {
            SMs = float(F[1]);
            NMs = WorldInfo.TimeSeconds * 1000.0;
            RoundTripPingMs = int(NMs - SMs);
        }
        return;
    }
    if (Left(Data, 6) == "NOTIF,") { AddNotification(Right(Data, Len(Data) - 6)); return; }
    if (Left(Data, 5) == "SRUN,") { HandleSpeedrunPacket(Data); return; }
    if (Left(Data, 5) == "TALK,")
    {
        F = SplitString(Data, ",", true);
        if (F.Length >= 2) bRemoteTalking = (int(F[1]) != 0);
        return;
    }
    F = SplitString(Data, ",", true);
    if (F.Length < 17 || F[0] != "LOC") return;
    IL.X = float(F[1]); IL.Y = float(F[2]); IL.Z = float(F[3]);
    IR.Pitch = int(F[4]); IR.Yaw = int(F[5]); IR.Roll = 0;
    IV.X = float(F[6]); IV.Y = float(F[7]); IV.Z = float(F[8]);
    CC = int(F[9]) != 0;
    BC = int(F[10]) != 0;
    CS = int(F[11]);
    LM = int(F[12]);
    SM = int(F[13]);
    DD = int(F[14]);
    LD = (F.Length >= 16) ? int(F[15]) : 0;
    ED = (F.Length >= 17) ? int(F[16]) : 0;
    ET = (F.Length >= 18) ? int(F[17]) : 0;
    HP = (F.Length >= 19) ? int(F[18]) : 100;
    LastReceivedLoc = IL;
    LastReceivedVel = IV;
    if (LM != 3 && LM != 4 && LM != 5 && LM != 6 && LM != 10)
    {
        LastReceivedRot = IR;
    }
    RemoteHealth = HP;
    bHasReceivedData = true;
    if (RemotePawn == None) return;
    RH = OLHero(RemotePawn);
    LastLeanInputDir = LD;
    if (CC != bRemotePawnCrouched)
    {
        bRemotePawnCrouched = CC;
        AnimLockEndTime = WorldInfo.TimeSeconds + 0.55;
        if (bRemotePawnCrouched)
            PlayBodyAnim('player_stand_to_crouch', 0.1, 0.0, false, 1.0);
        else
            PlayBodyAnim('player_crouch_to_stand', 0.1, 0.0, false, 1.0);
    }
    if (BC != bLastRemoteCamcorder)
    {
        bLastRemoteCamcorder = BC;
        RH.bCamcorderDesired = BC;
        if (RH.CameraMeshShadowProxy != None)
        {
            if (BC) { ClearTimer('HideCamcorderProp'); RH.CameraMeshShadowProxy.SetHidden(false); }
            else SetTimer(0.55, false, 'HideCamcorderProp');
        }
        if (RH.ShadowProxyRightArmAnimSlot != None)
        {
            if (BC)
            {
                RH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(bRemotePawnCrouched ? 'player_crouch_camcorder_raise' : 'player_camcorder_raise', 1.0, 0.15, 0.15, false, true);
                SetTimer(0.50, false, 'PlayCamcorderIdleAnim');
            }
            else
            {
                ClearTimer('PlayCamcorderIdleAnim');
                RH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(bRemotePawnCrouched ? 'player_crouch_camcorder_lower' : 'player_camcorder_lower', 1.0, 0.15, 0.15, false, true);
            }
        }
    }
    if (CS != LastRemoteCamcorderState)
    {
        if (CS == 4)
        {
            ClearTimer('PlayCamcorderIdleAnim');
            ClearTimer('FinishInactiveReload');
            if (RH.ShadowProxyRightArmAnimSlot != None)
                RH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(bRemotePawnCrouched ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload', 1.0, 0.15, 0.05, false, true);
            if (RH.ShadowProxyLeftArmAnimSlot != None)
                RH.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(bRemotePawnCrouched ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload', 1.0, 0.15, 0.4, false, true);
            SetTimer(2.85, false, 'PlayCamcorderIdleAnim');
        }
        else if (CS == 5)
        {
            ClearTimer('PlayCamcorderIdleAnim');
            ClearTimer('FinishInactiveReload');
            if (RH.CameraMeshShadowProxy != None && !bHideLocalPawnDuringSpeedrun)
                RH.CameraMeshShadowProxy.SetHidden(false);
            if (RH.ShadowProxyRightArmAnimSlot != None)
                RH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(bRemotePawnCrouched ? 'player_crouch_camcorder_reload_inactive' : 'player_camcorder_reload_inactive', 1.0, 0.15, 0.05, false, true);
            if (RH.ShadowProxyLeftArmAnimSlot != None)
                RH.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
            SetTimer(2.85, false, 'FinishInactiveReload');
        }
        else if (LastRemoteCamcorderState == 4 || LastRemoteCamcorderState == 5)
        {
            ClearTimer('PlayCamcorderIdleAnim');
            ClearTimer('FinishInactiveReload');
            if (CS == 1 && BC)
            {
                PlayCamcorderIdleAnim();
                if (RH.ShadowProxyLeftArmAnimSlot != None)
                    RH.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.2);
            }
            else
            {
                if (RH.CameraMeshShadowProxy != None)
                    RH.CameraMeshShadowProxy.SetHidden(true);
                if (RH.ShadowProxyRightArmAnimSlot != None)
                    RH.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
                if (RH.ShadowProxyLeftArmAnimSlot != None)
                    RH.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
            }
        }
        LastRemoteCamcorderState = CS;
    }
    if (LM != LastLocomotionMode)
    {
        PL = LastLocomotionMode;
        LastLocomotionMode = LM;
        if (LM == 3 || LM == 4)
        {
            if (RH.CameraMeshShadowProxy != None)
                RH.CameraMeshShadowProxy.SetHidden(true);
            if (RH.ShadowProxyRightArmAnimSlot != None)
                RH.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
            if (RH.ShadowProxyLeftArmAnimSlot != None)
                RH.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
        }
        else if ((PL == 3 || PL == 4) && bLastRemoteCamcorder)
        {
            if (RH.CameraMeshShadowProxy != None)
                RH.CameraMeshShadowProxy.SetHidden(false);
            PlayCamcorderIdleAnim();
        }
        switch (LM)
        {
            case 1:
                RH.LocomotionMode = LM_Fall;
                LastMovementAnim = 'None';
                LastLeanInputDir = 0;
                break;
            case 2:
                switch (SM)
                {
                    case 3:  PlayBodyAnim('player_jump_on_spot', 0.1, 0.0, false, 1.0); break;
                    case 5:  PlayBodyAnim((VSize(IV) > 300.0 ? 'player_jump_over_from_run' : 'player_jump_over_from_walk'), 0.1, 0.0, false, 1.0); break;
                    case 6:  PlayBodyAnim('player_jump_over_to_ledge', 0.1, 0.0, false, 1.0); break;
                    case 7:  PlayBodyAnim('player_slide_over_from_run', 0.1, 0.0, false, 1.0); break;
                    case 8:  PlayBodyAnim((VSize(IV) > 300.0 ? 'player_climb_up_from_run' : 'player_climb_up_from_walk'), 0.1, 0.0, false, 1.0); break;
                    case 9:  PlayBodyAnim('player_climb_up_wall_2m', 0.1, 0.0, false, 1.0); break;
                    case 10: PlayBodyAnim('player_climb_over_wall_2m', 0.1, 0.0, false, 1.0); break;
                    case 14: PlayBodyAnim('player_jump_to_ledge_from_walk', 0.1, 0.0, false, 1.0); break;
                    case 17: PlayBodyAnim('player_climb_ledge_to_stand', 0.1, 0.0, false, 1.0); break;
                    case 18: PlayBodyAnim('player_ledge_walk_stepoff', 0.1, 0.0, false, 1.0); break;
                    case 19: PlayBodyAnim('player_climb_ledge_to_stand', 0.1, 0.0, false, 1.0); break;
                    case 4:  PlayBodyAnim('player_landing_big', 0.05, 0.1, false, 1.0); break;
                    case 16:
                        switch (ET)
                        {
                            case 1:  PlayBodyAnim('player_ledge_move_left_90_outside', 0.1, 0.0, false, 1.0); break;
                            case 2:  PlayBodyAnim('player_ledge_move_right_90_inside', 0.1, 0.0, false, 1.0); break;
                            case 3:  PlayBodyAnim('player_ledge_move_right_90_outside', 0.1, 0.0, false, 1.0); break;
                            default: PlayBodyAnim('player_ledge_move_left_90_inside', 0.1, 0.0, false, 1.0); break;
                        }
                        break;
                    case 20:
                        switch (ET)
                        {
                            case 1:  PlayBodyAnim('player_ledge_walk_enter_left_outside_perp', 0.1, 0.0, false, 1.0); break;
                            case 2:  PlayBodyAnim('player_ledge_walk_enter_right_inside_perp', 0.1, 0.0, false, 1.0); break;
                            case 3:  PlayBodyAnim('player_ledge_walk_enter_right_outside_perp', 0.1, 0.0, false, 1.0); break;
                            default: PlayBodyAnim('player_ledge_walk_enter_left_inside_perp', 0.1, 0.0, false, 1.0); break;
                        }
                        break;
                    case 21:
                        switch (ET)
                        {
                            case 1:  PlayBodyAnim('player_ledge_walk_exit_left_outside_left', 0.1, 0.0, false, 1.0); break;
                            case 2:  PlayBodyAnim('player_ledge_walk_exit_right_inside_left', 0.1, 0.0, false, 1.0); break;
                            case 3:  PlayBodyAnim('player_ledge_walk_exit_right_outside_right', 0.1, 0.0, false, 1.0); break;
                            default: PlayBodyAnim('player_ledge_walk_exit_left_inside_right', 0.1, 0.0, false, 1.0); break;
                        }
                        break;
                    case 22:
                        switch (ET)
                        {
                            case 1:  PlayBodyAnim('player_ledge_walk_transition_left_90_outside', 0.1, 0.0, false, 1.0); break;
                            case 2:  PlayBodyAnim('player_ledge_walk_transition_right_90_inside', 0.1, 0.0, false, 1.0); break;
                            case 3:  PlayBodyAnim('player_ledge_walk_transition_right_90_outside', 0.1, 0.0, false, 1.0); break;
                            default: PlayBodyAnim('player_ledge_walk_transition_left_90_inside', 0.1, 0.0, false, 1.0); break;
                        }
                        break;
                    case 23: PlayBodyAnim('player_jump_from_ledge_walk', 0.1, 0.0, false, 1.0); break;
                    case 24: PlayBodyAnim((ED != 0) ? 'player_squeeze_enter_left' : 'player_squeeze_enter_right', 0.1, 0.0, false, 1.0); break;
                    case 25: PlayBodyAnim((ED != 0) ? 'player_squeeze_exit_left' : 'player_squeeze_exit_right', 0.1, 0.0, false, 1.0); break;
                    case 26: PlayBodyAnim('player_squeeze_through', 0.1, 0.0, false, 1.0); break;
                    case 27:
                        if (RH.ShadowProxyRightArmAnimSlot != None)
                            RH.ShadowProxyRightArmAnimSlot.PlayCustomAnim(bLastRemoteCamcorder ? 'player_squeeze_camera_reload' : 'player_squeeze_camera_reload_inactive', 1.0, 0.15, 0.05, false, true);
                        if (RH.ShadowProxyLeftArmAnimSlot != None)
                            RH.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(bLastRemoteCamcorder ? 'player_squeeze_camera_reload' : 'player_squeeze_camera_reload_inactive', 1.0, 0.15, 0.4, false, true);
                        break;
                    case 44: PlayBodyAnim('player_ladder_enter_above', 0.1, 0.0, false, 1.0); break;
                    case 48: PlayBodyAnim('player_ladder_grab_from_air', 0.1, 0.0, false, 1.0); break;
                    case 28:
                        LastDoorInputDir = DD;
                        PlayBodyAnim((DD < 2) ? 'player_door_access_left' : 'player_door_access_right', 0.1, 0.0, false, 1.0);
                        break;
                    case 29:
                        switch (DD)
                        {
                            case 0: PlayBodyAnim('player_door_open_push_left', 0.1, 0.0, false, 1.0); break;
                            case 1: PlayBodyAnim('player_door_open_pull_left', 0.1, 0.0, false, 1.0); break;
                            case 2: PlayBodyAnim('player_door_open_push_right', 0.1, 0.0, false, 1.0); break;
                            default: PlayBodyAnim('player_door_open_pull_right', 0.1, 0.0, false, 1.0); break;
                        }
                        break;
                    case 30: PlayBodyAnim((DD < 2) ? 'player_door_open_inside_left' : 'player_door_open_inside_right', 0.1, 0.0, false, 1.0); break;
                    case 31: PlayBodyAnim((DD < 2) ? 'player_door_locked_left' : 'player_door_locked_right', 0.1, 0.0, false, 1.0); break;
                    case 32: PlayBodyAnim((DD < 2) ? 'player_run_door_open_left' : 'player_run_door_open_right', 0.05, 0.1, false, 1.0); break;
                    case 33: case 34:
                        switch (DD)
                        {
                            case 0: PlayBodyAnim('player_door_close_left_front', 0.1, 0.0, false, 1.0); break;
                            case 1: PlayBodyAnim('player_door_close_left_side', 0.1, 0.0, false, 1.0); break;
                            case 2: PlayBodyAnim('player_door_close_left_back', 0.1, 0.0, false, 1.0); break;
                            case 3: PlayBodyAnim('player_door_close_inside_left', 0.1, 0.0, false, 1.0); break;
                            case 4: PlayBodyAnim('player_door_close_right_front', 0.1, 0.0, false, 1.0); break;
                            case 5: PlayBodyAnim('player_door_close_right_side', 0.1, 0.0, false, 1.0); break;
                            case 6: PlayBodyAnim('player_door_close_right_back', 0.1, 0.0, false, 1.0); break;
                            default: PlayBodyAnim('player_door_close_inside_right', 0.1, 0.0, false, 1.0); break;
                        }
                        break;
                    case 37: PlayBodyAnim('player_locker_open_straight', 0.1, 0.2, false, 1.0); break;
                    case 38: PlayBodyAnim('player_locker_hide', 0.3, -1.0, true, 1.0); break;
                    case 39: PlayBodyAnim('player_locker_exit', 0.1, 0.1, false, 1.0); break;
                    case 40:
                        PlayBodyAnim(
                            bRemotePawnCrouched ? ((ED != 0) ? 'player_enter_bed_left' : 'player_enter_bed_right') : ((ED != 0) ? 'player_enter_bed_left_stand' : 'player_enter_bed_right_stand'),
                            0.15, 0.0, false, 1.0);
                        break;
                    case 41: PlayBodyAnim((ED != 0) ? 'player_exit_bed_left' : 'player_exit_bed_right', 0.1, 0.1, false, 1.0); break;
                    case 49: PlayBodyAnim(bRemotePawnCrouched ? 'player_crouch_object_pickup_h45v35' : 'player_object_pickup_h62v105', 0.1, 0.1, false, 1.0); break;
                    case 54: PlayBodyAnim((ED != 0) ? 'player_push_object_enter_left' : 'player_push_object_enter_right', 0.1, 0.0, false, 1.0); break;
                    case 55: PlayBodyAnim((ED != 0) ? 'player_push_object_exit_left' : 'player_push_object_exit_right', 0.1, 0.0, false, 1.0); break;
                    case 57: PlayBodyAnim('player_crouch_over_ledge', 0.1, 0.0, false, 1.0); break;
                    case 62: PlayBodyAnim('player_grab', 0.1, 0.0, false, 1.0); break;
                    case 67: PlayBodyAnim('player_grab_throw', 0.1, 0.0, false, 1.0); break;
                    case 69: case 70: PlayBodyAnim('player_stand_death', 0.1, 0.0, false, 1.0); break;
                }
                LastMovementAnim = 'None';
                LastLeanInputDir = 0;
                break;
            case 7:
                PlayBodyAnim((LastDoorInputDir < 2) ? 'player_door_access_left' : 'player_door_access_right', 0.15, -1.0, true, 1.0);
                LastMovementAnim = 'None';
                LastLeanInputDir = 0;
                break;
            case 8:
                PlayBodyAnim('player_locker_hide', 0.2, -1.0, true, 1.0);
                LastMovementAnim = 'None';
                LastLeanInputDir = 0;
                break;
            case 3:  RH.LocomotionMode = LM_Ladder;         LastMovementAnim = 'None'; LastLeanInputDir = 0; break;
            case 4:  RH.LocomotionMode = LM_LedgeHang;      LastMovementAnim = 'None'; LastLeanInputDir = 0; break;
            case 5:  RH.LocomotionMode = LM_LedgeWalk;      LastMovementAnim = 'None'; LastLeanInputDir = 0; break;
            case 15: RH.LocomotionMode = LM_ContextualLean; LastMovementAnim = 'None'; LastLeanInputDir = 0; break;
            case 6:  RH.LocomotionMode = LM_Squeeze;        LastMovementAnim = 'None'; LastLeanInputDir = 0; break;
            case 10: RH.LocomotionMode = LM_Bed;            LastMovementAnim = 'None'; LastLeanInputDir = 0; break;
            case 12: RH.LocomotionMode = LM_Struggle;       LastMovementAnim = 'None'; LastLeanInputDir = 0; break;
            case 13: RH.LocomotionMode = LM_Grabbed;        LastMovementAnim = 'None'; LastLeanInputDir = 0; break;
            case 14: RH.LocomotionMode = LM_Pushing;        LastMovementAnim = 'None'; LastLeanInputDir = 0; break;
            case 0: default:
                RH.LocomotionMode = LM_Walk;
                if (PL == 1) PlayBodyAnim('player_land', 0.05, 0.1, false, 1.0);
                else if (PL == 7) StopBodyAnim(0.15);
                else if (PL == 8) PlayBodyAnim('player_locker_exit', 0.1, 0.1, false, 1.0);
                else if (PL == 3 || PL == 4 || PL == 5) StopBodyAnim(0.15);
                else if (PL == 6 || PL == 12 || PL == 13 || PL == 14) StopBodyAnim(0.2);
                LastMovementAnim = 'None';
                LastLeanInputDir = 0;
                break;
        }
    }
}
function HandleSpeedrunPacket(string Data)
{
    local array<string> F;
    F = SplitString(Data, ",", true);
    if (F.Length < 2) return;
    if (F[1] == "READY")    { bPeerIsReady = true; if (bSpeedrunReady && !bSpeedrunSequenceActive) BeginSpeedrunSequence(); }
    else if (F[1] == "UNREADY") bPeerIsReady = false;
    else if (F[1] == "SEQ")  BeginSpeedrunSequenceClient();
    else if (F[1] == "TP")   SpeedrunSequenceTeleportClient();
    else if (F[1] == "GO")   SpeedrunRemoteGo();
}
defaultproperties
{
    InputClass=class'Multiplayer.OLTogetherInput'
    bHasReceivedData=false
    InterpSpeed=12.0
    bLastRemoteCamcorder=false
    LastRemoteCamcorderState=0
    bLocalRunning=false
    bRemotePawnCrouched=false
    LastLocomotionMode=0
    LastDoorInputDir=0
    LastLeanInputDir=0
    RemoteHealth=100
    bSpeedrunSequenceActive=false
    bSpeedrunControlsLocked=false
    bHideLocalPawnDuringSpeedrun=false
    SpeedrunOverlayAlpha=0.0
    SpeedrunOverlayPulse=0.0
}
