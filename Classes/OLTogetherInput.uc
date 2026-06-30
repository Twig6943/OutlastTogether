class OLTogetherInput extends OLPlayerInput within OLTogetherController;

var bool bIgnoreNextChar;

function bool Key(int ControllerId, name Key, EInputEvent Event, float AmountDepressed=1.0, bool bGamepad=false)
{
    if (Outer == None)
        return false;

    if (Outer.bChatMode)
    {
        if (Event == IE_Pressed)
        {
            if (Key == 'Enter')
            {
                if (Outer.ChatInput != "")
                    Outer.Chat(Outer.ChatInput);
                Outer.ChatInput = "";
                Outer.bChatMode = false;
                return true;
            }
            if (Key == 'BackSpace')
            {
                if (Len(Outer.ChatInput) > 0)
                    Outer.ChatInput = Left(Outer.ChatInput, Len(Outer.ChatInput) - 1);
                return true;
            }
            if (Key == 'Escape')
            {
                Outer.ChatInput = "";
                Outer.bChatMode = false;
                return true;
            }
            if (Key == 'Space')
            {
                Outer.ChatInput = Outer.ChatInput $ " ";
                return true;
            }
        }

        return true;
    }

    if (Event == IE_Pressed && Key == 'T')
    {
        Outer.bChatMode = true;
        Outer.ChatInput = "";
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

    if (Len(Outer.ChatInput) + Len(Unicode) > 128)
        return true;

    Outer.ChatInput = Outer.ChatInput $ Unicode;
    return true;
}

DefaultProperties
{
    OnReceivedNativeInputKey = Key
    OnReceivedNativeInputChar = Char
}
