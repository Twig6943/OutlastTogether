class OLTogetherController extends OLPlayerController;

var OLTogetherLink NetworkLink;
var Pawn DummyPlayer;
var int MyRole;
var float LastSendTime;
var float LastPingTime;
var int PingMs;
var string ServerIP;
var string ServerPort;
var string ConnectionStatus;
var string PlayerName;
var string DummyPlayerName;
var bool bNameAnnounced;
var string LastAnnouncedName;
var float LastNameAnnounceTime;
var bool bChatMode;
var string ChatInput;

// --- Dead Reckoning & Interpolation state ---
var vector LastReceivedLoc;
var vector LastReceivedVel;
var rotator LastReceivedRot;
var bool bHasReceivedData;

// --- Last known remote states (for change detection) ---
var int LastRemoteSpecialMove;
var bool bLastRemoteCamcorder;
var int LastRemoteCamcorderState;
var bool bDummyCrouched;
var name LastMovementAnim;

// --- Running state from local player ---
var bool bLocalRunning;

// How fast the dummy smoothly slides toward the target position.
var float InterpSpeed;
var int IdleRetryAttempts;

function string GetUrlOptionValue(string Url, string OptionName)
{
    local array<string> Parts;
    local string Prefix;
    local int I;
    local int Pos;

    Prefix = OptionName $ "=";
    Parts = SplitString(Url, "?", true);
    for (I = 0; I < Parts.Length; I++)
    {
        Pos = InStr(Parts[I], Prefix);
        if (Pos == 0)
            return Right(Parts[I], Len(Parts[I]) - Len(Prefix));
    }
    return "";
}

event PostBeginPlay()
{
    local string Url;
    local string IpOption;
    local string PortOption;
    local string RoleOption;
    local string PlayerNameOption;

    super.PostBeginPlay();

    Url = WorldInfo.GetLocalURL();

    RoleOption = WorldInfo.Game.ParseOption(Url, "Role");
    if (RoleOption == "")
        RoleOption = GetUrlOptionValue(Url, "Role");
    MyRole = int(RoleOption);

    ServerIP = "127.0.0.1";
    ServerPort = "7777";
    PlayerName = "";
    IpOption = WorldInfo.Game.ParseOption(Url, "ServerIP");
    if (IpOption == "")
        IpOption = GetUrlOptionValue(Url, "ServerIP");
    PortOption = WorldInfo.Game.ParseOption(Url, "ServerPort");
    if (PortOption == "")
        PortOption = GetUrlOptionValue(Url, "ServerPort");
    PlayerNameOption = WorldInfo.Game.ParseOption(Url, "PlayerName");
    if (PlayerNameOption == "")
        PlayerNameOption = GetUrlOptionValue(Url, "PlayerName");

    if (IpOption != "")
        ServerIP = IpOption;
    if (PortOption != "")
        ServerPort = PortOption;
    if (PlayerNameOption != "")
        PlayerName = PlayerNameOption;
    if (PlayerName == "")
        PlayerName = "Player" @ (MyRole == 0 ? "Host" : "Client");

    ConnectionStatus = "Connecting...";
    LastPingTime = 0.0;
    PingMs = 0;
    bNameAnnounced = false;
    LastAnnouncedName = "";
    LastNameAnnounceTime = -999.0;
    bChatMode = false;
    ChatInput = "";

    NetworkLink = Spawn(class'OLTogetherLink', self);
    if (NetworkLink != None)
    {
        NetworkLink.ControllerOwner = self;
        NetworkLink.IP = ServerIP;
        NetworkLink.Port = ServerPort;
        NetworkLink.SetServer(ServerIP, ServerPort);
    }
}

