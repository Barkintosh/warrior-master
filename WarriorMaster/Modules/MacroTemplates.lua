--[[
Warrior Master - Modules/MacroTemplates.lua
Warrior macro templates (pure data + text builders).

Policy (enforced here and re-checked by MacroBuilder.Validate):
- one action per key press; no /castsequence, no /click, no scripts;
- only standard macro options: [stance], [nostance], [equipped],
  [noequipped], [mod], [combat], [nocombat];
- spell, item and equipment-type names come from the game client in the
  player's language (C_Spell.GetSpellName, C_Item.GetItemSubClassInfo,
  INVTYPE_2HWEAPON), with locale fallbacks.
Stance indexes follow the warrior stance bar: 1 Battle, 2 Defensive, 3 Berserker.
]]
local _, ns = ...

local format = string.format

local T = {}
ns.MacroTemplates = T

-- Classic warrior spell IDs (rank 1; /cast uses the highest known rank).
T.SPELLS = {
	charge = 100, intercept = 20252, overpower = 7384, execute = 5308, pummel = 6552,
	shieldbash = 72, taunt = 355, mocking = 694, shieldwall = 871, disarm = 676,
	revenge = 6572, retaliation = 20230, thunderclap = 6343, recklessness = 1719,
	berserkerrage = 18499, whirlwind = 1680, hamstring = 1715, sunder = 7386,
	heroic = 78, cleave = 845, battle = 2457, defensive = 71, berserker = 2458,
}

T.STANCE_INDEX = { battle = 1, defensive = 2, berserker = 3 }
T.STANCE_CHOICES = { "battle", "defensive", "berserker" }
T.STANCE_LABELS = { battle = "STANCE_BATTLE", defensive = "STANCE_DEFENSIVE", berserker = "STANCE_BERSERKER" }

T.CATEGORIES = { "attack", "stance", "defense", "weapons", "utility" }
T.CATEGORY_LABELS = {
	attack = "CAT_ATTACK", stance = "CAT_STANCE", defense = "CAT_DEFENSE",
	weapons = "CAT_WEAPONS", utility = "CAT_UTILITY",
}

local OPT_STARTATTACK_ON = { key = "startattack", kind = "bool", default = true, labelKey = "OPT_STARTATTACK" }
local OPT_STARTATTACK_OFF = { key = "startattack", kind = "bool", default = false, labelKey = "OPT_STARTATTACK" }

T.list = {}
T.byId = {}

