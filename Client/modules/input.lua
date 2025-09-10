Input.Register("Flashlight", "F")
Input.Bind("Flashlight", InputEvent.Pressed, function()
	if myRole == ROLE_SURVIVOR and not isSpectator then
        Events.CallRemote("ToggleFlashlight")
    end
end)

Input.Register("DropJerrycan", "G")
Input.Bind("DropJerrycan", InputEvent.Pressed, function()
    if myRole == ROLE_SURVIVOR and not isSpectator then
        Events.Call("DropJerrycan")
    end
end)