event PlayerTick(float DeltaTime)
{
    local string Payload;
    local vector ExtrapolatedLoc, SmoothedLoc, AnimVel;
    local rotator SmoothedRot;
    local AIController AIC;
    local int LocalSpecialMoveInt;

    super.PlayerTick(DeltaTime);

    // --- Try to reconnect if needed ---
    if (NetworkLink != None && !NetworkLink.bIsConnected && WorldInfo.TimeSeconds - LastSendTime > 5.0)
    {
        LastSendTime = WorldInfo.TimeSeconds;
        NetworkLink.Reconnect();
    }

    // --- Announce player name when connected or when it changes ---
    if (NetworkLink != None && NetworkLink.bIsConnected)
    {
        if (!bNameAnnounced || PlayerName != LastAnnouncedName || WorldInfo.TimeSeconds - LastNameAnnounceTime > 1.0)
        {
            NetworkLink.SendText("NAME," $ PlayerName $ "\n");
            bNameAnnounced = true;
            LastAnnouncedName = PlayerName;
            LastNameAnnounceTime = WorldInfo.TimeSeconds;
        }
    }

    // --- Send ping periodically ---
    if (NetworkLink != None && NetworkLink.bIsConnected && WorldInfo.TimeSeconds - LastPingTime > 1.0)
    {
        LastPingTime = WorldInfo.TimeSeconds;
        NetworkLink.SendText("PING," $ string(int(WorldInfo.TimeSeconds * 1000.0)) $ "\n");
    }

    // --- Send local player state ---
    if (NetworkLink != None && NetworkLink.bIsConnected && Pawn != None)
    {
        if (WorldInfo.TimeSeconds - LastSendTime > 0.05)
        {
            LocalSpecialMoveInt = 0;
            bLocalRunning = false;
            if (OLHero(Pawn) != None)
            {
                LocalSpecialMoveInt = int(OLHero(Pawn).SpecialMove);
                bLocalRunning = OLHero(Pawn).IsRunning();
            }

            LastSendTime = WorldInfo.TimeSeconds;
            Payload = "LOC,"
                $ Pawn.Location.X $ "," $ Pawn.Location.Y $ "," $ Pawn.Location.Z $ ","
                $ Pawn.Rotation.Pitch $ "," $ Pawn.Rotation.Yaw $ ","
                $ Pawn.Velocity.X $ "," $ Pawn.Velocity.Y $ "," $ Pawn.Velocity.Z $ ","
                $ LocalSpecialMoveInt $ "," 
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).bCamcorderDesired) : 0) $ ","
                $ (OLHero(Pawn) != None ? int(OLHero(Pawn).CamcorderState) : 0) $ ","
                $ (bLocalRunning ? 1 : 0);
            `log("OLTogetherController: Sending LocalSpecialMove=" $ LocalSpecialMoveInt);
            NetworkLink.SendText(Payload $ "\n");
        }
    }

    // --- Spawn dummy once ---
    if (DummyPlayer == None && Pawn != None)
    {
        DummyPlayer = Spawn(class'OLTogetherHero',,, Pawn.Location, Pawn.Rotation,, true);
        if (DummyPlayer != None)
        {
            DummyPlayer.SetPhysics(PHYS_Walking);
            DummyPlayer.SetCollision(false, false, false);
            DummyPlayer.bCollideWorld = false;

            AIC = Spawn(class'AIController');
            if (AIC != None)
                AIC.Possess(DummyPlayer, false);

            if (OLHero(DummyPlayer) != None)
            {
                if (OLHero(DummyPlayer).Mesh != None)
                {
                    OLHero(DummyPlayer).Mesh.SetHidden(true);
                    OLHero(DummyPlayer).Mesh.SetOwnerNoSee(true);
                    OLHero(DummyPlayer).Mesh.bUpdateSkelWhenNotRendered = true;
                    OLHero(DummyPlayer).Mesh.bTickAnimNodesWhenNotRendered = true;
                }
                if (OLHero(DummyPlayer).ShadowProxy != None)
                {
                    OLHero(DummyPlayer).ShadowProxy.SetOwnerNoSee(false);
                    OLHero(DummyPlayer).ShadowProxy.SetHidden(false);
                    OLHero(DummyPlayer).ShadowProxy.bUpdateSkelWhenNotRendered = true;
                    OLHero(DummyPlayer).ShadowProxy.bTickAnimNodesWhenNotRendered = true;
                }
                if (OLHero(DummyPlayer).HeadMesh != None)
                {
                    OLHero(DummyPlayer).HeadMesh.SetHidden(false);
                    OLHero(DummyPlayer).HeadMesh.SetOwnerNoSee(false);
                }
                if (OLHero(DummyPlayer).CameraMeshShadowProxy != None)
                    OLHero(DummyPlayer).CameraMeshShadowProxy.SetHidden(true);
            }
        }
    }

    // --- Dead Reckoning + Interpolation ---
    if (DummyPlayer != None && bHasReceivedData)
    {
        ExtrapolatedLoc = LastReceivedLoc;
        ExtrapolatedLoc.X += LastReceivedVel.X * DeltaTime;
        ExtrapolatedLoc.Y += LastReceivedVel.Y * DeltaTime;
        ExtrapolatedLoc.Z += LastReceivedVel.Z * DeltaTime;
        LastReceivedLoc = ExtrapolatedLoc;

        SmoothedLoc = VInterpTo(DummyPlayer.Location, ExtrapolatedLoc, DeltaTime, InterpSpeed);
        DummyPlayer.SetLocation(SmoothedLoc);

        SmoothedRot = RInterpTo(DummyPlayer.Rotation, LastReceivedRot, DeltaTime, InterpSpeed);
        SmoothedRot.Pitch = 0;
        DummyPlayer.SetRotation(SmoothedRot);

        if (OLTogetherHero(DummyPlayer) != None)
            OLTogetherHero(DummyPlayer).RemotePitch = LastReceivedRot.Pitch;

        AnimVel = LastReceivedVel;
        AnimVel.Z = 0;
        DummyPlayer.Velocity = AnimVel;
        DummyPlayer.Acceleration = AnimVel;

        UpdateDummyMovementAnim();
    }
}

exec function SetServerIP(string NewIP)
{
    if (NewIP == "")
        return;

    ServerIP = NewIP;
    if (NetworkLink != None)
        NetworkLink.SetServer(ServerIP, ServerPort);
}

exec function SetServerPort(string NewPort)
{
    if (NewPort == "")
        return;

    ServerPort = NewPort;
    if (NetworkLink != None)
        NetworkLink.SetServer(ServerIP, ServerPort);
}

exec function ConnectToServer()
{
    if (NetworkLink != None)
        NetworkLink.Reconnect();
}

exec function SetPlayerName(string NewName)
{
    if (NewName == "")
        return;

    PlayerName = NewName;
    bNameAnnounced = false;
    LastAnnouncedName = "";
    if (NetworkLink != None && NetworkLink.bIsConnected)
        NetworkLink.SendText("NAME," $ PlayerName $ "\n");
}

exec function Chat(string Message)
{
    if (Message == "")
        return;

    if (NetworkLink != None && NetworkLink.bIsConnected)
    {
        NetworkLink.SendText("CHAT," $ PlayerName $ ": " $ Message $ "\n");
        AddChatLine("You: " $ Message);
    }
    else
    {
        AddChatLine("Chat failed - not connected.");
    }
}

function AddChatLine(string Msg)
{
    local OLTogetherHUD H;

    if (Msg == "")
        return;

    H = OLTogetherHUD(HUD);
    if (H != None)
        H.AddChatLine(Msg);
}

function AddNotification(string Msg)
{
    local OLTogetherHUD H;

    if (Msg == "")
        return;

    H = OLTogetherHUD(HUD);
    if (H != None)
        H.AddNotification(Msg);
}

function UpdateDummyMovementAnim()
{
    local OLHero DummyHero;
    local vector Vel2D, Forward, Right, NormVel;
    local float Speed, ForwardDot, RightDot;
    local name DesiredAnim;
    local float YawRad;

    DummyHero = OLHero(DummyPlayer);
    if (DummyHero == None || DummyHero.ShadowProxy == None)
        return;

    Vel2D = LastReceivedVel;
    Vel2D.Z = 0;
    Speed = VSize(Vel2D);

    if (bDummyCrouched)
    {
        if (Speed < 20.0)
        {
            DesiredAnim = 'player_crouch_idle';
        }
        else
        {
            YawRad = DummyPlayer.Rotation.Yaw * (3.1415927 / 180.0);
            Forward.X = Cos(YawRad);
            Forward.Y = Sin(YawRad);
            Forward.Z = 0;
            Right.X = Cos(YawRad + 1.5707963);
            Right.Y = Sin(YawRad + 1.5707963);
            Right.Z = 0;
            NormVel = Vel2D / Speed;
            ForwardDot = (NormVel.X * Forward.X) + (NormVel.Y * Forward.Y);
            RightDot = (NormVel.X * Right.X) + (NormVel.Y * Right.Y);

            if (ForwardDot > 0.7)
                DesiredAnim = 'player_crouch_forward';
            else if (ForwardDot < -0.7)
                DesiredAnim = 'player_crouch_backward';
            else if (RightDot > 0.0)
                DesiredAnim = 'player_crouch_strafe_right';
            else
                DesiredAnim = 'player_crouch_strafe_left';
        }
    }
    else
    {
        if (Speed < 20.0)
        {
            DesiredAnim = 'player_idle';
        }
        else
        {
            YawRad = DummyPlayer.Rotation.Yaw * (3.1415927 / 180.0);
            Forward.X = Cos(YawRad);
            Forward.Y = Sin(YawRad);
            Forward.Z = 0;
            Right.X = Cos(YawRad + 1.5707963);
            Right.Y = Sin(YawRad + 1.5707963);
            Right.Z = 0;
            NormVel = Vel2D / Speed;
            ForwardDot = (NormVel.X * Forward.X) + (NormVel.Y * Forward.Y);
            RightDot = (NormVel.X * Right.X) + (NormVel.Y * Right.Y);

            if (ForwardDot > 0.7)
            {
                if (Speed > 400.0)
                    DesiredAnim = 'player_run_forward';
                else
                    DesiredAnim = 'player_walk_forward';
            }
            else if (ForwardDot < -0.7)
                DesiredAnim = 'player_walk_backward';
            else if (RightDot > 0.0)
                DesiredAnim = 'player_strafe_right';
            else
                DesiredAnim = 'player_strafe_left';
        }
    }

    if (DesiredAnim != LastMovementAnim)
    {
        LastMovementAnim = DesiredAnim;
        DummyHero.ShadowProxy.PlayAnim(DesiredAnim, 1.0, false, true, 0.15);
    }
}

function HideCamcorderProp()
{
    local OLHero DummyHero;
    DummyHero = OLHero(DummyPlayer);
    if (DummyHero != None && DummyHero.CameraMeshShadowProxy != None)
        DummyHero.CameraMeshShadowProxy.SetHidden(true);
}

function PlayCrouchIdleAnim()
{
    local OLHero DummyHero;
    DummyHero = OLHero(DummyPlayer);
    if (DummyHero == None)
        return;

    if (DummyHero.ShadowProxy != None)
        DummyHero.ShadowProxy.PlayAnim(
            bDummyCrouched ? 'player_crouch_idle' : 'player_idle', 1.0, true, true, 0.05);

    if (DummyHero.ShadowProxyRightArmAnimSlot != None && DummyHero.bCamcorderDesired)
        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
            bDummyCrouched ? 'player_crouch_camcorder_idle' : 'player_camcorder_idle', 1.0, 0.05, -1.0, true, true);
}

function PlayCamcorderIdleAnim()
{
    local OLHero DummyHero;
    DummyHero = OLHero(DummyPlayer);
    if (DummyHero != None && DummyHero.ShadowProxyRightArmAnimSlot != None)
        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
            bDummyCrouched ? 'player_crouch_camcorder_idle' : 'player_camcorder_idle', 1.0, 0.05, -1.0, true, true);
}

function FinishInactiveReload()
{
    local OLHero DummyHero;
    DummyHero = OLHero(DummyPlayer);
    if (DummyHero != None)
    {
        if (DummyHero.CameraMeshShadowProxy != None)
            DummyHero.CameraMeshShadowProxy.SetHidden(true);
        if (DummyHero.ShadowProxyRightArmAnimSlot != None)
            DummyHero.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
        if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
            DummyHero.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
    }
}

function OnReceiveData(string Data)
{
    local array<string> Parts;
    local array<string> PingParts;
    local vector NewLoc, NewVel;
    local rotator NewRot;
    local int NewSpecialMove;
    local bool bNewCamcorder;
    local int NewCamcorderState;
    local bool bRemoteRunning;
    local float SentMs;
    local float NowMs;
    local OLHero DummyHero;

    if (Left(Data, 5) == "CHAT,")
    {
        AddChatLine(Right(Data, Len(Data) - 5));
        return;
    }

    if (Left(Data, 5) == "NAME,")
    {
        DummyPlayerName = Right(Data, Len(Data) - 5);
        if (DummyPlayerName == "")
            DummyPlayerName = "Player";
        return;
    }

    if (Left(Data, 5) == "PONG,")
    {
        PingParts = SplitString(Data, ",", true);
        if (PingParts.Length >= 2)
        {
            SentMs = float(PingParts[1]);
            NowMs = WorldInfo.TimeSeconds * 1000.0;
            PingMs = int(NowMs - SentMs);
        }
        return;
    }

    if (Left(Data, 6) == "NOTIF,")
    {
        AddNotification(Right(Data, Len(Data) - 6));
        return;
    }

    Parts = SplitString(Data, ",", true);
    if (Parts.Length >= 12 && Parts[0] == "LOC")
    {
        NewLoc.X = float(Parts[1]);
        NewLoc.Y = float(Parts[2]);
        NewLoc.Z = float(Parts[3]);
        NewRot.Pitch = int(Parts[4]);
        NewRot.Yaw = int(Parts[5]);
        NewRot.Roll = 0;
        NewVel.X = float(Parts[6]);
        NewVel.Y = float(Parts[7]);
        NewVel.Z = float(Parts[8]);
        NewSpecialMove = int(Parts[9]);
        bNewCamcorder = int(Parts[10]) != 0;
        NewCamcorderState = int(Parts[11]);
        bRemoteRunning = (Parts.Length >= 13) ? (int(Parts[12]) != 0) : false;

        LastReceivedLoc = NewLoc;
        LastReceivedVel = NewVel;
        LastReceivedRot = NewRot;
        bHasReceivedData = true;

        if (DummyPlayer != None)
        {
            DummyHero = OLHero(DummyPlayer);

            // --- Detect and Sync Remote Player Special Moves ---
            if (NewSpecialMove != LastRemoteSpecialMove)
            {
                `log("OLTogetherController: NewSpecialMove=" $ NewSpecialMove);
                LastRemoteSpecialMove = NewSpecialMove;

                if (DummyHero != None)
                {
                    // FIXED: Using clear explicit enum conversion matching SMT_Crouch/SMT_Uncrouch definitions directly
                    if (ESpecialMoveType(NewSpecialMove) == SMT_Crouch)
                    {
                        `log("OLTogetherController: Detected SMT_Crouch");
                        bDummyCrouched = true;

                        // Prefer using the pawn's StartSpecialMove to ensure game logic and anims run
                        DummyHero.StartSpecialMove(ESpecialMoveType(NewSpecialMove));
                        if (DummyHero.ShadowProxy != None)
                        {
                            DummyHero.ShadowProxy.PlayAnim('player_stand_to_crouch', 1.0, false, true, 0.15);
                        }
                        if (DummyHero.Mesh != None)
                        {
                            DummyHero.Mesh.PlayAnim('player_stand_to_crouch', 1.0, false, true, 0.15);
                        }

                        // Mirror the real game: SMT_Crouch transitions back to SMT_None, then hold crouch idle.
                        DummyHero.SpecialMove = SMT_None;
                        DummyHero.bPlayingSpecialMoveAnim = false;
                        DummyHero.bDelayedSpecialMoveAnim = false;
                        DummyHero.bPendingSpecialMoveAnims = false;
                        DummyHero.PlayingSpecialMoveAnims.Length = 0;
                        DummyHero.LocomotionMode = LM_Walk;

                        ClearTimer('PlayCrouchIdleAnim');
                        SetTimer(0.15, false, 'PlayCrouchIdleAnim');
                    }
                    else if (ESpecialMoveType(NewSpecialMove) == SMT_None && bDummyCrouched)
                    {
                        `log("OLTogetherController: Detected SMT_None while crouched");

                        // Stay crouched until explicit uncrouch arrives.
                        ClearTimer('PlayCrouchIdleAnim');
                        SetTimer(0.10, false, 'PlayCrouchIdleAnim');
                    }
                    else if (ESpecialMoveType(NewSpecialMove) == SMT_Uncrouch)
                    {
                        `log("OLTogetherController: Detected SMT_Uncrouch");
                        // Clear crouched state for camcorder/animation selection
                        bDummyCrouched = false;

                        // Trigger the pawn's special-move exit to restore standard locomotion
                        DummyHero.StartSpecialMove(ESpecialMoveType(NewSpecialMove));
                        // Ensure the pawn's special-move state is cleared so animations resume
                        DummyHero.SpecialMove = SMT_None;
                        DummyHero.bPlayingSpecialMoveAnim = false;
                        DummyHero.bDelayedSpecialMoveAnim = false;
                        DummyHero.bPendingSpecialMoveAnims = false;
                        DummyHero.PlayingSpecialMoveAnims.Length = 0;
                        DummyHero.LocomotionMode = LM_Walk;
                        if (DummyHero.ShadowProxy != None)
                        {
                            DummyHero.ShadowProxy.PlayAnim('player_crouch_to_stand', 1.0, false, true, 0.15);
                        }
                        if (DummyHero.Mesh != None)
                        {
                            DummyHero.Mesh.PlayAnim('player_crouch_to_stand', 1.0, false, true, 0.15);
                        }
                    }
                }
            }

            // --- Sync Camcorder ---
            if (bNewCamcorder != bLastRemoteCamcorder)
            {
                bLastRemoteCamcorder = bNewCamcorder;
                DummyHero.bCamcorderDesired = bNewCamcorder;

                if (DummyHero.ShadowProxyRightArmAnimSlot != None)
                {
                    if (bNewCamcorder)
                    {
                        ClearTimer('HideCamcorderProp');
                        if (DummyHero.CameraMeshShadowProxy != None)
                            DummyHero.CameraMeshShadowProxy.SetHidden(false);
                        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_raise' : 'player_camcorder_raise', 1.0, 0.15, 0.15, false, true);
                        SetTimer(0.50, false, 'PlayCamcorderIdleAnim');
                    }
                    else
                    {
                        ClearTimer('PlayCamcorderIdleAnim');
                        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_lower' : 'player_camcorder_lower', 1.0, 0.15, 0.15, false, true);
                        SetTimer(0.55, false, 'HideCamcorderProp');
                    }
                }
            }

            // --- Sync Reloading ---
            if (NewCamcorderState != LastRemoteCamcorderState)
            {
                if (NewCamcorderState == 4)
                {
                    ClearTimer('PlayCamcorderIdleAnim');
                    ClearTimer('FinishInactiveReload');
                    if (DummyHero.ShadowProxyRightArmAnimSlot != None)
                        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload', 1.0, 0.15, 0.05, false, true);
                    if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
                        DummyHero.ShadowProxyLeftArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_reload' : 'player_camcorder_reload', 1.0, 0.15, 0.4, false, true);
                    SetTimer(2.85, false, 'PlayCamcorderIdleAnim');
                }
                else if (NewCamcorderState == 5)
                {
                    ClearTimer('PlayCamcorderIdleAnim');
                    ClearTimer('FinishInactiveReload');
                    if (DummyHero.CameraMeshShadowProxy != None)
                        DummyHero.CameraMeshShadowProxy.SetHidden(false);
                    if (DummyHero.ShadowProxyRightArmAnimSlot != None)
                        DummyHero.ShadowProxyRightArmAnimSlot.PlayCustomAnim(
                            bDummyCrouched ? 'player_crouch_camcorder_reload_inactive' : 'player_camcorder_reload_inactive', 1.0, 0.15, 0.05, false, true);
                    if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
                        DummyHero.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
                    SetTimer(2.85, false, 'FinishInactiveReload');
                }
                else if (LastRemoteCamcorderState == 4 || LastRemoteCamcorderState == 5)
                {
                    ClearTimer('PlayCamcorderIdleAnim');
                    ClearTimer('FinishInactiveReload');
                    if (NewCamcorderState == 1 && bNewCamcorder)
                    {
                        PlayCamcorderIdleAnim();
                        if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
                            DummyHero.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.2);
                    }
                    else
                    {
                        if (DummyHero.CameraMeshShadowProxy != None)
                            DummyHero.CameraMeshShadowProxy.SetHidden(true);
                        if (DummyHero.ShadowProxyRightArmAnimSlot != None)
                            DummyHero.ShadowProxyRightArmAnimSlot.StopCustomAnim(0.15);
                        if (DummyHero.ShadowProxyLeftArmAnimSlot != None)
                            DummyHero.ShadowProxyLeftArmAnimSlot.StopCustomAnim(0.15);
                    }
                }
                LastRemoteCamcorderState = NewCamcorderState;
            }
        }
    }
}

DefaultProperties
{
    InputClass=class'Multiplayer.OLTogetherInput'
    bHasReceivedData=false
    InterpSpeed=12.0
    bLastRemoteCamcorder=false
    LastRemoteSpecialMove=0
    LastRemoteCamcorderState=0
}

