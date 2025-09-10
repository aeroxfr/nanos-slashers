Input.Register("Flashlight", "F")
Input.Bind("Flashlight", InputEvent.Pressed, function()
	if myRole == ROLE_SURVIVOR and not isSpectator then
        Events.CallRemote("ToggleFlashlight")
    end
end)