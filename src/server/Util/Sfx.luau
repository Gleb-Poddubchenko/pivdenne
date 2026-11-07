--!strict
-- Sfx: plays positional sounds from the server (replicates to all clients).
-- Empty sound ids are ignored, so missing assets never break gameplay.

local Debris = game:GetService("Debris")

local Sfx = {}

function Sfx.Play(parent: Instance, soundId: string, volume: number?, looped: boolean?): Sound?
	if soundId == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.6
	sound.Looped = looped == true
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 60
	sound.Parent = parent
	sound:Play()
	if not sound.Looped then
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		Debris:AddItem(sound, 15) -- safety net if the asset fails to load
	end
	return sound
end

-- Brief coloured light on a part (key reader LED).
function Sfx.Flash(part: BasePart, color: Color3, duration: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 4
	light.Brightness = 3
	light.Parent = part
	Debris:AddItem(light, duration)
end

return Sfx
