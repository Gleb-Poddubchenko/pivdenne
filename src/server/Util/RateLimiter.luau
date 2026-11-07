--!strict
-- RateLimiter: per-player token bucket. Use one limiter per remote.

local Players = game:GetService("Players")

export type Limiter = {
	Check: (player: Player) -> boolean,
}

local RateLimiter = {}

-- capacity: burst size. refillPerSecond: sustained rate.
function RateLimiter.new(capacity: number, refillPerSecond: number): Limiter
	local buckets: { [Player]: { tokens: number, last: number } } = {}

	Players.PlayerRemoving:Connect(function(player)
		buckets[player] = nil
	end)

	return {
		Check = function(player: Player): boolean
			local now = os.clock()
			local b = buckets[player]
			if not b then
				b = { tokens = capacity, last = now }
				buckets[player] = b
			end
			b.tokens = math.min(capacity, b.tokens + (now - b.last) * refillPerSecond)
			b.last = now
			if b.tokens < 1 then
				return false
			end
			b.tokens -= 1
			return true
		end,
	}
end

return RateLimiter
