----------------------------------------------------------------
-- CustomUI.KillTracker.Parser — parse RVR kill Combat-log lines
----------------------------------------------------------------
if not CustomUI then CustomUI = {} end
CustomUI.KillTracker = CustomUI.KillTracker or {}
CustomUI.KillTracker.Parser = CustomUI.KillTracker.Parser or {}

local Parser = CustomUI.KillTracker.Parser

local function DebugLog(msg)
	if CustomUI.DebugLogging ~= true then
		return
	end
	if type(msg) == "string" then
		msg = towstring(msg)
	end
	if type(msg) ~= "wstring" then
		return
	end
	if LogLuaMessage and SystemData and SystemData.UiLogFilters then
		LogLuaMessage("Lua", SystemData.UiLogFilters.DEBUG, L"[CustomUI.KillTracker] " .. msg)
	end
end

--- Strip caret grammar (^n etc.) from ability / zone text.
function Parser.NormalizeDisplayText(raw)
	if raw == nil then
		return L""
	end
	local s = tostring(towstring(raw))
	s = string.gsub(s, "%^.", "")
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return towstring(s)
end

function Parser.NormalizeNameKey(name)
	if name == nil then
		return nil
	end
	local s = tostring(towstring(name))
	local caret = string.find(s, "^", 1, true)
	if caret then
		s = string.sub(s, 1, caret - 1)
	end
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	if s == "" then
		return nil
	end
	return string.lower(s)
end

--- True when killer and victim are the same player (environmental / self DB lines).
function Parser.IsSelfKill(parsed)
	if type(parsed) ~= "table" then
		return false
	end
	local a = Parser.NormalizeNameKey(parsed.killer)
	local b = Parser.NormalizeNameKey(parsed.victim)
	return a ~= nil and a == b
end

--- Parse engine RVR kill line.
--- Returns table { victim, verb, killer, ability, zone, streak } or nil.
function Parser.ParseKillLine(msg)
	if msg == nil then
		return nil
	end
	local text = towstring(msg)
	if text == L"" then
		return nil
	end

	-- Primary: Victim has been VERB by Killer's Ability in Zone.[ Streak]
	local victim, verb, killer, ability, zone, streak = text:match(
		L"([%a]+) has been ([%a]+) by ([%a]+)'s ([%a%d%p ]-) in ([^%.]+)%.%s*(.*)"
	)

	if not victim then
		-- Fallback closer to UnrealDBAnnouncer (names only)
		victim, killer = text:match(L"([%a]+) has been [%a]+ by ([%a]+)'s [%a%d%p ]+ in [^%.]+%.")
		if victim and killer then
			DebugLog(L"partial parse victim=" .. victim .. L" killer=" .. killer)
			return {
				victim = victim,
				verb = L"killed",
				killer = killer,
				ability = L"",
				zone = L"",
				streak = L"",
			}
		end
		DebugLog(L"unmatched: " .. text)
		return nil
	end

	ability = Parser.NormalizeDisplayText(ability)
	zone = Parser.NormalizeDisplayText(zone)
	streak = Parser.NormalizeDisplayText(streak or L"")

	return {
		victim = victim,
		verb = verb,
		killer = killer,
		ability = ability,
		zone = zone,
		streak = streak,
	}
end
