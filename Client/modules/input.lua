Input.Register("Flashlight", "F")
Input.Bind("Flashlight", InputEvent.Pressed, function()
	if not isSpectator then
        Events.CallRemote("ToggleFlashlight")
    end
end)