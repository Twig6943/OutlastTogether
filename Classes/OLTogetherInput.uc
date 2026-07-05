class OLTogetherInput extends OLPlayerInput within OLTogetherController;

var bool bIgnoreNextChar;
var IntPoint MousePosition;
var bool bMouseCaptured;

event PlayerInput(float DeltaTime)
{
    local OLTogetherHUD H;
    H = OLTogetherHUD(myHUD);
    if (H != None && (H.bSettingsOpen || Outer.bChatMode))
    {
        if (!bMouseCaptured)
        {
            bMouseCaptured = true;
            MousePosition.X = H.SizeX / 2;
            MousePosition.Y = H.SizeY / 2;
        }
        MousePosition.X = Clamp(MousePosition.X + aMouseX, 0, H.SizeX);
        MousePosition.Y = Clamp(MousePosition.Y - aMouseY, 0, H.SizeY);
        aMouseX = 0;
        aMouseY = 0;
    }
    else
    {
        bMouseCaptured = false;
    }
    Super.PlayerInput(DeltaTime);
}

function bool Key(int ControllerId, name Key, EInputEvent Event, float AmountDepressed=1.0, bool bGamepad=false)
{
    local OLTogetherHUD H;

    if (Outer == None)
        return false;

    H = OLTogetherHUD(Outer.myHUD);
    if (H == None)
        H = OLTogetherHUD(Outer.HUD);

    // While the settings menu is open it captures navigation so movement keys
    // don't leak into gameplay. Mouse click triggers selection.
    if (H != None && H.bSettingsOpen)
    {
        if (H.bRebindListening)
        {
            if (Event == IE_Pressed)
            {
                if (Key == 'Escape')
                {
                    H.bRebindListening = false;
                    H.RebindSlotIndex = -1;
                    return true;
                }
                if (Key != 'LeftMouseButton' && Key != 'RightMouseButton' && Key != 'MiddleMouseButton')
                {
                    H.CaptureRebindKey(Outer, Key);
                    return true;
                }
            }
            return true;
        }

        if (Event == IE_Pressed && Key == 'LeftMouseButton')
        {
            Outer.SettingsMenuClick();
            return true;
        }
        if (Event == IE_Pressed || Event == IE_Repeat)
        {
            switch (Key)
            {
                case 'Up': case 'W':          Outer.SettingsMenuInput('Up');    return true;
                case 'Down': case 'S':        Outer.SettingsMenuInput('Down');  return true;
                case 'Left': case 'A':        Outer.SettingsMenuInput('Left');  return true;
                case 'Right': case 'D':       Outer.SettingsMenuInput('Right'); return true;
                case 'Enter': case 'SpaceBar': Outer.SettingsMenuInput('Enter'); return true;
                case 'Escape': case 'Tilde':  Outer.SettingsMenuInput('Escape'); return true;
            }
        }
        return true;
    }

    // Tilde toggles the settings menu (only when not in chat)
    if (Event == IE_Pressed && Key == Outer.BindOpenSettings && !Outer.bChatMode)
    {
        Outer.ToggleSettingsMenu();
        return true;
    }

    // Ready toggle (when in speedrun mode)
    if (Event == IE_Pressed && Key == Outer.BindSpeedrunReady && Outer.bSpeedrunMode && !Outer.bChatMode)
    {
        Outer.ToggleSpeedrunReady();
        return true;
    }

    if (Event == IE_Pressed && Key == Outer.BindForceStart && Outer.bSpeedrunMode && !Outer.bChatMode)
    {
        Outer.ForceStartSpeedrun();
        return true;
    }

    // Push To Talk enabled: hold the bind to open the mic, release to mute.
    // Push To Talk disabled: each press toggles the mic open/muted.
    if (Event == IE_Pressed && Key == Outer.BindPushToTalk)
    {
        if (Outer.Settings != None && Outer.Settings.bPushToTalk)
            Outer.bMicTransmitting = true;
        else
            Outer.bMicTransmitting = !Outer.bMicTransmitting;
        return true;
    }
    if (Event == IE_Released && Key == Outer.BindPushToTalk)
    {
        if (Outer.Settings != None && Outer.Settings.bPushToTalk)
            Outer.bMicTransmitting = false;
        return true;
    }

    if (Outer.bChatMode)
    {
        if (Event == IE_Pressed && Key == 'LeftMouseButton')
        {
            if (H != None && H.EmojiPickerClick(Outer))
                return true;
        }

        if (Event == IE_Pressed || Event == IE_Repeat)
        {
            if (Key == 'MouseScrollUp')
            {
                if (H != None && H.bEmojiPickerOpen)
                    H.ScrollEmojiPicker(-1);
                else if (H != None)
                    H.ScrollChat(3);
                return true;
            }
            if (Key == 'MouseScrollDown')
            {
                if (H != None && H.bEmojiPickerOpen)
                    H.ScrollEmojiPicker(1);
                else if (H != None)
                    H.ScrollChat(-3);
                return true;
            }
            if (Key == 'PageUp')
            {
                if (H != None && H.bEmojiPickerOpen)
                    H.ScrollEmojiPicker(-6);
                else if (H != None)
                    H.ScrollChat(6);
                return true;
            }
            if (Key == 'PageDown')
            {
                if (H != None && H.bEmojiPickerOpen)
                    H.ScrollEmojiPicker(6);
                else if (H != None)
                    H.ScrollChat(-6);
                return true;
            }
        }
    }

    if (Outer.bChatMode)
    {
        if (Event == IE_Pressed)
        {
            if (Key == 'Enter')
            {
                if (Outer.ChatText != "")
                    Outer.Chat(Outer.ChatText);
                Outer.ChatText = "";
                Outer.bChatMode = false;
                if (H != None)
                    H.CloseEmojiPicker();
                return true;
            }
            if (Key == 'BackSpace')
            {
                if (Len(Outer.ChatText) > 0)
                    Outer.ChatText = Left(Outer.ChatText, Len(Outer.ChatText) - 1);
                return true;
            }
            if (Key == 'Escape')
            {
                Outer.ChatText = "";
                Outer.bChatMode = false;
                if (H != None)
                    H.CloseEmojiPicker();
                return true;
            }
            if (Key == 'Space')
            {
                Outer.ChatText = Outer.ChatText $ " ";
                return true;
            }
        }

        return true;
    }

    if (Event == IE_Pressed && Key == 'T')
    {
        Outer.bChatMode = true;
        Outer.ChatText = "";
        if (H != None)
        {
            H.ResetChatVisibility();
            MousePosition.X = H.SizeX / 2;
            MousePosition.Y = H.SizeY / 2;
        }
        bMouseCaptured = true;
        bIgnoreNextChar = true;
        return true;
    }

    return false;
}

function bool Char(int ControllerId, string Unicode)
{
    if (Outer == None || !Outer.bChatMode)
        return false;

    if (bIgnoreNextChar)
    {
        bIgnoreNextChar = false;
        return true;
    }

    if (Len(Unicode) == 1 && Asc(Unicode) < 32)
        return true;

    if (Len(Outer.ChatText) + Len(Unicode) > 128)
        return true;

    Outer.ChatText = Outer.ChatText $ Unicode;
    return true;
}

DefaultProperties
{
    OnReceivedNativeInputKey = Key
    OnReceivedNativeInputChar = Char
}