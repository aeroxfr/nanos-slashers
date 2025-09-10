Input.Register("Flashlight", "F")

Input.Bind("Flashlight", InputEvent.Pressed, function()
	if myRole == ROLE_SURVIVOR or myRole == ROLE_SLASHER and not isSpectator then
        Events.CallRemote("ToggleFlashlight")
    end
end)