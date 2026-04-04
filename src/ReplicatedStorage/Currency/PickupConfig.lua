-- Tunables for CurrencyPickup.server.lua (world pickups tagged "CurrencyPickup").
-- Attributes on the tagged instance (Model or BasePart):
--   GiveCoins    (number, optional) — coins granted on touch; omit or 0 for none
--   GiveDiamonds (number, optional) — diamonds granted; omit or 0 for none
-- At least one must be > 0. Values are floored and clamped to MaxGivePerAttribute.

return {
	TagName = "CurrencyPickup",
	-- Safety caps per attribute per single collect
	MaxGivePerAttribute = 1_000_000,
	-- Same player cannot re-trigger the same pickup faster than this (seconds)
	TouchDebounceSeconds = 0.35,
	-- Optional sanity check: max distance from player HRP to touched pickup part (studs); set false/nil to skip
	MaxTouchDistanceStuds = 32,
	-- If true, remove the tagged instance after a successful grant; if false, hide via attributes only
	DestroyOnCollect = true,
}