local function add(template)
	template.nameKey = "TPL_" .. template.id:upper() .. "_NAME"
	template.descKey = "TPL_" .. template.id:upper() .. "_DESC"
	template.options = template.options or {}
	T.list[#T.list + 1] = template
	T.byId[template.id] = template
end

--- Ability usable in some stances; otherwise the macro switches stance.
local function stanceAbility(id, spell, stances, fallback, category)
	add({
		id = id,
		category = category,
		iconSpell = spell,
		build = function(ctx)
			return {
				"#showtooltip " .. ctx.spell(spell),
				format("/cast [stance:%s] %s; %s", stances, ctx.spell(spell), ctx.spell(fallback)),
			}
		end,
	})
end

-- Attacks -------------------------------------------------------------------------------------
add({
	id = "heroic_cleave",
	category = "attack",
	iconSpell = "heroic",
	options = {
		OPT_STARTATTACK_ON,
		{ key = "modifier", kind = "choice", default = "shift", values = { "shift", "ctrl", "alt" },
			labels = { shift = "MOD_SHIFT", ctrl = "MOD_CTRL", alt = "MOD_ALT" }, labelKey = "OPT_MODIFIER" },
	},
	build = function(ctx)
		local lines = { "#showtooltip" }
		if ctx.opt("startattack") then
			lines[#lines + 1] = "/startattack"
		end
		lines[#lines + 1] = format("/cast [mod:%s] %s; %s", ctx.opt("modifier"), ctx.spell("cleave"), ctx.spell("heroic"))
		return lines
	end,
})

add({
	id = "sunder",
	category = "attack",
	iconSpell = "sunder",
	options = { OPT_STARTATTACK_ON },
	build = function(ctx)
		local lines = { "#showtooltip " .. ctx.spell("sunder") }
		if ctx.opt("startattack") then
			lines[#lines + 1] = "/startattack"
		end
		lines[#lines + 1] = "/cast " .. ctx.spell("sunder")
		return lines
	end,
})

add({
	id = "execute",
	category = "attack",
	iconSpell = "execute",
	options = {
		{ key = "stance", kind = "choice", default = "berserker", values = { "berserker", "battle" },
			labels = { berserker = "STANCE_BERSERKER", battle = "STANCE_BATTLE" }, labelKey = "OPT_EXEC_STANCE" },
	},
	build = function(ctx)
		return {
			"#showtooltip " .. ctx.spell("execute"),
			format("/cast [stance:1/3] %s; %s", ctx.spell("execute"), ctx.spell(ctx.opt("stance"))),
		}
	end,
})

stanceAbility("overpower", "overpower", "1", "battle", "attack")
stanceAbility("whirlwind", "whirlwind", "3", "berserker", "attack")
stanceAbility("thunder_clap", "thunderclap", "1", "battle", "attack")
stanceAbility("hamstring", "hamstring", "1/3", "battle", "attack")
stanceAbility("recklessness", "recklessness", "3", "berserker", "attack")

-- Stance dancing ------------------------------------------------------------------------------------
add({
	id = "charge_intercept",
	category = "stance",
	iconSpell = "charge",
	options = { OPT_STARTATTACK_OFF },
	build = function(ctx)
		local lines = { "#showtooltip" }
		if ctx.opt("startattack") then
			lines[#lines + 1] = "/startattack"
		end
		lines[#lines + 1] = format("/cast [nocombat,stance:1] %s; [combat,stance:3] %s; [nocombat] %s; %s",
			ctx.spell("charge"), ctx.spell("intercept"), ctx.spell("battle"), ctx.spell("berserker"))
		return lines
	end,
})

add({
	id = "interrupt",
	category = "stance",
	iconSpell = "pummel",
	build = function(ctx)
		return {
			"#showtooltip",
			format("/cast [stance:3] %s; [equipped:%s] %s; %s",
				ctx.spell("pummel"), ctx.shields, ctx.spell("shieldbash"), ctx.spell("berserker")),
		}
	end,
})

add({
	id = "stance_toggle",
	category = "stance",
	iconSpell = "battle",
	options = {
		{ key = "first", kind = "choice", default = "battle", values = T.STANCE_CHOICES, labels = T.STANCE_LABELS, labelKey = "OPT_STANCE_A" },
		{ key = "second", kind = "choice", default = "berserker", values = T.STANCE_CHOICES, labels = T.STANCE_LABELS, labelKey = "OPT_STANCE_B" },
	},
	build = function(ctx)
		local a, b = ctx.opt("first"), ctx.opt("second")
		if a == b then
			return { "#showtooltip", "/cast " .. ctx.spell(a) }
		end
		return {
			"#showtooltip",
			format("/cast [stance:%d] %s; %s", T.STANCE_INDEX[a], ctx.spell(b), ctx.spell(a)),
		}
	end,
})

stanceAbility("berserker_rage", "berserkerrage", "3", "berserker", "stance")

-- Defensive -----------------------------------------------------------------------------------------
stanceAbility("taunt", "taunt", "2", "defensive", "defense")
stanceAbility("revenge", "revenge", "2", "defensive", "defense")
stanceAbility("shield_wall", "shieldwall", "2", "defensive", "defense")
stanceAbility("disarm", "disarm", "2", "defensive", "defense")
stanceAbility("mocking_blow", "mocking", "1", "battle", "defense")
stanceAbility("retaliation", "retaliation", "1", "battle", "defense")

-- Weapons ---------------------------------------------------------------------------------------------
add({
	id = "weapon_toggle",
	category = "weapons",
	options = {
		{ key = "twohand", kind = "item", slot = "twohand", labelKey = "OPT_TWOHAND", required = true },
		{ key = "onehand", kind = "item", slot = "mainhand", labelKey = "OPT_ONEHAND", required = true },
		{ key = "shield", kind = "item", slot = "shield", labelKey = "OPT_SHIELD", required = true },
	},
	build = function(ctx)
		return {
			"#showtooltip",
			format("/equipslot [equipped:%s] 16 %s", ctx.twoHand, ctx.item("onehand")),
			format("/equipslot [equipped:%s] 17 %s", ctx.twoHand, ctx.item("shield")),
			format("/equip [noequipped:%s] %s", ctx.twoHand, ctx.item("twohand")),
		}
	end,
})

add({
	id = "defensive_setup",
	category = "weapons",
	iconSpell = "defensive",
	options = {
		{ key = "onehand", kind = "item", slot = "mainhand", labelKey = "OPT_ONEHAND", required = true },
		{ key = "shield", kind = "item", slot = "shield", labelKey = "OPT_SHIELD", required = true },
	},
	build = function(ctx)
		return {
			"#showtooltip " .. ctx.spell("defensive"),
			"/cast [nostance:2] " .. ctx.spell("defensive"),
			"/equipslot 16 " .. ctx.item("onehand"),
			"/equipslot 17 " .. ctx.item("shield"),
		}
	end,
})

-- Utility -----------------------------------------------------------------------------------------------
add({
	id = "startattack",
	category = "utility",
	build = function()
		return { "/startattack" }
	end,
})
